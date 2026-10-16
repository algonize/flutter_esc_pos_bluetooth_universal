import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'models/print_ticket.dart';
import 'models/write_pacing.dart';
import 'transport/printer_transport.dart';
import 'utils/write_pacer.dart';

/// How one ticket was sent, for logs and bug reports.
@immutable
class PrintOutcome {
  const PrintOutcome({required this.bytes, required this.elapsed, required this.paced});

  /// Bytes handed to the link.
  final int bytes;

  /// From the first byte handed to the link until the link had taken them all.
  final Duration elapsed;

  /// Whether the ticket was paced (`BluetoothWriteOptions.pacing` not null).
  final bool paced;

  /// The average rate, in kB/s.
  double get kilobytesPerSecond =>
      elapsed.inMilliseconds == 0 ? 0 : bytes / elapsed.inMilliseconds;

  @override
  String toString() =>
      'PrintOutcome($bytes B in ${elapsed.inMilliseconds} ms, '
      '${kilobytesPerSecond.toStringAsFixed(1)} kB/s, ${paced ? 'paced' : 'unpaced'})';
}

/// Feeds tickets to one connected printer at the speed it prints them (see
/// [WritePacing]), so its buffer never overflows and it is never kept waiting.
///
/// Over Wi-Fi the printer's TCP window slows the sender down by itself, which
/// is why `flutter_esc_pos_network_universal` needs no pacing. Bluetooth has
/// nothing like it: a BLE write without response is never refused, and most
/// printers take Classic data before checking for room. So the sender keeps
/// its own account of what the printer has left to print.
///
/// A printer prints an `ESC *` band only once all of it has arrived: the line
/// feed that ends the band prints it. So each band goes out at link speed,
/// and its print time is paid before the next band leaves. The printer gets
/// every band at once and has printed it, give or take the burst, before more
/// data arrives. Paying for a band while sending it gets this backwards: the
/// printer waits idle while a slow band (a barcode, a dark logo) trickles in,
/// then gets the text after it at full speed while it is still printing that
/// band, and a 58 mm printer threw that text away.
///
/// One per connection: the pacing allowance is shared by every ticket sent on
/// the link, as the printer's buffer is. Nothing is read back from the
/// printer.
class PrintSession {
  PrintSession({
    required this._transport,
    required WritePacing? pacing,
    required int widthDots,
    int Function()? nowMicros,
  }) : _pacing = pacing,
       _pacer = WritePacer.of(pacing, widthDots: widthDots, nowMicros: nowMicros);

  final PrinterTransport _transport;
  final WritePacing? _pacing;
  final WritePacer? _pacer;

  /// Sends [ticket] and reports how it went. Completes once the link has
  /// taken every byte; the printing of the last bands is booked, so a ticket
  /// sent next on this link waits for it.
  Future<PrintOutcome> send(PrintTicket ticket) async {
    final pacing = _pacing;
    final pacer = _pacer;
    final clock = Stopwatch()..start();
    if (pacing == null || pacer == null) {
      await _transport.write(ticket.bytes);
    } else {
      final cost = TicketCost(ticket, pacing);
      await _transport.write(
        ticket.bytes,
        gate: (_, start, _) => pacer.wait(cost.dueBefore(start)),
      );
      pacer.book(cost.rest());
    }
    clock.stop();
    return PrintOutcome(bytes: ticket.length, elapsed: clock.elapsed, paced: pacer != null);
  }
}

/// What a ticket costs against the pacer, in bytes of text, and when it is
/// due: a band once all of it has been sent.
///
/// - An image band is charged as the full band it covers: a band trimmed of
///   blank columns still moves a band's height of paper.
/// - A dense band, with [WritePacing.denseThreshold] or more of its bits set
///   (a barcode, a QR code, a dark logo: whatever the picture holds), is
///   charged [WritePacing.darkRatio] times that, so the printer gets the
///   time it needs for it. A lighter band is text and is charged its share
///   alone, whatever its dots: the head prints a row of text at full speed
///   whatever its weight.
/// - Bytes outside any band (a raw ticket, or the commands around an image)
///   are charged as themselves plus their printed dots at the dark rate, so a
///   dense image inside a raw ticket still gets its time.
///
/// Every byte is charged once, however often the link offers a piece again
/// (a write refused for a busy radio, or one retried smaller).
@visibleForTesting
class TicketCost {
  TicketCost(this._ticket, WritePacing pacing)
    : _darkRatio = pacing.darkRatio,
      _denseThreshold = pacing.denseThreshold,
      _costPerDot = (pacing.darkRatio - 1) / 8;

  final PrintTicket _ticket;
  final double _darkRatio;
  final double _denseThreshold;

  /// The extra a printed dot costs outside a band: a solid byte (8 dots)
  /// costs [_darkRatio], a blank one 1.
  final double _costPerDot;

  final Map<int, bool> _dense = {};

  /// Everything before this offset has been paid for.
  int _paid = 0;

  /// The first band that may hold the start of the next piece.
  int _current = 0;

  /// The first band that may overlap what is left to pay for.
  int _scan = 0;

  /// The cost due before the piece starting at [start] may be sent:
  /// everything before it that has not been paid for yet. A band is due once
  /// all of it has gone, so a piece that starts inside a band pays only for
  /// what came before that band.
  double dueBefore(int start) {
    final bands = _ticket.bands;
    while (_current < bands.length && bands[_current].end <= start) {
      _current++;
    }
    final inside = _current < bands.length && bands[_current].start < start;
    return _payTo(inside ? bands[_current].start : start);
  }

  /// The cost of whatever has not been paid for yet: the end of the ticket,
  /// sent but still to print.
  double rest() => _payTo(_ticket.length);

  double _payTo(int to) {
    if (to <= _paid) return 0;
    final cost = _cost(_paid, to);
    _paid = to;
    return cost;
  }

  double _cost(int start, int end) {
    final bytes = _ticket.bytes;
    final bands = _ticket.bands;
    while (_scan < bands.length && bands[_scan].end <= start) {
      _scan++;
    }
    var cost = 0.0;
    var at = start;
    for (var i = _scan; i < bands.length && bands[i].start < end; i++) {
      final band = bands[i];
      final from = math.max(at, band.start);
      final to = math.min(end, band.end);
      if (to <= from) continue;
      if (from > at) cost += _plain(bytes, at, from);
      final share = (to - from) / band.length * band.fullBytes;
      cost += _isDense(i) ? share * _darkRatio : share;
      at = to;
    }
    if (end > at) cost += _plain(bytes, at, end);
    return cost;
  }

  double _plain(Uint8List bytes, int start, int end) =>
      (end - start) + _dotsIn(bytes, start, end) * _costPerDot;

  bool _isDense(int index) => _dense.putIfAbsent(index, () {
    final band = _ticket.bands[index];
    return _dotsIn(_ticket.bytes, band.start, band.end) >= _denseThreshold * band.length * 8;
  });

  static int _dotsIn(Uint8List bytes, int start, int end) {
    var dots = 0;
    for (var i = start; i < end; i++) {
      dots += _bitCount[bytes[i]];
    }
    return dots;
  }

  static final Uint8List _bitCount = Uint8List.fromList([
    for (var b = 0; b < 256; b++) _popCount(b),
  ]);

  static int _popCount(int b) {
    var n = 0;
    for (var v = b; v != 0; v >>= 1) {
      n += v & 1;
    }
    return n;
  }
}

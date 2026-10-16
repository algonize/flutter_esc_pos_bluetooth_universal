import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/models/print_ticket.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/print_session.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/raster/column_image.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/transport/printer_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A link that takes 100 bytes a write and notes when each piece left. With
/// [refuseFirstTry] it refuses the first piece once, as a busy radio does, so
/// the same range is offered to the gate twice.
class _FakeTransport implements PrinterTransport {
  _FakeTransport({required this.now, this.refuseFirstTry = false});

  static const chunk = 100;

  final int Function() now;
  final bool refuseFirstTry;

  /// When each accepted piece left, in milliseconds.
  final times = <int>[];
  final received = <int>[];

  @override
  BluetoothPrinter get printer => const BluetoothPrinter(id: 'printer', type: BluetoothPrinterType.ble);

  @override
  bool get isConnected => true;

  @override
  Future<void> connect(Duration timeout) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> write(List<int> data, {WriteGate? gate}) async {
    var offset = 0;
    var refused = false;
    while (offset < data.length) {
      final end = min(offset + chunk, data.length);
      if (gate != null) await gate(data, offset, end);
      if (refuseFirstTry && !refused) {
        refused = true;
        continue;
      }
      times.add(now());
      received.addAll(data.sublist(offset, end));
      offset = end;
    }
  }
}

/// Bits set in [bytes].
int _dots(List<int> bytes) {
  var n = 0;
  for (final b in bytes) {
    for (var v = b; v != 0; v >>= 1) {
      n += v & 1;
    }
  }
  return n;
}

/// 10 mm/s on a 100-dot head: 1000 bytes of text a second. Dense bands at
/// 5 mm/s cost twice as much. No burst unless given.
WritePacing _pacing({int burst = 0, double dark = 5}) =>
    WritePacing(mmPerSecond: 10, darkMmPerSecond: dark, burstBytes: burst);

void main() {
  group('TicketCost', () {
    const perDot = 9 / 8; // default pacing: a dense byte costs 10, a dot 9/8 extra
    final bytes = Uint8List.fromList([
      0x1b, 0x33, 0x00, // plain: 3 bytes, 8 dots
      ...List.filled(10, 0x00), // a text band, trimmed: 10 bytes for 100
      ...List.filled(10, 0xff), // a dense band: 10 bytes for 100
      0x0a, // plain: 1 byte, 2 dots
    ]);
    PrintTicket ticket() => PrintTicket(
      bytes,
      bands: const [
        BandSpan(start: 3, end: 13, fullBytes: 100),
        BandSpan(start: 13, end: 23, fullBytes: 100),
      ],
    );

    test('a band is due once all of it has been sent, not while it goes', () {
      final cost = TicketCost(ticket(), const WritePacing());
      expect(cost.dueBefore(0), 0, reason: 'nothing sent yet');
      expect(cost.dueBefore(5), closeTo(3 + 8 * perDot, 1e-9), reason: 'the plain bytes before the text band');
      expect(cost.dueBefore(8), 0, reason: 'the text band is still going out');
      expect(cost.dueBefore(13), 100, reason: 'the text band has gone: its full width');
      expect(cost.dueBefore(18), 0, reason: 'the dense band is still going out');
      expect(cost.dueBefore(23), 1000, reason: 'the dense band has gone: ten times its width');
      expect(cost.rest(), closeTo(1 + 2 * perDot, 1e-9), reason: 'the end of the ticket');
      expect(cost.rest(), 0);
    });

    test('charges every byte once, however often the link offers a piece again', () {
      final cost = TicketCost(ticket(), const WritePacing());
      expect(cost.dueBefore(13), closeTo(3 + 8 * perDot + 100, 1e-9));
      expect(cost.dueBefore(13), 0, reason: 'the same piece, refused and offered again');
      expect(cost.dueBefore(15), 0);
      expect(cost.dueBefore(23), 1000);
    });

    test('a widget ticket is charged its text at the text rate and its barcode at the dark rate', () {
      // 48 rows of light text, then a 48-row solid block, on a 58 mm head.
      final rgba = Uint8List(384 * 96 * 4)..fillRange(0, 384 * 96 * 4, 255);
      for (var y = 0; y < 96; y++) {
        final solid = y >= 48;
        if (!solid && y % 24 >= 18) continue;
        for (var x = 20; x < 364; x += solid ? 1 : 4) {
          final o = (y * 384 + x) * 4;
          rgba[o] = rgba[o + 1] = rgba[o + 2] = 0;
        }
      }
      final image = columnImageBands(rgba, 384, 96, headWidth: 384);
      // Two text bands, two solid bands, the blank band after the picture.
      expect(image.bands, hasLength(5));
      const band = 5 + 384 * 3 + 1;
      const perDot = 9 / 8;
      final expected =
          3 * band + // the text bands and the blank band, at the text rate
          2 * band * 10 + // the solid block, at the dark rate
          (3 + _dots(const [0x1b, 0x33, 0]) * perDot) + // ESC 3 0
          (2 + _dots(const [0x1b, 0x32]) * perDot); // ESC 2
      final cost = TicketCost(PrintTicket(image.bytes, bands: image.bands), const WritePacing());
      expect(cost.dueBefore(image.bytes.length) + cost.rest(), closeTo(expected, 1e-6));
    });
  });

  group('PrintSession', () {
    test('without pacing the ticket goes out at once', () {
      fakeAsync((async) {
        final link = _FakeTransport(now: () => async.elapsed.inMilliseconds);
        final session = PrintSession(transport: link, pacing: null, widthDots: 384);
        PrintOutcome? outcome;
        session.send(PrintTicket(Uint8List(1000))).then((o) => outcome = o);
        async.flushMicrotasks();
        expect(link.times, everyElement(0));
        expect(link.received, hasLength(1000));
        expect(outcome!.paced, isFalse);
      });
    });

    test('lets the burst through, then feeds at the print speed', () {
      fakeAsync((async) {
        final link = _FakeTransport(now: () => async.elapsed.inMilliseconds);
        final session = PrintSession(
          transport: link,
          pacing: _pacing(burst: 100, dark: 10),
          widthDots: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        PrintOutcome? outcome;
        session.send(PrintTicket(Uint8List(400))).then((o) => outcome = o);
        async.elapse(const Duration(seconds: 1));
        // Each piece is paid for once it has gone: the second rides the
        // burst, the third and fourth wait for the one before to print.
        expect(link.times, [0, 0, 100, 200]);
        expect(link.received, hasLength(400));
        expect(outcome!.bytes, 400);
        expect(outcome!.paced, isTrue);
      });
    });

    test('text after a dense graphic waits until the printer has printed it', () {
      fakeAsync((async) {
        final link = _FakeTransport(now: () => async.elapsed.inMilliseconds);
        final session = PrintSession(
          transport: link,
          pacing: _pacing(),
          widthDots: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        // A dense band (a logo or a barcode), then two text bands.
        final bytes = Uint8List.fromList([
          ...List.filled(100, 0xff),
          ...List.filled(100, 0x00),
          ...List.filled(100, 0x00),
        ]);
        session.send(
          PrintTicket(
            bytes,
            bands: const [
              BandSpan(start: 0, end: 100, fullBytes: 100),
              BandSpan(start: 100, end: 200, fullBytes: 100),
              BandSpan(start: 200, end: 300, fullBytes: 100),
            ],
          ),
        );
        async.elapse(const Duration(seconds: 1));
        // The graphic goes at once, so the printer is not kept waiting for
        // it; the text after it is held for the graphic's 200 ms of printing,
        // so it cannot pile up while the printer is busy with the graphic.
        expect(link.times, [0, 200, 300]);
      });
    });

    test('a dense graphic is not held back by its own print time', () {
      fakeAsync((async) {
        final link = _FakeTransport(now: () => async.elapsed.inMilliseconds);
        final session = PrintSession(
          transport: link,
          pacing: _pacing(),
          widthDots: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        // A text band, then a dense band.
        final bytes = Uint8List.fromList([...List.filled(100, 0x00), ...List.filled(100, 0xff)]);
        session.send(
          PrintTicket(
            bytes,
            bands: const [
              BandSpan(start: 0, end: 100, fullBytes: 100),
              BandSpan(start: 100, end: 200, fullBytes: 100),
            ],
          ),
        );
        async.elapse(const Duration(seconds: 1));
        // The dense band leaves once the text before it has printed.
        expect(link.times, [0, 100]);
      });
    });

    test('a piece the radio refused is not charged twice', () {
      fakeAsync((async) {
        final link = _FakeTransport(now: () => async.elapsed.inMilliseconds, refuseFirstTry: true);
        final session = PrintSession(
          transport: link,
          pacing: _pacing(burst: 100, dark: 10),
          widthDots: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        session.send(PrintTicket(Uint8List(400)));
        async.elapse(const Duration(seconds: 1));
        expect(link.times, [0, 0, 100, 200], reason: 'no extra wait for the refused try');
        expect(link.received, hasLength(400));
      });
    });

    test('the next ticket on the link waits for the end of the last one to print', () {
      fakeAsync((async) {
        final link = _FakeTransport(now: () => async.elapsed.inMilliseconds);
        final session = PrintSession(
          transport: link,
          pacing: _pacing(),
          widthDots: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        // The first ticket ends with a dense band: 200 ms to print.
        session.send(
          PrintTicket(
            Uint8List.fromList(List.filled(100, 0xff)),
            bands: const [BandSpan(start: 0, end: 100, fullBytes: 100)],
          ),
        );
        async.flushMicrotasks();
        session.send(PrintTicket(Uint8List(100)));
        async.elapse(const Duration(seconds: 1));
        expect(link.times, [0, 200]);
      });
    });
  });
}

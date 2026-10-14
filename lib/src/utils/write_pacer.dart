import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import '../models/write_pacing.dart';

/// Holds print data back so it leaves no faster than a [WritePacing] allows.
///
/// A token bucket: it starts full ([WritePacing.burstBytes]) and refills at
/// the printer's print speed in bytes. Each write is charged its bytes plus an
/// extra for the dots it prints, so dense graphics are fed slower than text
/// (see [WritePacing.darkMmPerSecond]). There is one per link, so tickets
/// printed back to back on the same connection share the allowance, as they
/// share the printer's buffer.
class WritePacer {
  WritePacer({
    required int bytesPerSecond,
    required int burstBytes,
    double costPerDot = 0,
    int Function()? nowMicros,
  }) : assert(bytesPerSecond > 0),
       assert(burstBytes >= 0),
       assert(costPerDot >= 0),
       _bytesPerSecond = bytesPerSecond,
       _burstBytes = burstBytes,
       _costPerDot = costPerDot,
       _nowMicros = nowMicros ?? _stopwatchMicros(),
       _tokens = burstBytes.toDouble();

  /// A pacer for [pacing] on a print head [widthDots] dots wide, or null when
  /// pacing is off.
  static WritePacer? of(WritePacing? pacing, {required int widthDots}) {
    if (pacing == null) return null;
    return WritePacer(
      bytesPerSecond: pacing.bytesPerSecond(widthDots),
      burstBytes: pacing.burstBytes,
      costPerDot: pacing.costPerDot,
    );
  }

  static int Function() _stopwatchMicros() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds;
  }

  final int _bytesPerSecond;
  final int _burstBytes;
  final double _costPerDot;
  final int Function() _nowMicros;
  double _tokens;
  int _lastMicros = 0;

  /// Completes once `data[start..end)` may be sent: its bytes, plus the extra
  /// charge for the dots it prints.
  Future<void> waitFor(List<int> data, int start, int end) =>
      wait(end - start, dots: _costPerDot == 0 ? 0 : dotsIn(data, start, end));

  /// Completes once [bytes] more may be sent, carrying [dots] printed dots.
  ///
  /// The cost is booked at once, so calls complete in order even when they
  /// are not awaited one after the other. The balance goes negative for a
  /// write larger than the burst; the debt is paid off by the next refills.
  Future<void> wait(int bytes, {int dots = 0}) {
    if (bytes <= 0) return Future.value();
    final cost = bytes + dots * _costPerDot;
    _refill();
    final deficit = cost - _tokens;
    _tokens -= cost;
    if (deficit <= 0) return Future.value();
    final micros = (deficit * Duration.microsecondsPerSecond / _bytesPerSecond).ceil();
    return Future<void>.delayed(Duration(microseconds: micros));
  }

  /// The number of 1 bits in `data[start..end)`: the dots those raster bytes
  /// print. Text and control bytes count too, but they are a sliver of a
  /// ticket next to its image.
  static int dotsIn(List<int> data, int start, int end) {
    var dots = 0;
    for (var i = start; i < end; i++) {
      dots += _bitCount[data[i] & 0xff];
    }
    return dots;
  }

  static final Uint8List _bitCount = Uint8List.fromList([for (var b = 0; b < 256; b++) _popCount(b)]);

  static int _popCount(int b) {
    var n = 0;
    for (var v = b; v != 0; v >>= 1) {
      n += v & 1;
    }
    return n;
  }

  void _refill() {
    final now = _nowMicros();
    final earned = (now - _lastMicros) * _bytesPerSecond / Duration.microsecondsPerSecond;
    _tokens = math.min(_burstBytes.toDouble(), _tokens + earned);
    _lastMicros = now;
  }
}

import 'dart:async';
import 'dart:math' as math;

import '../models/write_pacing.dart';

/// Holds print data back so it leaves no faster than a [WritePacing] allows.
///
/// A token bucket: it starts full ([burstBytes]) and refills at the printer's
/// print speed in bytes per second. Each write is charged a cost in bytes (a
/// dense byte costs more than a text byte, see `PrintSession`) and waits until
/// the bucket can pay for it. There is one per connection, so tickets printed
/// back to back on the same link share the allowance, as they share the
/// printer's buffer.
class WritePacer {
  WritePacer({required int bytesPerSecond, required int burstBytes, int Function()? nowMicros})
    : assert(bytesPerSecond > 0),
      assert(burstBytes >= 0),
      _bytesPerSecond = bytesPerSecond,
      _burstBytes = burstBytes,
      _nowMicros = nowMicros ?? _stopwatchMicros(),
      _tokens = burstBytes.toDouble();

  /// A pacer for [pacing] on a print head [widthDots] dots wide, or null when
  /// pacing is off.
  static WritePacer? of(WritePacing? pacing, {required int widthDots, int Function()? nowMicros}) {
    if (pacing == null) return null;
    return WritePacer(
      bytesPerSecond: pacing.bytesPerSecond(widthDots),
      burstBytes: pacing.burstBytes,
      nowMicros: nowMicros,
    );
  }

  static int Function() _stopwatchMicros() {
    final clock = Stopwatch()..start();
    return () => clock.elapsedMicroseconds;
  }

  final int _bytesPerSecond;
  final int _burstBytes;
  final int Function() _nowMicros;
  double _tokens;
  int _lastMicros = 0;

  /// Completes once [cost] bytes' worth more may be sent, and any debt
  /// [book]ed earlier has been paid off: `wait(0)` waits for the debt alone.
  ///
  /// The cost is booked at once, so calls complete in order even when they
  /// are not awaited one after the other. The balance goes negative for a
  /// write larger than the burst; the debt is paid off by the next refills.
  Future<void> wait(num cost) {
    _refill();
    final deficit = cost - _tokens;
    if (cost > 0) _tokens -= cost;
    if (deficit <= 0) return Future.value();
    final micros = (deficit * Duration.microsecondsPerSecond / _bytesPerSecond).ceil();
    return Future<void>.delayed(Duration(microseconds: micros));
  }

  /// Books [cost] without waiting: a debt the next [wait] pays off. For data
  /// already sent whose printing has not been paid for yet.
  void book(num cost) {
    if (cost <= 0) return;
    _refill();
    _tokens -= cost;
  }

  void _refill() {
    final now = _nowMicros();
    final earned = (now - _lastMicros) * _bytesPerSecond / Duration.microsecondsPerSecond;
    _tokens = math.min(_burstBytes.toDouble(), _tokens + earned);
    _lastMicros = now;
  }
}

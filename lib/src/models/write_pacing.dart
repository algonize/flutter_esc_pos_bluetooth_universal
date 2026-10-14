import 'package:flutter/foundation.dart';

/// How fast print data is fed to the printer, so its input buffer never
/// overflows.
///
/// A thermal printer prints at a fixed speed and keeps only a small buffer of
/// data it has not printed yet (a few to a few dozen kilobytes). The link is
/// usually faster than the print head: Bluetooth delivers some 20 to 40 kB/s,
/// while a 58 mm printer at 60 mm/s prints about 23 kB/s of raster data. A
/// short ticket fits in the buffer, but on a long one the surplus fills it and
/// the printer drops bytes. Nothing stops that: a BLE write without response
/// is never refused, and most printers take Classic or TCP data before
/// checking for room. A byte lost inside an image command puts the printer out
/// of step with it, and the rest of the image comes out as text garbage. That
/// is the "bottom of a long receipt is gibberish" symptom.
///
/// Pacing sends data no faster than the printer prints it, after an initial
/// [burstBytes] the buffer can hold. It is set as a print speed
/// ([mmPerSecond]) because raster data is one bit per dot: at 8 dots per
/// millimetre the printer consumes exactly the paper width in dots per
/// millimetre of paper, so the byte rate follows from the paper size.
///
/// The defaults (40 mm/s on text, 5 mm/s on solid black, 2 kB burst) are
/// under the speed of nearly every receipt printer, slow 58 mm portable ones
/// included. A Deli ES421 (rated 60 mm/s) still dropped whole bands of a QR
/// code and a barcode at 10 mm/s dark, cleanly and without garbage: its
/// parser throws a band away when the print queue is full, so the only cure
/// is to send dense graphics no faster than it prints them. Raise the speeds
/// for a faster printer you have tested, or turn pacing off with
/// `pacing: null` in [BluetoothWriteOptions].
@immutable
class WritePacing {
  const WritePacing({this.mmPerSecond = 40, this.darkMmPerSecond = 5, this.burstBytes = 2048})
    : assert(mmPerSecond > 0),
      assert(darkMmPerSecond > 0 && darkMmPerSecond <= mmPerSecond),
      assert(burstBytes >= 0);

  /// The print speed on light content such as text, in millimetres of paper
  /// per second: the motor-limited speed, close to the printer's rating.
  final double mmPerSecond;

  /// The print speed on solid black, in millimetres per second.
  ///
  /// A thermal head cannot fire a whole dense row at once: it splits it into
  /// several strobe groups, each heated in turn, and pauses to let the head
  /// cool, so a row of a QR code or a barcode takes many times longer than a
  /// row of text. Cheap printers drop to a tenth of their rated speed or less
  /// on solid black. Data is charged by its dots so that the sender slows
  /// down through dense graphics and speeds back up on text, instead of
  /// flooding the buffer exactly where the printer is at its slowest.
  final double darkMmPerSecond;

  /// Bytes that may go out at once before pacing starts: what the printer's
  /// buffer takes while it starts printing. Keep it well under the smallest
  /// buffer you expect (4 kB on many printers): whatever the burst leaves in
  /// the buffer stays there until the printer gets ahead of the sender, and
  /// is room the next dense band does not have.
  final int burstBytes;

  /// Bytes per second for a print head [widthDots] dots wide.
  ///
  /// A row of raster data takes `widthDots / 8` bytes and a millimetre of
  /// paper is 8 rows, so a millimetre is exactly [widthDots] bytes.
  int bytesPerSecond(int widthDots) => (widthDots * mmPerSecond).round().clamp(1, 1 << 30);

  /// The extra bytes a printed dot is charged on top of the byte it is in.
  ///
  /// A solid black byte (8 dots) takes `mmPerSecond / darkMmPerSecond` times
  /// as long to print as a blank one, so it is charged that many bytes.
  double get costPerDot => (mmPerSecond / darkMmPerSecond - 1) / 8;

  @override
  String toString() => 'WritePacing($mmPerSecond mm/s, $darkMmPerSecond mm/s dark, burst $burstBytes B)';
}

import 'package:flutter/foundation.dart';

/// How fast print data is fed to the printer, so its input buffer never
/// overflows on a long receipt.
///
/// A thermal printer prints at a fixed speed and keeps only a small buffer of
/// data it has not printed yet (a few to a few dozen kilobytes). Bluetooth
/// delivers faster than the print head consumes: a 58 mm printer at 60 mm/s
/// prints about 23 kB/s of raster, while the link carries two to ten times
/// that. Nothing holds the link back: a BLE write without response is never
/// refused, and most printers take Classic or TCP data before checking for
/// room. A short ticket fits in the buffer, but on a long one the surplus
/// fills it and the printer drops bytes. A byte lost inside an image command
/// puts the printer out of step with it, and the rest of the image prints as
/// text garbage. That is the "bottom of a long receipt is gibberish" symptom.
///
/// So data is fed at [mmPerSecond] (text) after an initial [burstBytes] the
/// buffer can hold, and an image band with [denseThreshold] or more of its
/// dots printed (a barcode, a QR code, a logo) is fed at [darkMmPerSecond], as
/// if it were solid black. A thermal head cannot fire a whole dense row at
/// once: it splits it into strobe groups heated in turn and pauses to let the
/// head cool, so a dense row prints several times slower than a row of text,
/// and that is exactly where a single fixed rate still overran the buffer.
///
/// Both directions matter. Fed faster than it prints, the buffer fills and a
/// long receipt breaks. Fed slower, the printer empties its buffer after every
/// band and stops until the next one arrives, and each restart leaves a thin
/// white seam through the text, most visible through bold lines. So
/// [mmPerSecond] should sit just above the printer's bit-image speed on text,
/// with [burstBytes] covering a few bands so short link pauses never reach the
/// head, and [darkMmPerSecond] is a ceiling the dense bands must not exceed.
///
/// Speeds are millimetres of paper per second because raster data is one bit
/// per dot: at 8 dots per millimetre the printer consumes the paper width in
/// dots per millimetre of paper, so the byte rate follows from the paper size.
///
/// The defaults (50 mm/s text, 5 mm/s solid black, 4 kB burst) printed a full
/// receipt with text, a logo, a QR code and a barcode cleanly on a Deli ES421
/// 58 mm printer. Raise [mmPerSecond] for a faster printer you have tested,
/// lower it if text prints as random characters on a long receipt, lower
/// [darkMmPerSecond] if only the graphics break, or turn pacing off with
/// `pacing: null` in [BluetoothWriteOptions] on a fast printer.
@immutable
class WritePacing {
  const WritePacing({
    this.mmPerSecond = 50,
    this.darkMmPerSecond = 5,
    this.burstBytes = 4096,
    this.denseThreshold = 0.25,
  }) : assert(mmPerSecond > 0),
       assert(denseThreshold > 0 && denseThreshold <= 1),
       assert(darkMmPerSecond > 0 && darkMmPerSecond <= mmPerSecond),
       assert(burstBytes >= 0);

  /// The print speed on light content such as text, in millimetres of paper
  /// per second: the motor-limited speed in bit-image mode, kept under the
  /// printer's rating with room to spare, as a guess that is too high
  /// overflows the buffer on a long ticket.
  final double mmPerSecond;

  /// The print speed on dense graphics (a barcode, a QR code, a logo), in
  /// millimetres per second. An image band with [denseThreshold] or more of
  /// its dots printed is fed at this speed throughout, so the sender slows
  /// through dense graphics and speeds back up on text, instead of flooding
  /// the buffer exactly where the printer is at its slowest.
  final double darkMmPerSecond;

  /// The share of printed dots from which a whole image band is fed at
  /// [darkMmPerSecond], as if it were solid black. A lighter band is text and
  /// is fed at [mmPerSecond] by its bytes alone, whatever its dots: receipt
  /// text measures 4 to 15% dark per band, bold headings included, and the
  /// head prints a row of text at full speed whatever its weight. Charged by
  /// its dots, bold text was fed at a third of the speed it printed, the
  /// printer emptied its buffer after every band, and each restart left a
  /// one-row white seam through the text.
  final double denseThreshold;

  /// Bytes that may go out at once before pacing starts: what the printer's
  /// buffer takes while it begins printing, a few image bands. Keep it under
  /// the smallest buffer you expect: whatever the burst leaves in the buffer
  /// stays there until the printer gets ahead of the sender, and is room the
  /// next dense band does not have.
  final int burstBytes;

  /// How many times longer a dense (solid black) byte takes to print than a
  /// text byte: [mmPerSecond] / [darkMmPerSecond]. A dense band's bytes are
  /// charged this many each, so the dense band feeds at [darkMmPerSecond].
  double get darkRatio => mmPerSecond / darkMmPerSecond;

  /// Bytes per second for a print head [widthDots] dots wide at [mmPerSecond].
  ///
  /// A row of raster data takes `widthDots / 8` bytes and a millimetre of
  /// paper is 8 rows, so a millimetre is exactly [widthDots] bytes.
  int bytesPerSecond(int widthDots) =>
      (widthDots * mmPerSecond).round().clamp(1, 1 << 30);

  @override
  String toString() =>
      'WritePacing($mmPerSecond mm/s text, $darkMmPerSecond mm/s dark, '
      'dense from ${(denseThreshold * 100).round()}%, burst $burstBytes B)';
}

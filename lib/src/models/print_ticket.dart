import 'package:flutter/foundation.dart';

/// One bit-image band inside a ticket's bytes: an `ESC *` column band with
/// its line feed.
///
/// The sender paces a band by the paper it covers rather than the bytes it
/// takes, so a band trimmed of blank columns is still charged as a full band.
@immutable
class BandSpan {
  const BandSpan({required this.start, required this.end, required this.fullBytes})
    : assert(start >= 0 && end > start && fullBytes > 0);

  /// Offset of the band's first byte.
  final int start;

  /// Offset just past the band.
  final int end;

  /// The bytes the band would take untrimmed, across the whole print head.
  final int fullBytes;

  int get length => end - start;

  BandSpan shift(int by) => BandSpan(start: start + by, end: end + by, fullBytes: fullBytes);

  @override
  bool operator ==(Object other) =>
      other is BandSpan && other.start == start && other.end == end && other.fullBytes == fullBytes;

  @override
  int get hashCode => Object.hash(start, end, fullBytes);

  @override
  String toString() => 'BandSpan($start..$end, full $fullBytes)';
}

/// ESC/POS bytes ready to send, with the bit-image bands inside them.
@immutable
class PrintTicket {
  PrintTicket(this.bytes, {this.bands = const []})
    : assert(() {
        var last = 0;
        for (final b in bands) {
          if (b.start < last || b.end > bytes.length) return false;
          last = b.end;
        }
        return true;
      }(), 'bands must be in order, non-overlapping and inside the bytes');

  final Uint8List bytes;

  /// The bands in [bytes], in order and non-overlapping. Empty for a raw
  /// ticket, whose bytes are then paced by the dots they print.
  final List<BandSpan> bands;

  int get length => bytes.length;
  bool get isEmpty => bytes.isEmpty;
}

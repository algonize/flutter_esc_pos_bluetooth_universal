import 'dart:typed_data';

/// Dots per ESC * band at double density ("ESC * 33").
const int _bandHeight = 24;

/// The ESC * bands that flutter_esc_pos_utils' `Generator.image` prints for
/// an 8-bit RGBA picture, byte for byte, without the alignment it sets first.
///
/// `Generator.image` gets there through a dozen whole-image passes of the
/// image package (copy, invert, flip, rotate, resize, composite, a crop and
/// a grayscale per band), which takes seconds in a browser, where it runs on
/// the UI thread. Those passes amount to reading each pixel once, so this
/// does just that.
///
/// Each band covers 24 rows. It holds 3 bytes per pixel column, the topmost
/// dot in the high bit, and a dot is printed where the pixel is darker than
/// mid grey. One blank band always follows the picture, as with
/// `Generator.image`.
List<int> columnImageBands(Uint8List rgba, int width, int height) {
  assert(rgba.length >= width * height * 4);
  final dots = _darkDots(rgba, width * height);

  // Rounded up to whole bands, plus the extra band Generator.image adds when
  // the height is already a whole number of bands.
  final bands = height ~/ _bandHeight + 1;
  final bandLength = 5 + width * 3 + 1;
  final out = Uint8List(3 + bands * bandLength + 2);
  var i = 0;

  // ESC 3 0: no extra line spacing, so the bands touch.
  out[i++] = 0x1b;
  out[i++] = 0x33;
  out[i++] = 0;
  for (var band = 0; band < bands; band++) {
    // ESC * 33 nL nH: 24-dot double density, width columns.
    out[i++] = 0x1b;
    out[i++] = 0x2a;
    out[i++] = 33;
    out[i++] = width & 0xff;
    out[i++] = width >> 8;
    final top = band * _bandHeight;
    for (var x = 0; x < width; x++) {
      for (var byte = 0; byte < 3; byte++) {
        var value = 0;
        for (var bit = 0; bit < 8; bit++) {
          final y = top + byte * 8 + bit;
          value <<= 1;
          if (y < height && dots[y * width + x] == 1) value |= 1;
        }
        out[i++] = value;
      }
    }
    out[i++] = 0x0a;
  }
  // ESC 2: default line spacing.
  out[i++] = 0x1b;
  out[i++] = 0x32;
  return out;
}

/// Whether each grey level prints, after the image package takes the
/// luminance of the grey once more to keep a single channel. Floating point
/// rounds a few levels down there (128 becomes 127), right at the threshold.
final Uint8List _printsGrey = Uint8List.fromList([
  for (var grey = 0; grey < 256; grey++)
    (0.299 * grey + 0.587 * grey + 0.114 * grey).toInt() > 127 ? 1 : 0,
]);

/// 1 for every pixel printed as a dot, in row order.
///
/// Matches the image package: the colour is inverted, flattened onto black
/// (its alpha blend), turned grey with 0.299 R + 0.587 G + 0.114 B truncated
/// to an integer, then reduced to one channel (see [_printsGrey]).
Uint8List _darkDots(Uint8List rgba, int pixels) {
  final dots = Uint8List(pixels);
  for (var p = 0, o = 0; p < pixels; p++, o += 4) {
    var r = 255 - rgba[o];
    var g = 255 - rgba[o + 1];
    var b = 255 - rgba[o + 2];
    final a = rgba[o + 3];
    if (a != 255) {
      r = r * a ~/ 255;
      g = g * a ~/ 255;
      b = b * a ~/ 255;
    }
    dots[p] = _printsGrey[(0.299 * r + 0.587 * g + 0.114 * b).toInt()];
  }
  return dots;
}

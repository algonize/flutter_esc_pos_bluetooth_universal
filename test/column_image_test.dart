import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/models/print_ticket.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/raster/column_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'helpers/escpos_decode.dart';

/// What Generator.image prints, as the reference: centred, full-width bands.
List<int> _reference(Uint8List rgba, int width, int height, CapabilityProfile profile) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return Generator(PaperSize.mm58, profile).image(image);
}

/// The package's bands, left-aligned and padded like the ticket builder does.
/// Scrubbing is off: Generator.image prints every dot, real-time sequences
/// included, and random pixels are full of them.
List<int> _fast(
  Uint8List rgba,
  int width,
  int height,
  CapabilityProfile profile, {
  required int head,
}) => [
  0x1b, 0x61, 0x30, // ESC a 0: left
  ...columnImageBands(
    rgba,
    width,
    height,
    leftPad: (head - width) ~/ 2,
    headWidth: head,
    scrubRealTime: false,
  ).bytes,
];

Uint8List _randomRgba(Random random, int width, int height, {bool opaque = true}) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < rgba.length; i += 4) {
    // Mostly black and white with grey edges, like rendered text, plus noise
    // around the 127/128 threshold.
    final kind = random.nextInt(4);
    final v = switch (kind) {
      0 => 0,
      1 => 255,
      2 => 120 + random.nextInt(16),
      _ => random.nextInt(256),
    };
    rgba[i] = (v + random.nextInt(9) - 4).clamp(0, 255);
    rgba[i + 1] = v;
    rgba[i + 2] = (v + random.nextInt(9) - 4).clamp(0, 255);
    rgba[i + 3] = opaque ? 255 : random.nextInt(256);
  }
  return rgba;
}

/// White pixels, with the given (x, y) dots black.
Uint8List _picture(int width, int height, Iterable<(int, int)> black) {
  final rgba = Uint8List(width * height * 4)..fillRange(0, width * height * 4, 255);
  for (final (x, y) in black) {
    final o = (y * width + x) * 4;
    rgba[o] = rgba[o + 1] = rgba[o + 2] = 0;
  }
  return rgba;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('column bands', () {
    test('print exactly the dots Generator.image prints', () async {
      final profile = await CapabilityProfile.load();
      final random = Random(42);
      for (final (width, height) in [
        (1, 1),
        (8, 24),
        (37, 23),
        (384, 48),
        (384, 391),
        (200, 100),
      ]) {
        final rgba = _randomRgba(random, width, height);
        final ours = decodePaper(_fast(rgba, width, height, profile, head: 384), headWidth: 384);
        final theirs = decodePaper(_reference(rgba, width, height, profile), headWidth: 384);
        expect(ours.sameAs(theirs), isTrue, reason: '${width}x$height: ${ours.diff(theirs)}');
        expect(ours.height, (height ~/ 24 + 1) * 24);
      }
    });

    test('match it for translucent pixels too', () async {
      final profile = await CapabilityProfile.load();
      final rgba = _randomRgba(Random(7), 96, 50, opaque: false);
      final ours = decodePaper(_fast(rgba, 96, 50, profile, head: 384), headWidth: 384);
      final theirs = decodePaper(_reference(rgba, 96, 50, profile), headWidth: 384);
      expect(ours.sameAs(theirs), isTrue, reason: ours.diff(theirs));
    });

    test('butt together: zero line spacing set before the bands, reset after', () {
      final image = columnImageBands(_picture(384, 48, const [(5, 5)]), 384, 48);
      expect(image.bytes.sublist(0, 3), [0x1b, 0x33, 0]);
      expect(image.bytes.sublist(image.bytes.length - 2), [0x1b, 0x32]);
      for (final s in image.bands) {
        expect(image.bytes.sublist(s.start, s.start + 3), [0x1b, 0x2a, 33]);
        expect(image.bytes[s.end - 1], 0x0a, reason: 'each band ends with its line feed');
      }
    });

    test('trim each band at its last printed column and keep one column for a blank band', () {
      // 384 wide, 72 tall: three bands. Band 0 has a dot at column 100, band 1
      // is blank, band 2 has dots at 10 and 383.
      final rgba = _picture(384, 72, [(100, 5), (10, 50), (383, 60)]);
      final image = columnImageBands(rgba, 384, 72);
      expect(image.bands, hasLength(4)); // plus the blank band after the picture
      int columns(BandSpan b) => image.bytes[b.start + 3] | (image.bytes[b.start + 4] << 8);
      expect(columns(image.bands[0]), 101);
      expect(columns(image.bands[1]), 1);
      expect(columns(image.bands[2]), 384);
      expect(columns(image.bands[3]), 1);
      expect(image.bands[1].length, 5 + 3 + 1);
      expect(image.bands[1].fullBytes, 5 + 384 * 3 + 1);
      // Untrimmed it would have been four full bands.
      expect(image.bytes.length, lessThan(2 * (5 + 384 * 3 + 1)));
      // And the paper still reads the same.
      final paper = decodePaper(image.bytes, headWidth: 384);
      expect(paper.height, 96);
      expect(paper.rows[5][100], 1);
      expect(paper.rows[50][10], 1);
      expect(paper.rows[60][383], 1);
      expect([for (var y = 24; y < 48; y++) paper.dotsIn(y)].every((d) => d == 0), isTrue);
    });

    test('pad a narrow picture to where centring would put it', () {
      final rgba = _picture(100, 24, [(0, 0), (99, 23)]);
      final image = columnImageBands(rgba, 100, 24, leftPad: (384 - 100) ~/ 2, headWidth: 384);
      final paper = decodePaper([0x1b, 0x61, 0, ...image.bytes], headWidth: 384);
      expect(paper.rows[0][142], 1);
      expect(paper.rows[23][241], 1);
      expect(paper.dotsIn(0), 1);
      expect(image.bands.first.fullBytes, 5 + 384 * 3 + 1);
    });

    test('never carry a real-time command sequence in the image data', () {
      // A column whose bytes read 0x10 0x04 (DLE EOT): dots at rows 3 and 13.
      // The 0x10 dot is dropped; the 0x04 dot stays.
      final rgba = _picture(8, 24, [(2, 3), (2, 13), (5, 3), (5, 21)]);
      final image = columnImageBands(rgba, 8, 24);
      final data = image.bytes.sublist(image.bands.first.start + 5, image.bands.first.end - 1);
      for (var i = 0; i + 1 < data.length; i++) {
        expect(
          data[i] == 0x10 && (data[i + 1] == 0x04 || data[i + 1] == 0x05 || data[i + 1] == 0x14),
          isFalse,
        );
      }
      final paper = decodePaper(image.bytes, headWidth: 8);
      expect(paper.rows[3][2], 0, reason: 'the DLE dot is dropped');
      expect(paper.rows[13][2], 1);
      expect(paper.rows[3][5], 1, reason: 'a column reading 0x10 0x00 0x04 is left alone');
      expect(paper.rows[21][5], 1);
      // Scrubbing can be turned off.
      final raw = columnImageBands(rgba, 8, 24, scrubRealTime: false);
      expect(decodePaper(raw.bytes, headWidth: 8).rows[3][2], 1);
    });
  });
}

import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/raster/column_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// What Generator.image prints, as the reference.
List<int> _reference(Uint8List rgba, int width, int height, CapabilityProfile profile) {
  final image = img.Image.fromBytes(
    width: width,
    height: height,
    bytes: rgba.buffer,
    numChannels: 4,
  );
  return Generator(PaperSize.mm58, profile).image(image);
}

List<int> _fast(Uint8List rgba, int width, int height, CapabilityProfile profile) => [
  ...Generator(PaperSize.mm58, profile).setStyles(const PosStyles(align: PosAlign.center)),
  ...columnImageBands(rgba, width, height),
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('prints exactly what Generator.image prints', () async {
    final profile = await CapabilityProfile.load();
    final random = Random(42);
    for (final (width, height) in [(1, 1), (8, 24), (37, 23), (384, 48), (384, 391), (576, 100)]) {
      final rgba = _randomRgba(random, width, height);
      expect(
        _fast(rgba, width, height, profile),
        _reference(rgba, width, height, profile),
        reason: '${width}x$height',
      );
    }
  });

  test('matches it for translucent pixels too', () async {
    final profile = await CapabilityProfile.load();
    final rgba = _randomRgba(Random(7), 96, 50, opaque: false);
    expect(_fast(rgba, 96, 50, profile), _reference(rgba, 96, 50, profile));
  });
}

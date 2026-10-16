import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/raster/widget_raster.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';

import 'helpers/escpos_decode.dart';

/// A receipt with text, rules and a filled box, so the image has black, white
/// and anti-aliased grey edges.
const _receipt = Padding(
  padding: EdgeInsets.all(8),
  child: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('ALGORAMMING CAFE', style: TextStyle(color: Colors.black, fontSize: 30)),
      Divider(color: Colors.black),
      Row(
        children: [
          Expanded(
            child: Text('Latte', style: TextStyle(color: Colors.black, fontSize: 22)),
          ),
          Text('4.20', style: TextStyle(color: Colors.black, fontSize: 22)),
        ],
      ),
      SizedBox(height: 8),
      ColoredBox(color: Color(0xFF7F7F7F), child: SizedBox(width: 120, height: 30)),
    ],
  ),
);

/// The ticket as flutter_esc_pos_network_universal builds it: a PNG capture,
/// decoded and printed with Generator.image.
Future<List<int>> _networkPackageTicket(
  BuildContext context,
  Widget child,
  ThermalPosPrinterPageSize paperSize,
  CapabilityProfile profile,
) async {
  final png = await ScreenshotController().captureFromLongWidget(
    InheritedTheme.captureAll(context, Material(color: Colors.white, child: child)),
    delay: const Duration(milliseconds: 200),
    context: context,
    constraints: BoxConstraints(maxWidth: paperSize.widthPx),
  );
  var image = img.decodeImage(png)!;
  if (image.format != img.Format.uint8) image = image.convert(format: img.Format.uint8);
  final generator = Generator(paperSize.toPaperSize, profile);
  return [...generator.image(image), ...generator.feed(2), ...generator.cut()];
}

void main() {
  testWidgets('prints exactly the dots the network package prints, in fewer bytes', (tester) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    final profile = await CapabilityProfile.load();

    for (final paperSize in ThermalPosPrinterPageSize.values) {
      final (fast, reference) = (await tester.runAsync(
        () async => (
          // Scrubbing off: the reference prints every dot.
          await buildWidgetTicket(context, _receipt, paperSize: paperSize, profile: profile, scrubRealTime: false),
          await _networkPackageTicket(context, _receipt, paperSize, profile),
        ),
      ))!;
      final head = paperSize.widthPx.toInt();
      expect(fast.bytes.length, greaterThan(1000), reason: paperSize.title);
      expect(fast.bytes.length, lessThan(reference.length), reason: '${paperSize.title}: trimmed bands');
      final ours = decodePaper(fast.bytes, headWidth: head);
      final theirs = decodePaper(reference, headWidth: head);
      expect(ours.sameAs(theirs), isTrue, reason: '${paperSize.title}: ${ours.diff(theirs)}');
      // Every band is accounted for, in order, and charged as a full band.
      expect(fast.bands.length, ours.height ~/ 24);
      for (final b in fast.bands) {
        expect(b.fullBytes, 5 + head * 3 + 1);
        expect(fast.bytes[b.start], 0x1b);
        expect(fast.bytes[b.start + 1], 0x2a);
        expect(fast.bytes[b.end - 1], 0x0a);
      }
      // The ticket still ends with a feed and a cut.
      expect(fast.bytes[fast.bytes.length - 3], 0x1d);
      expect(fast.bytes[fast.bytes.length - 2], 0x56);
    }
  });
}

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';

import '../enums.dart';

/// Renders [child] off screen and turns it into an ESC/POS ticket: one raster
/// image, then a short feed and a cut. Same pipeline as
/// flutter_esc_pos_network_universal, so receipts look identical on both.
Future<List<int>> buildWidgetTicket(
  BuildContext context,
  Widget child, {
  required ThermalPosPrinterPageSize paperSize,
  required CapabilityProfile profile,
}) async {
  final Uint8List png = await ScreenshotController().captureFromLongWidget(
    InheritedTheme.captureAll(context, Material(color: Colors.white, child: child)),
    delay: const Duration(milliseconds: kIsWeb ? 500 : 200),
    context: context,
    // Without a width limit the widget is laid out at infinite width, and any
    // Row + Expanded (or other width-filling layout) fails to lay out. Cap it
    // at the print-head width so ordinary receipt layouts just work.
    constraints: BoxConstraints(maxWidth: paperSize.widthPx),
  );
  // Image work runs in a background isolate on native platforms (inline on web).
  return compute(encodeTicketImage, (png, paperSize, profile));
}

/// Encodes a PNG into ESC/POS raster bytes. Top level so it can run in an isolate.
@visibleForTesting
List<int> encodeTicketImage((Uint8List, ThermalPosPrinterPageSize, CapabilityProfile) args) {
  final (png, paperSize, profile) = args;
  final decoded = img.decodeImage(png);
  if (decoded == null) return const [];

  // Real iOS devices can capture 16 bits per channel (wide colour). The ESC/POS
  // encoder assumes 8, so a 16-bit image comes out double length and garbled.
  var image = decoded.format == img.Format.uint8
      ? decoded
      : decoded.convert(format: img.Format.uint8);

  // Keep within the print head; wider bitmaps desync the image command.
  final maxWidth = paperSize.widthPx.toInt();
  if (image.width > maxWidth) image = img.copyResize(image, width: maxWidth);

  final generator = Generator(paperSize.toPaperSize, profile);
  // One image for the whole receipt: images split into pieces leave white seams.
  return [...generator.image(image), ...generator.feed(2), ...generator.cut()];
}

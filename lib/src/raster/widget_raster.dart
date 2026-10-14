import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';

import '../enums.dart';
import 'column_image.dart';

/// Renders [child] off screen and turns it into an ESC/POS ticket: one image,
/// then a short feed and a cut. The bytes are the same as
/// flutter_esc_pos_network_universal prints, so receipts look identical on
/// both.
Future<List<int>> buildWidgetTicket(
  BuildContext context,
  Widget child, {
  required ThermalPosPrinterPageSize paperSize,
  required CapabilityProfile profile,
}) async {
  final image = await ScreenshotController().longWidgetToUiImage(
    InheritedTheme.captureAll(context, Material(color: Colors.white, child: child)),
    delay: const Duration(milliseconds: kIsWeb ? 500 : 200),
    context: context,
    // Without a width limit the widget is laid out at infinite width, and any
    // Row + Expanded (or other width-filling layout) fails to lay out. Cap it
    // at the print-head width so ordinary receipt layouts just work.
    constraints: BoxConstraints(maxWidth: paperSize.widthPx),
  );
  final width = image.width;
  final height = image.height;
  final ByteData? pixels;
  try {
    // Raw pixels rather than a PNG: encoding and decoding one again took most
    // of the time, above all in a browser. They are always 8 bits per channel,
    // even where the screen captures 16 (wide colour on real iOS devices).
    pixels = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  } finally {
    image.dispose();
  }
  if (pixels == null) return const [];
  return encodeTicketPixels(
    pixels.buffer.asUint8List(pixels.offsetInBytes, pixels.lengthInBytes),
    width,
    height,
    paperSize: paperSize,
    profile: profile,
  );
}

/// Encodes 8-bit RGBA pixels into an ESC/POS ticket: the image as ESC * bands
/// (what `Generator.image` prints), a feed and a cut. Fast enough to run on
/// the UI thread, even in a browser.
@visibleForTesting
List<int> encodeTicketPixels(
  Uint8List rgba,
  int width,
  int height, {
  required ThermalPosPrinterPageSize paperSize,
  required CapabilityProfile profile,
}) {
  if (width == 0 || height == 0) return const [];

  // Keep within the print head; wider bitmaps desync the image command. The
  // widget is laid out at most this wide, so this is only a safeguard.
  final maxWidth = paperSize.widthPx.toInt();
  if (width > maxWidth) {
    final resized = img.copyResize(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: rgba.buffer,
        bytesOffset: rgba.offsetInBytes,
        numChannels: 4,
      ),
      width: maxWidth,
    );
    rgba = resized.getBytes(order: img.ChannelOrder.rgba);
    width = resized.width;
    height = resized.height;
  }

  final generator = Generator(paperSize.toPaperSize, profile);
  // One image for the whole receipt: images split into pieces leave white seams.
  return [
    ...generator.setStyles(const PosStyles(align: PosAlign.center)),
    ...columnImageBands(rgba, width, height),
    ...generator.feed(2),
    ...generator.cut(),
  ];
}

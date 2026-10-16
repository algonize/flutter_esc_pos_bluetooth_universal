import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/raster/widget_raster.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders a width-filling receipt (Row + Expanded) without layout errors', (
    tester,
  ) async {
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

    final ticket = await tester.runAsync(
      () => buildWidgetTicket(
        context,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('ALGORAMMING CAFE'),
            Row(
              children: [
                Expanded(child: Text('Latte')),
                Text('4.20'),
              ],
            ),
          ],
        ),
        paperSize: ThermalPosPrinterPageSize.size58mm,
        profile: profile,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(ticket, isNotNull);
    expect(ticket!.bytes, isNotEmpty);
    expect(ticket.bands, isNotEmpty);
    // No initialise command (ESC @): the ticket starts by setting left
    // alignment, which the trimmed bands need whatever an earlier ticket
    // left the printer in.
    expect(ticket.bytes.sublist(0, 3), [0x1b, 0x61, 0x30]);
    expect(ticket.bands.first.start, greaterThanOrEqualTo(3));
  });
}

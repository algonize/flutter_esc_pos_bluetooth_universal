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

    final bytes = await tester.runAsync(
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
    expect(bytes, isNotNull);
    expect(bytes, isNotEmpty);
  });
}

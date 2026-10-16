# flutter_esc_pos_bluetooth_universal example

A small app that finds a Bluetooth thermal printer and prints on it in the two ways the package
offers:

- **Print test ticket**: raw ESC/POS bytes built with the re-exported `Generator`, sent with
  `printTicket`.
- **Print widget**: any Flutter widget, rendered at the paper width and sent with `printWidget`.

## Run it

```bash
cd example
flutter pub get
flutter run   # Android, iOS, macOS, Windows, Linux or Chrome
```

1. Choose the paper size (58, 72 or 80 mm).
2. On a phone or computer, tap **Scan** and then your printer. In Chrome or Edge, tap
   **BLE printer** or **Classic printer (paired)** and pick it in the browser's chooser.
3. Tap **Print test ticket** or **Print widget**.

The Bluetooth permissions and usage descriptions are already set in this example's Android
manifest, iOS and macOS `Info.plist` files and macOS entitlements. The package README lists what
your own app needs.

## The two print calls

```dart
final manager = PrinterBluetoothManager(
  license: License.nonprofit,
  paperSize: ThermalPosPrinterPageSize.size80mm,
);
await manager.selectPrinter(printer); // from a scan, pairedPrinters() or requestPrinter() on the web

// Raw ESC/POS bytes.
final generator = Generator(PaperSize.mm80, await CapabilityProfile.load());
await manager.printTicket([
  ...generator.text('Hello', styles: const PosStyles(bold: true)),
  ...generator.feed(2),
  ...generator.cut(),
]);

// Any widget.
await manager.printWidget(context, child: const MyReceipt());
```

`License.nonprofit` covers personal, nonprofit and educational use. Use `License.commercial` for
any for-profit use (see the flutter_blue_plus licence).

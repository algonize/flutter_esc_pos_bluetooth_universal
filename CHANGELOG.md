# 1.0.0

First release of **flutter_esc_pos_bluetooth_universal**, a complete rewrite of [`esc_pos_bluetooth`](https://github.com/andrey-ushakov/esc_pos_bluetooth) / [`flutter_esc_pos_bluetooth`](https://pub.dev/packages/flutter_esc_pos_bluetooth). It is the Bluetooth companion of [`flutter_esc_pos_network_universal`](https://pub.dev/packages/flutter_esc_pos_network_universal) and shares its API.

- **Universal Support**: One API for Android, iOS, macOS, Windows, Linux and Flutter Web.
- **BLE Printers**: Printing through `flutter_blue_plus` 2.x on every platform. In the browser it uses Web Bluetooth.
- **Bluetooth Classic (SPP) Printers**: Support for the kind most 58/80 mm POS printers are.
  - Android, Windows, macOS and Linux use `flutter_classic_bluetooth`.
  - Chromium browsers use Web Serial over Bluetooth RFCOMM (desktop Chrome 117+), with no browser extension needed.
  - iOS is BLE only, because Apple allows Classic Bluetooth only for MFi accessories.
- **Smart Characteristic Selection**: Finds the BLE characteristic to print on:
  - It first tries a table of common printer services (`defaultBlePrinterServices`), then falls back to any writable characteristic.
  - The choice is saved on the printer, so later connections skip the search.
  - Apps can add their own UUIDs through `bleServices`.
- **Reliable Writes**:
  - BLE data is sent in chunks sized to the negotiated MTU, and the size steps down automatically when a write is rejected.
  - Classic and Web Serial stream in larger slices with a short pause between them.
  - Everything can be tuned through `BluetoothWriteOptions`.
- **Widget Printing**: `printWidget` renders any Flutter widget as a receipt. It uses the same image pipeline as the network package: 8-bit normalisation (the iOS fix), clamping to the print-head width, and image processing in a background isolate on native platforms.
- **Discovery**:
  - On native platforms, BLE and Classic scanning are merged into one list, with paired printers first, then by signal strength.
  - `pairedPrinters()` lists printers usable without scanning.
  - On the web, `requestPrinter()` opens the browser's chooser.
- **Saved Printers**: `BluetoothPrinter` converts to and from JSON, so a chosen printer can be stored and used again without scanning.
- **Platform Insight**:
  - `capabilities` reports what the platform supports.
  - `checkAvailability()` reports whether Bluetooth is on, off, unauthorized or unsupported.
  - `requestPermissions()` asks for Bluetooth permissions on Android 12+.
  - `connectionStatus` streams the connection state.
- **Clear Results**: `PosPrintResult` is now an enum with a readable `msg`. Names shared with the network package (`success`, `timeout`, `ticketEmpty`, `printInProgress`, …) mean the same thing. Bluetooth adds `bluetoothUnavailable`, `permissionDenied`, `unsupported`, `userCancelled`, `printerAccessRequired`, `noWritableCharacteristic`, `connectionFailed` and `writeFailed`.
- **Paper Size Support**: 58 mm, 72 mm and 80 mm paper widths.
- **Example App**: A full example for every platform. It covers scanning or the web chooser, a test ticket and widget printing, with Bluetooth permissions already configured.

### Migrating from `esc_pos_bluetooth` / `flutter_esc_pos_bluetooth`

- **`PrinterBluetooth`** is now **`BluetoothPrinter`**, a plain data class with `id`, `name`, `type` (`ble` / `classic`) and `toJson()` / `fromJson()`.
- **`PrinterBluetoothManager()`** now needs a `license` (`License.nonprofit` or `License.commercial`). The value is passed to `flutter_blue_plus`, whose own licence requires it.
- **`startScan(Duration)`** is now `startScan({timeout})` and returns a `Future`. **`selectPrinter`** is now asynchronous as well.
- **`printTicket`** takes raw ESC/POS bytes (`List<int>`). Build them with the re-exported `Generator` from `flutter_esc_pos_utils`; the old `Ticket` class is gone.
- **`queueSleepTimeMs` / `chunkSizeBytes`** are replaced by `BluetoothWriteOptions`.
- **`PosPrintResult`** is an enum. Compare with `==` as before, and read the text from `msg`.
- **`flutter_blue` and `rxdart`** are no longer dependencies.

### Requirements

- Dart 3.12+ and Flutter 3.44+ (required by `flutter_classic_bluetooth`).
- `flutter_blue_plus` is under the FlutterBluePlus License. It is free for personal, nonprofit and educational use; for-profit use needs a commercial licence from its authors. See the README.

Based on the original work by Andrey Ushakov ([esc_pos_bluetooth](https://github.com/andrey-ushakov/esc_pos_bluetooth), BSD-3).

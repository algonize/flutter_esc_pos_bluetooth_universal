# 1.0.0

First release of **flutter_esc_pos_bluetooth_universal**, a complete rewrite of [`esc_pos_bluetooth`](https://github.com/andrey-ushakov/esc_pos_bluetooth) / [`flutter_esc_pos_bluetooth`](https://pub.dev/packages/flutter_esc_pos_bluetooth). It is the Bluetooth companion of [`flutter_esc_pos_network_universal`](https://pub.dev/packages/flutter_esc_pos_network_universal) and shares its API.

- **Universal Support**: One API for Android, iOS, macOS, Windows, Linux and Flutter Web.
- **BLE Printers**: Printing through `flutter_blue_plus` 2.x on every platform. In the browser it uses Web Bluetooth.
- **Bluetooth Classic (SPP) Printers**: Support for the kind most 58/80 mm POS printers are.
  - Android, Windows, macOS and Linux use `flutter_classic_bluetooth`.
  - Chromium browsers use Web Serial over Bluetooth RFCOMM (desktop Chrome 117+), with no browser extension needed.
  - On macOS, where RFCOMM connections can stall until they time out, a Classic printer is reached through its BLE side when it has one (most are dual-mode), found by name. RFCOMM is the fallback, tried once.
  - iOS is BLE only, because Apple allows Classic Bluetooth only for MFi accessories.
- **Smart Characteristic Selection**: Finds the BLE characteristic to print on:
  - It first tries a table of common printer services (`defaultBlePrinterServices`), then falls back to any writable characteristic.
  - Printers often expose several known services and only some reach the print engine (the Deli ES421 takes data on 18F0 and FF00, while its ISSC UART accepts writes and drops them). So printer services come before the module UART, and when several match, a status request (DLE EOT 1, prints nothing) picks the one the printer answers on.
  - The choice is saved on the printer, so later connections skip the search.
  - Apps can add their own UUIDs through `bleServices`.
- **Reliable Writes**:
  - BLE data is sent in chunks sized to the negotiated MTU, and the size steps down automatically when a write is rejected.
  - A BLE write without response only queues the data, and closing the link straight after throws the queue away. So the last chunk is sent with response when the printer allows it, and the ticket is known to have arrived before the link closes.
  - BLE connects wait briefly for Bluetooth to be ready, so a printer reconnected right at app launch doesn't fail while the adapter state is still unknown.
  - On the web, BLE chunks are written in batches: a few without response, then one confirmed by the printer (`webBleBatchSize`, default 4). Browsers report a write without response as done at once, and Chrome on macOS drops the ones CoreBluetooth can't queue without an error, so tickets could vanish while the print reported success. Confirming one chunk per batch keeps the queue from overflowing while running about twice as fast as confirming every chunk (measured ~5.5 vs ~2.9 kB/s on a Deli ES421). Chunks are 182 bytes; larger BLE writes are fragmented and slower on macOS. A printer that only takes write without response gets 20-byte chunks, 20 ms apart; one that only takes write with response confirms every chunk.
  - Web Serial opens the port with a 16 KB buffer instead of Chrome's default of 255 bytes. Chrome sends one buffer at a time and waits on the Bluetooth link after each, so a widget receipt (8 to 100 KB) used to go out 255 bytes per round trip.
  - Web Serial waits until the browser has sent every byte before closing the port. A write there only buffers the bytes, and closing the port throws that buffer away and drops the Bluetooth link, so a ticket could print in full, in part or not at all while always reporting success.
  - On the web, a BLE link the printer dropped is reported as `printerNotConnected`, and Chrome's "Unsupported device" (a dual-mode printer paired in macOS, which Chrome can only reach as Classic) as `unsupported`.
  - Classic and Web Serial stream in larger slices with a short pause between them.
  - Everything can be tuned through `BluetoothWriteOptions`.
- **Widget Printing**: `printWidget` renders any Flutter widget as a receipt. The widget is laid out at most as wide as the paper, so width-filling layouts such as `Row` + `Expanded` work. It prints exactly the bytes the network package prints (ESC * bands, clamped to the print-head width), but builds them about 20 times faster: from the raw 8-bit pixels of the capture, with no PNG encode and decode and none of the image package's whole-image passes. In a release web build a long 80 mm receipt went from 147 ms to 6 ms. The pixels are always 8 bits per channel, so the 16-bit capture of real iOS devices can't garble the output.
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
  - `lastError` holds the underlying error behind the last failure, for logs and bug reports.
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

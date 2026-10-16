# 1.0.0

First release of **flutter_esc_pos_bluetooth_universal**, a complete rewrite of [`esc_pos_bluetooth`](https://github.com/andrey-ushakov/esc_pos_bluetooth) / [`flutter_esc_pos_bluetooth`](https://pub.dev/packages/flutter_esc_pos_bluetooth). It is the Bluetooth companion of [`flutter_esc_pos_network_universal`](https://pub.dev/packages/flutter_esc_pos_network_universal) and shares its API.

- **Universal support**: one API for Android, iOS, macOS, Windows, Linux and Flutter Web.
- **BLE printers** through `flutter_blue_plus` 2.x on every platform; in the browser it uses Web Bluetooth.
- **Bluetooth Classic (SPP) printers**, the kind most 58/80 mm POS printers are:
  - Android, Windows, macOS and Linux use `flutter_classic_bluetooth`.
  - Chromium browsers use Web Serial over Bluetooth RFCOMM (desktop Chrome 117+), with no browser extension.
  - On macOS, where RFCOMM connections can stall, a Classic printer is reached through its BLE side when it has one (most are dual-mode), found by name. RFCOMM is the fallback.
  - iOS is BLE only, because Apple allows Classic Bluetooth only for MFi accessories.
- **Characteristic selection**: tries a table of common printer services (`defaultBlePrinterServices`), then any writable characteristic. When several known ones match (the Deli ES421 takes data on 18F0 and FF00 while its ISSC UART accepts writes and drops them), a status request picks the one the printer answers on. The choice is saved on the printer. Apps can add their own UUIDs through `bleServices`.
- **Clean widget receipts**, sent exactly as the network package sends them: one image of `ESC *` column bands, then a feed and a cut. No raster commands, nothing that depends on what the receipt holds.
  - **No white lines**: the bands are bracketed by `ESC 3 0` / `ESC 2`, so each line feed moves the paper exactly one band.
  - **Every part prints, no random characters**: Bluetooth has no TCP window to slow the sender, so every write is paced to the print speed (`WritePacing`: 50 mm/s on text, 2.5 mm/s on dense bands, 4 kB burst). A band is dense when a quarter of its bits are set, measured from the picture itself, so any logo, QR code or barcode gets its time.
  - **Timing that follows the printer**: a printer prints a band only once all of it has arrived, so each band goes out at link speed and the next waits for its print time. Paying for a band while sending it left the printer idle while a graphic trickled in, then flooded it with the text after the graphic while it was still printing it, and a 58 mm printer threw that text away. Each byte is charged once, even when the radio asks for a write to be retried.
  - Explicit left alignment at the start of every ticket and no `ESC @`, as in the network package.
  - Built straight from the captured 8-bit pixels: the same dots as `Generator.image`, trimmed of blank columns, about 20 times faster, and immune to the 16-bit captures that garbled receipts on real iPhones.
  - Bytes that would spell a real-time command (`DLE EOT`, `DLE ENQ`, `DLE DC4`) never appear in image data.
  - `gapMm` leaves blank paper below the receipt for tearing by hand.
- **Reliable writes**:
  - BLE chunks follow the negotiated MTU and step down when a write is rejected for its length; a write refused for a busy radio is retried at the same size.
  - The last BLE chunk is sent with response when possible, so the ticket has arrived before the link closes.
  - On the web, BLE writes go in batches with one confirmed write every `webBleBatchSize` chunks, as Chrome on macOS silently drops unconfirmed writes its queue cannot hold.
  - Web Serial opens the port with a 16 KB buffer and waits until the browser has sent every byte before closing it.
- **Raw ESC/POS**: `printTicket` sends bytes from the re-exported `Generator`, paced by the dots they print.
- **Discovery**: BLE and Classic scanning merged into one list (paired first, then by signal strength), `pairedPrinters()`, and `requestPrinter()` for the browser chooser.
- **Saved printers**: `BluetoothPrinter` converts to and from JSON.
- **Platform insight**: `capabilities`, `checkAvailability()`, `requestPermissions()`, `connectionStatus`, `lastError` and `lastPrint`.
- **Clear results**: `PosPrintResult` is an enum with a readable `msg`, its shared names matching the network package.
- **Paper sizes**: 58 mm, 72 mm and 80 mm.
- **Example app** for every platform.

### Migrating from `esc_pos_bluetooth` / `flutter_esc_pos_bluetooth`

- **`PrinterBluetooth`** is now **`BluetoothPrinter`**, a plain data class with `id`, `name`, `type` (`ble` / `classic`) and `toJson()` / `fromJson()`.
- **`PrinterBluetoothManager()`** now needs a `license` (`License.nonprofit` or `License.commercial`), passed to `flutter_blue_plus`, whose own licence requires it.
- **`startScan(Duration)`** is now `startScan({timeout})` and returns a `Future`. **`selectPrinter`** is asynchronous as well.
- **`printTicket`** takes raw ESC/POS bytes (`List<int>`). Build them with the re-exported `Generator`; the old `Ticket` class is gone.
- **`queueSleepTimeMs` / `chunkSizeBytes`** are replaced by `BluetoothWriteOptions`.
- **`PosPrintResult`** is an enum. Compare with `==` as before, and read the text from `msg`.
- **`flutter_blue` and `rxdart`** are no longer dependencies.

### Requirements

- Dart 3.12+ and Flutter 3.44+ (required by `flutter_classic_bluetooth`).
- `flutter_blue_plus` is under the FlutterBluePlus License: free for personal, nonprofit and educational use; for-profit use needs a commercial licence from its authors.

Based on the original work by Andrey Ushakov ([esc_pos_bluetooth](https://github.com/andrey-ushakov/esc_pos_bluetooth), BSD-3).

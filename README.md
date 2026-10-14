# Flutter ESC/POS Bluetooth Universal

[![pub package](https://img.shields.io/pub/v/flutter_esc_pos_bluetooth_universal.svg)](https://pub.dev/packages/flutter_esc_pos_bluetooth_universal)
[![platform](https://img.shields.io/badge/platform-android%20%7C%20ios%20%7C%20macos%20%7C%20windows%20%7C%20linux%20%7C%20web-blue.svg)](https://pub.dev/packages/flutter_esc_pos_bluetooth_universal)
[![license](https://img.shields.io/badge/license-BSD--3-green.svg)](LICENSE)

Print receipts on **ESC/POS thermal Bluetooth printers** from **Android, iOS, macOS, Windows, Linux and Flutter Web**, with one API.

It supports both kinds of Bluetooth printer:
- **BLE** printers, on every platform including iOS and the browser.
- **Bluetooth Classic (SPP)** printers, which most 58/80 mm POS printers are, on Android and desktop. In Chrome and Edge it uses Web Serial, so no browser extension is needed.

> A complete rewrite of [`esc_pos_bluetooth`](https://github.com/andrey-ushakov/esc_pos_bluetooth) / [`flutter_esc_pos_bluetooth`](https://pub.dev/packages/flutter_esc_pos_bluetooth). It is the Bluetooth companion of [`flutter_esc_pos_network_universal`](https://pub.dev/packages/flutter_esc_pos_network_universal) and shares its API, so Wi-Fi and Bluetooth printers can be driven by the same code.

---

## ✨ Features

- **One API everywhere.** Android, iOS, macOS, Windows, Linux and Web.
- **BLE and Classic.** Scanning merges both. Each printer is reached over the right link automatically.
- **Works with real printers.**
  - Picks the printer's BLE write characteristic from a table of common printer UUIDs, then falls back to any writable one.
  - Remembers the choice per printer.
- **Fast and safe writes.**
  - BLE chunks follow the negotiated MTU and step down automatically if a write is rejected.
  - Classic and Web Serial stream in large slices.
  - A print only reports success once the data has actually left: on the web, every BLE chunk is confirmed by the printer and Web Serial waits until the browser has sent every byte.
  - All of this can be tuned with `BluetoothWriteOptions`.
- **Widget printing.** `printWidget` renders any Flutter widget (logos, QR codes, any script) into the same bytes as the network package prints, built straight from the captured pixels, so even long receipts encode in a few milliseconds, in the browser too.
- **Raw ESC/POS.** `printTicket` sends bytes from the re-exported `flutter_esc_pos_utils` `Generator`.
- **Save and reconnect.** `BluetoothPrinter` is plain JSON-serialisable data.

---

## 📋 Platform support

| Platform | BLE printers | Classic (SPP) printers | How printers are found |
|---|---|---|---|
| Android | ✅ | ✅ | Scan + paired list |
| iOS / iPadOS | ✅ | ❌ (Apple allows Classic only for MFi accessories) | Scan |
| macOS | ✅ | ✅ through the printer's BLE side when it has one; RFCOMM is unreliable | Scan + paired list |
| Windows | ✅ | ✅ | Scan + paired list |
| Linux | ✅ | ✅ | Scan + paired list |
| Web: Chrome, Edge, Opera, Brave | ✅ Web Bluetooth | ✅ Web Serial (desktop Chrome 117+, paired printers) | Browser chooser |
| Web: Safari, Firefox, iOS browsers | ❌ | ❌ | Browsers without Bluetooth APIs |

At runtime, `PrinterBluetoothManager.capabilities` tells you which of these apply.

---

## 🚀 Installation

```yaml
dependencies:
  flutter_esc_pos_bluetooth_universal: <latest-version>
```

```dart
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
```

### Platform setup

<details>
<summary><b>Android</b>: permissions in <code>android/app/src/main/AndroidManifest.xml</code></summary>

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```
Call `manager.requestPermissions()` at a moment the user expects it. Scanning also asks when needed.
</details>

<details>
<summary><b>iOS / macOS</b>: usage text (and a macOS entitlement)</summary>

`Info.plist`:
```xml
<key>NSBluetoothAlwaysUsageDescription</key>
<string>Bluetooth is used to find and print on your receipt printer.</string>
```
macOS `DebugProfile.entitlements` and `Release.entitlements`:
```xml
<key>com.apple.security.device.bluetooth</key>
<true/>
```
Classic (RFCOMM) connections are unreliable on current macOS: the connection attempt can stall until it times out. Most Classic POS printers are dual-mode, so on macOS a Classic printer is reached through its BLE side when it has one (found by name), and the manager's `selectedPrinter` becomes that BLE printer. RFCOMM is only tried for printers with no BLE side.
</details>

<details>
<summary><b>Windows / Linux</b></summary>

Nothing extra. Classic printers usually need pairing in the system's Bluetooth settings first (PIN `0000` or `1234`). On Linux, BlueZ must be running.
</details>

<details>
<summary><b>Web</b></summary>

- Serve the app over **HTTPS** (`localhost` is fine while developing).
- Browsers can't scan, so printers are picked with `requestPrinter()`, which **must be called from a button tap**.
- Classic printers must be **paired in the operating system** first; they then appear in Chrome's serial port chooser. Bluetooth Classic printers speak the Serial Port Profile (a serial cable over Bluetooth), which is why Chrome offers them through Web Serial: Web Bluetooth only reaches BLE.
</details>

---

## ⚡ Quick start

```dart
final manager = PrinterBluetoothManager(
  // Passed to flutter_blue_plus for BLE connections. See "Licensing" below.
  license: License.nonprofit,
  paperSize: ThermalPosPrinterPageSize.size80mm,
);
```

### 1. Pick a printer

**Android, iOS, macOS, Windows, Linux:** scan, then select.

```dart
if (await manager.checkAvailability() != BluetoothAvailability.available) {
  // Ask the user to switch Bluetooth on.
}

manager.scanResults.listen((printers) {
  // BLE and Classic printers, paired first, strongest signal next.
});
await manager.startScan(timeout: const Duration(seconds: 8));

// Later, from your list:
await manager.selectPrinter(printer);
```

**Web:** open the browser's chooser from a button.

```dart
ElevatedButton(
  onPressed: () async {
    final printer = await manager.requestPrinter(type: BluetoothPrinterType.ble);
    // or BluetoothPrinterType.classic for paired SPP printers (Web Serial)
    if (printer == null) return; // chooser closed
  },
  child: const Text('Choose printer'),
)
```

### 2. Print raw ESC/POS bytes

```dart
final generator = Generator(PaperSize.mm80, await CapabilityProfile.load());

final result = await manager.printTicket([
  ...generator.text('ALGORAMMING CAFE', styles: const PosStyles(align: PosAlign.center, bold: true)),
  ...generator.text('Espresso .......... \$3.00'),
  ...generator.feed(2),
  ...generator.cut(),
]);

if (result != PosPrintResult.success) debugPrint(result.msg);
```

`printTicket` connects when needed and disconnects afterwards. To send several tickets over one connection:

```dart
await manager.connect();
await manager.printTicket(ticket1, isDisconnect: false);
await manager.printTicket(ticket2, isDisconnect: false);
await manager.disconnect();
```

### 3. Print a Flutter widget

```dart
await manager.printWidget(context, child: const MyReceiptWidget());
```

### 4. Save the printer and reconnect later

```dart
// After a successful connection: this copy also holds the resolved BLE characteristic.
final json = manager.selectedPrinter!.toJson();
// … store it, then on the next launch:
final manager = PrinterBluetoothManager(
  license: License.nonprofit,
  printer: BluetoothPrinter.fromJson(json),
);
await manager.printTicket(bytes);
```

On the web, a saved **BLE** printer must be chosen again once per page load (`requestPrinter`), because browsers only grant access through their chooser. Saved **Web Serial** printers reconnect without asking, as Chrome remembers the permission.

---

## ⚙️ Tuning writes

The defaults suit most printers. If long tickets or images come out cut short or garbled, slow down a little:

```dart
PrinterBluetoothManager(
  license: License.nonprofit,
  writeOptions: const BluetoothWriteOptions(
    bleChunkSize: 100,                                 // default: MTU - 3 (182 on web)
    bleChunkDelay: Duration(milliseconds: 5),
    preferWriteWithoutResponse: true,
    classicChunkSize: 1024,
    classicChunkDelay: Duration(milliseconds: 20),
    classicSecureConnection: true,                     // false for some older printers
  ),
);
```

On the web, every BLE chunk is written with response, so the printer confirms each one. Browsers report a write without response as done straight away, and Chrome on macOS drops the ones the system can't queue without any error, which made tickets vanish while the print "succeeded". Chunks start at 182 bytes. Browsers don't expose the MTU, but a longer write with response is sent as a long write or rejected, never cut short, and a rejected size steps down. A printer that only takes write without response gets 20-byte chunks, 20 ms apart.

If your BLE printer uses UUIDs not in `defaultBlePrinterServices`, add them:

```dart
PrinterBluetoothManager(
  license: License.nonprofit,
  bleServices: [
    const BlePrinterService('0000ae30-0000-1000-8000-00805f9b34fb', '0000ae01-0000-1000-8000-00805f9b34fb'),
    ...defaultBlePrinterServices,
  ],
);
```

---

## 📚 API reference

### `PrinterBluetoothManager`

| Member | Description |
|---|---|
| `capabilities` *(static)* | What this platform supports: `ble`, `classic`, `scan`, `chooser`, `pairedList` |
| `checkAvailability()` | `available`, `poweredOff`, `unauthorized`, `unsupported` or `unknown` |
| `requestPermissions()` | Asks for Bluetooth permissions (Android 12+) |
| `startScan({timeout, types, includeUnnamed})` / `stopScan()` | Native platforms: find nearby printers |
| `scanResults` / `lastScanResults` / `isScanningStream` | Scan output |
| `pairedPrinters()` | Paired Classic printers, or serial ports the page may already use (web) |
| `requestPrinter({type})` | Web: browser chooser. Must run from a user gesture |
| `selectPrinter(printer)` / `selectedPrinter` | The printer to use |
| `connect({timeout})` / `disconnect()` / `isConnected` | Connection control |
| `connectionStatus` / `status` | `disconnected`, `connecting`, `connected`, `disconnecting` |
| `printTicket(bytes, {isDisconnect})` | Sends raw ESC/POS bytes |
| `printWidget(context, {child, isDisconnect})` | Renders and prints a widget |
| `lastError` | The underlying error behind the last failed connect or print, for logs and bug reports |
| `dispose()` | Disconnects and releases the manager |

Every action returns a `PosPrintResult` with a readable `msg`. The names shared with the network package (`success`, `timeout`, `ticketEmpty`, `printInProgress`, …) mean the same thing. Bluetooth adds `bluetoothUnavailable`, `permissionDenied`, `unsupported`, `userCancelled`, `printerAccessRequired`, `noWritableCharacteristic`, `connectionFailed` and `writeFailed`.

---

## 🏗️ How it works

```
PrinterBluetoothManager  (public API)
   │
   ├── Native (dart:io)
   │     ├── BLE      → flutter_blue_plus           (Android · iOS · macOS · Windows · Linux)
   │     └── Classic  → flutter_classic_bluetooth   (Android · Windows · macOS · Linux)
   │
   └── Web (dart:js_interop)
         ├── BLE      → Web Bluetooth via flutter_blue_plus_web
         └── Classic  → Web Serial over Bluetooth RFCOMM
```

The platform is picked at compile time by conditional import, like the network package.

---

## 🧰 Troubleshooting

| Problem | Try |
|---|---|
| Printer not in the scan | Many Classic printers only appear when paired. Pair it in system settings, then use `pairedPrinters()`. |
| iPhone can't see a Classic printer | iOS doesn't allow Classic SPP. Use a BLE or dual-mode printer. |
| `noWritableCharacteristic` | Add the printer's service and characteristic through `bleServices`. |
| BLE print reports success but nothing prints | The data went to a characteristic that isn't wired to the print engine. Put the right pair first in `bleServices`, or clear the saved `serviceUuid` / `characteristicUuid` so it's detected again. |
| macOS: Classic printer times out | Use the printer's BLE entry from the scan. Dual-mode printers are routed there automatically. |
| Ticket cut short or garbled | Lower `bleChunkSize` / `classicChunkSize` or add a small delay. |
| `printerAccessRequired` on web | Call `requestPrinter()` again from a button. The browser forgot the device. |
| Web on macOS: `unsupported` when connecting a BLE printer | Chrome lists a dual-mode printer paired in System Settings under its Classic address, and can't open BLE on it. Choose it as a Classic printer (Web Serial) instead. |
| Widget prints nothing, text tickets print | Check the paper size. A 58 mm printer (384 dots, such as the Deli ES421) can't print an image laid out for 80 mm. |
| Classic printer won't connect | Pair it first. For old printers, try `classicSecureConnection: false`. |

Found a printer that works (or doesn't)? Add it to [printers.md](printers.md).

---

## ⚖️ Licensing

This package is BSD-3 licensed (see [LICENSE](LICENSE)). It builds on two plugins with their own terms:

- **[`flutter_blue_plus`](https://pub.dev/packages/flutter_blue_plus)** (BLE) is under the **FlutterBluePlus License**.
  - Free for personal use, registered nonprofits and educational institutions.
  - **Any for-profit use requires a commercial licence** from its authors.
  - That's why `PrinterBluetoothManager` asks for `license`: pass `License.nonprofit` or `License.commercial` to match your situation.
- **[`flutter_classic_bluetooth`](https://pub.dev/packages/flutter_classic_bluetooth)** (Classic) is MIT.

---

## 🙏 Credits

- Based on the original work by Andrey Ushakov ([esc_pos_bluetooth](https://github.com/andrey-ushakov/esc_pos_bluetooth)).
- Rewritten by [Algoramming Systems Ltd.](https://www.algonize.xyz)

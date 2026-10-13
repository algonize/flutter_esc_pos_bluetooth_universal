import 'package:flutter/foundation.dart';

/// What the current platform can do, so an app can show the right buttons.
@immutable
class BluetoothCapabilities {
  const BluetoothCapabilities({
    required this.ble,
    required this.classic,
    required this.scan,
    required this.chooser,
    required this.pairedList,
  });

  /// BLE printers can be used.
  final bool ble;

  /// Bluetooth Classic (SPP) printers can be used.
  /// False on iOS (Apple allows Classic only for MFi accessories) and in
  /// browsers without Web Serial.
  final bool classic;

  /// [PrinterBluetoothManager.startScan] can list nearby printers.
  /// False on the web, where browsers only offer their own chooser.
  final bool scan;

  /// Printers are picked through a browser chooser with
  /// [PrinterBluetoothManager.requestPrinter]. True on the web only.
  final bool chooser;

  /// [PrinterBluetoothManager.pairedPrinters] can return printers without a
  /// scan (paired Classic printers, or ports the page was already allowed to use).
  final bool pairedList;

  static const none = BluetoothCapabilities(
    ble: false,
    classic: false,
    scan: false,
    chooser: false,
    pairedList: false,
  );

  @override
  String toString() =>
      'BluetoothCapabilities(ble: $ble, classic: $classic, scan: $scan, '
      'chooser: $chooser, pairedList: $pairedList)';
}

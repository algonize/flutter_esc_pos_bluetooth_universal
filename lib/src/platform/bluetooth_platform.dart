import 'package:flutter_blue_plus/flutter_blue_plus.dart' show License;

import '../enums.dart';
import '../models/ble_printer_service.dart';
import '../models/bluetooth_capabilities.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../transport/printer_transport.dart';

/// Discovery and transport creation for one platform family. Picked at compile
/// time: `bluetooth_platform_io.dart` or `bluetooth_platform_web.dart`.
abstract interface class BluetoothPlatform {
  BluetoothCapabilities get capabilities;

  Future<BluetoothAvailability> availability();

  /// Asks for the runtime permissions scanning and connecting need (Android).
  /// Returns whether they are granted.
  Future<bool> requestPermissions();

  /// Printers found by the current or last scan, strongest signal first.
  Stream<List<BluetoothPrinter>> get scanResults;
  List<BluetoothPrinter> get lastScanResults;
  Stream<bool> get isScanning;
  bool get isScanningNow;

  Future<void> startScan({
    required Duration timeout,
    required Set<BluetoothPrinterType> types,
    required List<BlePrinterService> bleServices,
    required bool includeUnnamed,
  });

  Future<void> stopScan();

  /// Printers usable without a scan: paired Classic printers (native) or ports
  /// this page may already use (web).
  Future<List<BluetoothPrinter>> pairedPrinters();

  /// Opens the browser's device chooser. Web only; must run from a user gesture.
  /// Returns null when the user closes the chooser.
  Future<BluetoothPrinter?> requestPrinter({
    required BluetoothPrinterType type,
    required List<BlePrinterService> bleServices,
  });

  PrinterTransport createTransport(
    BluetoothPrinter printer, {
    required License license,
    required BluetoothWriteOptions options,
    required List<BlePrinterService> bleServices,
  });
}

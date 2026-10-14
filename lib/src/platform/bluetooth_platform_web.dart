import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:web/web.dart' as web;

import '../enums.dart';
import '../models/ble_printer_service.dart';
import '../models/bluetooth_capabilities.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../transport/ble_transport.dart';
import '../transport/printer_transport.dart';
import '../utils/write_pacer.dart';
import '../transport/web_serial_bindings.dart';
import '../transport/web_serial_transport.dart';
import 'bluetooth_platform.dart';

/// Chromium browsers (Chrome, Edge, Opera, Brave). Browsers don't let pages
/// scan, so printers are picked through the browser's own chooser:
/// - BLE printers: Web Bluetooth (through flutter_blue_plus_web).
/// - Classic printers: Web Serial over Bluetooth RFCOMM (desktop Chrome 117+).
class WebBluetoothPlatform implements BluetoothPlatform {
  WebBluetoothPlatform._();

  static final WebBluetoothPlatform instance = WebBluetoothPlatform._();

  /// Serial ports this page was allowed to use, keyed by printer id.
  /// Port objects can't be saved, so ids only last for the page session.
  final Map<String, SerialPort> _ports = {};
  int _portCounter = 0;

  bool get _hasWebBluetooth => (web.window.navigator as JSObject).has('bluetooth');
  bool get _hasWebSerial => navigatorSerial != null;

  @override
  BluetoothCapabilities get capabilities => BluetoothCapabilities(
    ble: _hasWebBluetooth,
    classic: _hasWebSerial,
    scan: false,
    chooser: _hasWebBluetooth || _hasWebSerial,
    pairedList: _hasWebSerial,
  );

  @override
  Future<BluetoothAvailability> availability() async {
    if (!_hasWebBluetooth && !_hasWebSerial) return BluetoothAvailability.unsupported;
    if (_hasWebBluetooth) {
      try {
        // false when the computer has no Bluetooth adapter or it is switched off.
        if (await FlutterBluePlus.isSupported) return BluetoothAvailability.available;
      } catch (_) {}
      if (!_hasWebSerial) return BluetoothAvailability.poweredOff;
    }
    return BluetoothAvailability.available;
  }

  @override
  Future<bool> requestPermissions() async => true; // The browser asks in its chooser.

  @override
  Stream<List<BluetoothPrinter>> get scanResults => const Stream.empty();

  @override
  List<BluetoothPrinter> get lastScanResults => const [];

  @override
  Stream<bool> get isScanning => Stream.value(false);

  @override
  bool get isScanningNow => false;

  @override
  Future<void> startScan({
    required Duration timeout,
    required Set<BluetoothPrinterType> types,
    required List<BlePrinterService> bleServices,
    required bool includeUnnamed,
  }) async {
    // Browsers can't scan. Use requestPrinter() from a button instead.
  }

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<BluetoothPrinter>> pairedPrinters() async {
    final serial = navigatorSerial;
    if (serial == null) return const [];
    try {
      final ports = (await serial.getPorts().toDart).toDart;
      final printers = <BluetoothPrinter>[];
      for (final port in ports) {
        // Only Bluetooth ports; USB serial adapters are out of scope here.
        if (port.getInfo().bluetoothServiceClassId == null) continue;
        printers.add(_registerPort(port));
      }
      return printers;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<BluetoothPrinter?> requestPrinter({
    required BluetoothPrinterType type,
    required List<BlePrinterService> bleServices,
  }) {
    return switch (type) {
      BluetoothPrinterType.ble => _requestBlePrinter(bleServices),
      BluetoothPrinterType.classic => _requestSerialPrinter(),
    };
  }

  Future<BluetoothPrinter?> _requestBlePrinter(List<BlePrinterService> services) async {
    if (!_hasWebBluetooth) {
      throw const PrinterTransportException(PosPrintResult.unsupported);
    }
    final completer = Completer<BluetoothPrinter?>();
    // flutter_blue_plus_web turns startScan into navigator.bluetooth.requestDevice
    // and reports the chosen device as a single scan result, or an error when
    // the chooser is closed.
    final subscription = FlutterBluePlus.onScanResults.listen(
      (results) {
        if (results.isEmpty || completer.isCompleted) return;
        final device = results.first.device;
        completer.complete(
          BluetoothPrinter(
            id: device.remoteId.str,
            type: BluetoothPrinterType.ble,
            name: device.platformName.isEmpty ? null : device.platformName,
          ),
        );
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.complete(null);
      },
    );
    try {
      await FlutterBluePlus.startScan(
        // Without these the browser hides the printer's services after connecting.
        webOptionalServices: [for (final s in services) Guid(s.serviceUuid)],
      );
      return await completer.future;
    } catch (_) {
      return null; // Chooser closed, or no adapter.
    } finally {
      await subscription.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  Future<BluetoothPrinter?> _requestSerialPrinter() async {
    final serial = navigatorSerial;
    if (serial == null) {
      throw const PrinterTransportException(PosPrintResult.unsupported);
    }
    try {
      final port = await serial
          .requestPort(
            SerialPortRequestOptions(
              filters: [SerialPortFilter(bluetoothServiceClassId: sppServiceClassId)].toJS,
              allowedBluetoothServiceClassIds: [sppServiceClassId.toJS].toJS,
            ),
          )
          .toDart;
      return _registerPort(port);
    } catch (e) {
      if (isDomError(e, 'NotFoundError')) return null; // Chooser closed.
      if (isDomError(e, 'SecurityError')) {
        throw PrinterTransportException(PosPrintResult.permissionDenied, e);
      }
      rethrow;
    }
  }

  BluetoothPrinter _registerPort(SerialPort port) {
    for (final entry in _ports.entries) {
      if (entry.value == port) return _serialPrinter(entry.key);
    }
    final id = 'webserial:${++_portCounter}';
    _ports[id] = port;
    return _serialPrinter(id);
  }

  BluetoothPrinter _serialPrinter(String id) => BluetoothPrinter(
    id: id,
    type: BluetoothPrinterType.classic,
    // Web Serial does not expose device names.
    name: 'Bluetooth printer (${id.split(':').last})',
    isPaired: true,
  );

  @override
  PrinterTransport createTransport(
    BluetoothPrinter printer, {
    required License license,
    required BluetoothWriteOptions options,
    required List<BlePrinterService> bleServices,
    WritePacer? pacer,
  }) {
    return switch (printer.type) {
      BluetoothPrinterType.ble => BleTransport(
        printer,
        license: license,
        options: options,
        services: bleServices,
        pacer: pacer,
      ),
      BluetoothPrinterType.classic => WebSerialTransport(
        printer,
        _ports[printer.id],
        options: options,
        pacer: pacer,
      ),
    };
  }
}

BluetoothPlatform createBluetoothPlatform() => WebBluetoothPlatform.instance;

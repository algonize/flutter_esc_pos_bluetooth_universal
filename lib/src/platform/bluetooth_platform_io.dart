import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../enums.dart';
import '../models/ble_printer_service.dart';
import '../models/bluetooth_capabilities.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../transport/ble_transport.dart';
import '../transport/classic_transport.dart';
import '../transport/mac_classic_transport.dart';
import '../transport/printer_transport.dart';
import 'bluetooth_platform.dart';

/// Android, iOS, macOS, Windows and Linux.
/// BLE through flutter_blue_plus; Classic through flutter_classic_bluetooth
/// (not on iOS, where Apple allows Classic only for MFi accessories).
class IoBluetoothPlatform implements BluetoothPlatform {
  IoBluetoothPlatform._();

  static final IoBluetoothPlatform instance = IoBluetoothPlatform._();

  final FlutterClassicBluetooth _classic = FlutterClassicBluetooth();

  final _results = <String, BluetoothPrinter>{};
  final _resultsController = StreamController<List<BluetoothPrinter>>.broadcast();
  final _scanningController = StreamController<bool>.broadcast();
  List<BluetoothPrinter> _lastResults = const [];
  bool _scanning = false;

  StreamSubscription<List<ScanResult>>? _bleSubscription;
  StreamSubscription<BtcDevice>? _classicSubscription;
  Timer? _scanTimer;

  bool get _classicSupported => !Platform.isIOS;

  @override
  BluetoothCapabilities get capabilities => BluetoothCapabilities(
    ble: true,
    classic: _classicSupported,
    scan: true,
    chooser: false,
    pairedList: _classicSupported,
  );

  @override
  Future<BluetoothAvailability> availability() async {
    try {
      if (!await FlutterBluePlus.isSupported) return BluetoothAvailability.unsupported;
      final state = await FlutterBluePlus.adapterState
          .where((s) => s != BluetoothAdapterState.unknown)
          .first
          .timeout(const Duration(seconds: 3), onTimeout: () => BluetoothAdapterState.unknown);
      return switch (state) {
        BluetoothAdapterState.on => BluetoothAvailability.available,
        BluetoothAdapterState.off ||
        BluetoothAdapterState.turningOff ||
        BluetoothAdapterState.turningOn => BluetoothAvailability.poweredOff,
        BluetoothAdapterState.unauthorized => BluetoothAvailability.unauthorized,
        BluetoothAdapterState.unavailable => BluetoothAvailability.unsupported,
        BluetoothAdapterState.unknown => BluetoothAvailability.unknown,
      };
    } catch (_) {
      return BluetoothAvailability.unknown;
    }
  }

  @override
  Future<bool> requestPermissions() async {
    if (!_classicSupported) return true; // iOS asks on first use; nothing to request here.
    try {
      var status = await _classic.checkPermissions();
      if (status == BtcPermissionStatus.denied) status = await _classic.requestPermissions();
      return status == BtcPermissionStatus.granted || status == BtcPermissionStatus.notRequired;
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<List<BluetoothPrinter>> get scanResults => _resultsController.stream;

  @override
  List<BluetoothPrinter> get lastScanResults => _lastResults;

  @override
  Stream<bool> get isScanning => _scanningController.stream;

  @override
  bool get isScanningNow => _scanning;

  @override
  Future<void> startScan({
    required Duration timeout,
    required Set<BluetoothPrinterType> types,
    required List<BlePrinterService> bleServices,
    required bool includeUnnamed,
  }) async {
    await stopScan();
    _results.clear();
    _emitResults();
    _setScanning(true);
    _scanTimer = Timer(timeout, stopScan);

    if (types.contains(BluetoothPrinterType.classic) && _classicSupported) {
      await _startClassicDiscovery(includeUnnamed);
    }
    if (types.contains(BluetoothPrinterType.ble)) {
      await _startBleScan(timeout, includeUnnamed);
    }
  }

  Future<void> _startBleScan(Duration timeout, bool includeUnnamed) async {
    _bleSubscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (name.isEmpty && !includeUnnamed) continue;
        _addResult(
          BluetoothPrinter(
            id: r.device.remoteId.str,
            type: BluetoothPrinterType.ble,
            name: name.isEmpty ? null : name,
            rssi: r.rssi,
          ),
        );
      }
    }, onError: (_) {});
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
    } catch (_) {
      // Bluetooth off or permission refused: Classic results, if any, still show.
    }
  }

  Future<void> _startClassicDiscovery(bool includeUnnamed) async {
    try {
      if (!await requestPermissions()) return;
      // Paired printers first: they show even when not discoverable right now.
      for (final device in await _classic.getPairedDevices()) {
        final printer = _fromClassic(device, includeUnnamed);
        if (printer != null) _addResult(printer.copyWith(isPaired: true));
      }
      _classicSubscription = _classic.discoveryResults.listen((device) {
        final printer = _fromClassic(device, includeUnnamed);
        if (printer != null) _addResult(printer);
      }, onError: (_) {});
      await _classic.startDiscovery();
    } catch (_) {
      // Discovery can fail when Bluetooth is off; BLE results still show.
    }
  }

  BluetoothPrinter? _fromClassic(BtcDevice device, bool includeUnnamed) {
    // BLE-only devices also show up in Classic discovery on Android.
    if (device.type == BtcDeviceType.le) return null;
    final name = device.name ?? device.alias;
    if ((name == null || name.isEmpty) && !includeUnnamed) return null;
    return BluetoothPrinter(
      id: device.address,
      type: BluetoothPrinterType.classic,
      name: name,
      rssi: device.rssi,
      isPaired: device.bondState == BtcBondState.bonded,
    );
  }

  void _addResult(BluetoothPrinter printer) {
    final key = '${printer.type.name}:${printer.id.toLowerCase()}';
    final previous = _results[key];
    _results[key] = previous == null
        ? printer
        : previous.copyWith(
            name: printer.name ?? previous.name,
            rssi: printer.rssi ?? previous.rssi,
            isPaired: previous.isPaired || printer.isPaired,
          );
    _emitResults();
  }

  void _emitResults() {
    final list = _results.values.toList()
      ..sort((a, b) {
        if (a.isPaired != b.isPaired) return a.isPaired ? -1 : 1;
        return (b.rssi ?? -1000).compareTo(a.rssi ?? -1000);
      });
    _lastResults = List.unmodifiable(list);
    _resultsController.add(_lastResults);
  }

  void _setScanning(bool value) {
    if (_scanning == value) return;
    _scanning = value;
    _scanningController.add(value);
  }

  @override
  Future<void> stopScan() async {
    _scanTimer?.cancel();
    _scanTimer = null;
    final ble = _bleSubscription;
    final classic = _classicSubscription;
    _bleSubscription = null;
    _classicSubscription = null;
    await ble?.cancel();
    await classic?.cancel();
    try {
      if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
    } catch (_) {}
    if (_classicSupported) {
      try {
        if (await _classic.isDiscovering()) await _classic.stopDiscovery();
      } catch (_) {}
    }
    _setScanning(false);
  }

  @override
  Future<List<BluetoothPrinter>> pairedPrinters() async {
    if (!_classicSupported || !await requestPermissions()) return const [];
    try {
      final devices = await _classic.getPairedDevices();
      return [
        for (final device in devices)
          if (_fromClassic(device, true) case final printer?) printer.copyWith(isPaired: true),
      ];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<BluetoothPrinter?> requestPrinter({
    required BluetoothPrinterType type,
    required List<BlePrinterService> bleServices,
  }) async => null; // Native platforms scan instead.

  @override
  PrinterTransport createTransport(
    BluetoothPrinter printer, {
    required License license,
    required BluetoothWriteOptions options,
    required List<BlePrinterService> bleServices,
  }) {
    return switch (printer.type) {
      BluetoothPrinterType.ble => BleTransport(
        printer,
        license: license,
        options: options,
        services: bleServices,
      ),
      BluetoothPrinterType.classic when !_classicSupported => _UnsupportedTransport(printer),
      BluetoothPrinterType.classic when Platform.isMacOS => MacClassicTransport(
        printer,
        license: license,
        options: options,
        services: bleServices,
      ),
      BluetoothPrinterType.classic => ClassicTransport(printer, options: options),
    };
  }
}

class _UnsupportedTransport implements PrinterTransport {
  _UnsupportedTransport(this.printer);

  @override
  final BluetoothPrinter printer;

  @override
  bool get isConnected => false;

  @override
  Future<void> connect(Duration timeout) =>
      throw const PrinterTransportException(PosPrintResult.unsupported);

  @override
  Future<void> write(List<int> data, {WriteGate? gate}) =>
      throw const PrinterTransportException(PosPrintResult.unsupported);

  @override
  Future<void> disconnect() async {}
}

BluetoothPlatform createBluetoothPlatform() => IoBluetoothPlatform.instance;

import 'dart:async';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../enums.dart';
import '../models/ble_printer_service.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import 'ble_transport.dart';
import 'classic_transport.dart';
import 'printer_transport.dart';

/// macOS: Classic printers, reached through their BLE side when they have one.
///
/// RFCOMM to SPP printers is unreliable on current macOS. The plugin's
/// asynchronous open can stall and never complete (seen with a Deli ES421 on
/// macOS 27), and the `/dev/cu.*` port macOS creates for a paired printer
/// accepts writes without ever connecting. Most Classic POS printers are
/// dual-mode, so this looks for the same printer over BLE first, by its name,
/// and falls back to RFCOMM only when it has no BLE side.
class MacClassicTransport implements PrinterTransport {
  MacClassicTransport(
    this._printer, {
    required this._license,
    required this._options,
    required this._services,
  });

  final BluetoothPrinter _printer;
  final License _license;
  final BluetoothWriteOptions _options;
  final List<BlePrinterService> _services;

  /// How long to look for the printer's BLE side. Printers advertise several
  /// times a second, so a few seconds is plenty.
  static const _bleSearchTimeout = Duration(seconds: 4);

  PrinterTransport? _active;

  /// The BLE printer once connected through it, so the manager keeps that one
  /// and later connections go straight to BLE.
  @override
  BluetoothPrinter get printer => _active?.printer ?? _printer;

  @override
  bool get isConnected => _active?.isConnected ?? false;

  @override
  Future<void> connect(Duration timeout) async {
    if (isConnected) return;

    PrinterTransportException? bleFailure;
    final blePrinter = await _findBlePrinter(
      timeout < _bleSearchTimeout ? timeout : _bleSearchTimeout,
    );
    if (blePrinter != null) {
      final ble = BleTransport(
        blePrinter,
        license: _license,
        options: _options,
        services: _services,
      );
      try {
        await ble.connect(timeout);
        _active = ble;
        return;
      } on PrinterTransportException catch (e) {
        bleFailure = e;
      }
    }

    final classic = ClassicTransport(_printer, options: _options);
    try {
      await classic.connect(timeout);
      _active = classic;
    } on PrinterTransportException {
      // The BLE error says more: RFCOMM failing on macOS is the expected case.
      if (bleFailure != null) throw bleFailure;
      rethrow;
    }
  }

  /// Scans briefly for a BLE device advertising the same name as the printer.
  Future<BluetoothPrinter?> _findBlePrinter(Duration timeout) async {
    final wanted = _printer.name?.trim().toLowerCase();
    if (wanted == null || wanted.isEmpty) return null;
    if (await settledAdapterState() != BluetoothAdapterState.on) return null;

    final found = Completer<BluetoothPrinter?>();
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (name.trim().toLowerCase() == wanted && !found.isCompleted) {
          found.complete(
            BluetoothPrinter(id: r.device.remoteId.str, type: BluetoothPrinterType.ble, name: name),
          );
        }
      }
    }, onError: (_) {});
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      return await found.future.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null; // Bluetooth off or not allowed: RFCOMM reports the reason.
    } finally {
      await subscription.cancel();
      try {
        if (FlutterBluePlus.isScanningNow) await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }

  @override
  Future<void> write(List<int> data) async {
    final active = _active;
    if (active == null) throw const PrinterTransportException(PosPrintResult.printerNotConnected);
    await active.write(data);
  }

  @override
  Future<void> disconnect() async {
    final active = _active;
    _active = null;
    await active?.disconnect();
  }
}

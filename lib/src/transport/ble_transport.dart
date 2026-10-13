import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../enums.dart';
import '../models/ble_printer_service.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../utils/chunking.dart';
import 'printer_transport.dart';

/// BLE printers through flutter_blue_plus, on every platform including the web
/// (where flutter_blue_plus uses Web Bluetooth).
class BleTransport implements PrinterTransport {
  BleTransport(
    this._printer, {
    required this._license,
    required this._options,
    required this._services,
  });

  BluetoothPrinter _printer;
  final License _license;
  final BluetoothWriteOptions _options;
  final List<BlePrinterService> _services;

  BluetoothCharacteristic? _characteristic;
  bool _withoutResponse = false;
  int _chunkSize = minBleChunk;

  BluetoothDevice get _device => BluetoothDevice.fromId(_printer.id);

  @override
  BluetoothPrinter get printer => _printer;

  @override
  bool get isConnected => _characteristic != null && _device.isConnected;

  @override
  Future<void> connect(Duration timeout) async {
    if (isConnected) return;
    try {
      // On Android this also asks for a 512 byte MTU right after connecting.
      await _device.connect(license: _license, timeout: timeout);
    } catch (e) {
      throw PrinterTransportException(_connectFailure(e), e);
    }

    try {
      final services = await _device.discoverServices();
      final candidates = [
        for (final service in services)
          for (final c in service.characteristics)
            BleCharacteristicInfo(
              serviceUuid: c.serviceUuid.str128,
              characteristicUuid: c.characteristicUuid.str128,
              canWrite: c.properties.write,
              canWriteWithoutResponse: c.properties.writeWithoutResponse,
            ),
      ];
      final chosen = resolveWriteCharacteristic(
        candidates,
        preferred: _services,
        cachedService: _printer.serviceUuid,
        cachedCharacteristic: _printer.characteristicUuid,
      );
      if (chosen == null) {
        throw const PrinterTransportException(PosPrintResult.noWritableCharacteristic);
      }

      _characteristic = services
          .expand((s) => s.characteristics)
          .firstWhere(
            (c) =>
                normalizeUuid(c.serviceUuid.str128) == normalizeUuid(chosen.serviceUuid) &&
                normalizeUuid(c.characteristicUuid.str128) ==
                    normalizeUuid(chosen.characteristicUuid),
          );
      _withoutResponse =
          chosen.canWriteWithoutResponse &&
          (_options.preferWriteWithoutResponse || !chosen.canWrite);
      _chunkSize = _options.bleChunkSize ?? (kIsWeb ? minBleChunk : bleChunkForMtu(_device.mtuNow));
      _printer = _printer.copyWith(
        serviceUuid: chosen.serviceUuid,
        characteristicUuid: chosen.characteristicUuid,
      );
    } catch (e) {
      await disconnect();
      if (e is PrinterTransportException) rethrow;
      throw PrinterTransportException(PosPrintResult.connectionFailed, e);
    }
  }

  @override
  Future<void> write(List<int> data) async {
    final characteristic = _characteristic;
    if (characteristic == null || !_device.isConnected) {
      throw const PrinterTransportException(PosPrintResult.printerNotConnected);
    }

    var offset = 0;
    while (offset < data.length) {
      final end = offset + _chunkSize < data.length ? offset + _chunkSize : data.length;
      try {
        // flutter_blue_plus waits until each packet has left the radio, even
        // without response, so the operating system never drops data.
        await characteristic.write(data.sublist(offset, end), withoutResponse: _withoutResponse);
      } catch (e) {
        if (!_device.isConnected) {
          throw PrinterTransportException(PosPrintResult.printerNotConnected, e);
        }
        // A rejected write is usually too large for the link: retry the same
        // bytes smaller, unless the app fixed the size itself.
        if (_options.bleChunkSize == null && _chunkSize > minBleChunk) {
          _chunkSize = nextSmallerBleChunk(_chunkSize);
          continue;
        }
        throw PrinterTransportException(PosPrintResult.writeFailed, e);
      }
      offset = end;
      if (_options.bleChunkDelay > Duration.zero) {
        await Future<void>.delayed(_options.bleChunkDelay);
      }
    }
  }

  @override
  Future<void> disconnect() async {
    _characteristic = null;
    try {
      await _device.disconnect();
    } catch (_) {
      // Already disconnected, or the link dropped. Nothing left to release.
    }
  }

  PosPrintResult _connectFailure(Object error) {
    if (error is FlutterBluePlusException) {
      final code = error.code;
      if (error.platform == ErrorPlatform.fbp) {
        if (code == FbpErrorCode.timeout.index) return PosPrintResult.timeout;
        if (code == FbpErrorCode.adapterIsOff.index) return PosPrintResult.bluetoothUnavailable;
        if (code == FbpErrorCode.userRejected.index) return PosPrintResult.permissionDenied;
      }
    }
    final text = error.toString().toLowerCase();
    // flutter_blue_plus_web only knows devices chosen in this page session.
    if (kIsWeb && text.contains('could not be found')) return PosPrintResult.printerAccessRequired;
    if (text.contains('timeout') || text.contains('timed out')) return PosPrintResult.timeout;
    if (text.contains('permission')) return PosPrintResult.permissionDenied;
    return PosPrintResult.connectionFailed;
  }
}

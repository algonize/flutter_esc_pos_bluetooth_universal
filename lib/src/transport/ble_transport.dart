import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../enums.dart';
import '../models/ble_printer_service.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../utils/chunking.dart';
import 'printer_transport.dart';

/// The adapter state once it has settled, waiting up to [timeout].
///
/// Right after launch the state is `unknown` for a moment, and
/// flutter_blue_plus refuses to scan or connect until it is `on`, so a printer
/// reconnected at startup would otherwise fail at once. On the web the browser
/// handles this, so it returns `on` straight away.
Future<BluetoothAdapterState> settledAdapterState({
  Duration timeout = const Duration(seconds: 3),
}) async {
  if (kIsWeb) return BluetoothAdapterState.on;
  try {
    return await FlutterBluePlus.adapterState
        .where((s) => s != BluetoothAdapterState.unknown && s != BluetoothAdapterState.turningOn)
        .first
        .timeout(timeout);
  } catch (_) {
    return BluetoothAdapterState.unknown;
  }
}

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
  bool _canWriteWithResponse = false;
  int _chunkSize = minBleChunk;

  /// How long to let queued writes drain when the printer only accepts write
  /// without response, so there is no acknowledged write to wait on.
  static const _drainDelay = Duration(milliseconds: 500);

  BluetoothDevice get _device => BluetoothDevice.fromId(_printer.id);

  @override
  BluetoothPrinter get printer => _printer;

  @override
  bool get isConnected => _characteristic != null && _device.isConnected;

  @override
  Future<void> connect(Duration timeout) async {
    if (isConnected) return;
    switch (await settledAdapterState()) {
      case BluetoothAdapterState.unauthorized:
        throw const PrinterTransportException(PosPrintResult.permissionDenied);
      case BluetoothAdapterState.off || BluetoothAdapterState.unavailable:
        throw const PrinterTransportException(PosPrintResult.bluetoothUnavailable);
      default:
        break;
    }
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
      final ranked = rankWriteCharacteristics(
        candidates,
        preferred: _services,
        cachedService: _printer.serviceUuid,
        cachedCharacteristic: _printer.characteristicUuid,
      );
      if (ranked.isEmpty) {
        throw const PrinterTransportException(PosPrintResult.noWritableCharacteristic);
      }
      final chosen = await _confirmWriteCharacteristic(services, ranked);

      _characteristic = _characteristicFor(services, chosen);
      _withoutResponse =
          chosen.canWriteWithoutResponse &&
          (_options.preferWriteWithoutResponse || !chosen.canWrite);
      _canWriteWithResponse = chosen.canWrite;
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

    // A write without response only queues the bytes: the operating system
    // reports success before they leave the radio, and disconnecting right
    // after (as printTicket does) throws the queue away. On a Deli ES421 under
    // macOS the whole ticket was lost that way. So the last chunk goes with
    // response when the printer allows it: writes are handled in order, so its
    // acknowledgement means every chunk before it has arrived.
    final acknowledgeLast = _withoutResponse && _canWriteWithResponse;

    var offset = 0;
    while (offset < data.length) {
      final end = offset + _chunkSize < data.length ? offset + _chunkSize : data.length;
      final isLast = end == data.length;
      try {
        await characteristic.write(
          data.sublist(offset, end),
          withoutResponse: _withoutResponse && !(isLast && acknowledgeLast),
        );
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
    // Nothing was acknowledged: give the queue time to reach the printer.
    if (_withoutResponse && !acknowledgeLast) await Future<void>.delayed(_drainDelay);
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

  /// Real-time status request (DLE EOT 1). Prints nothing.
  static const _statusRequest = [0x10, 0x04, 0x01];

  /// How long to wait for the printer to answer a probe. Printers that answer
  /// do so within about 50 ms.
  static const _probeTimeout = Duration(milliseconds: 500);

  /// Printers often expose several known printer characteristics, and only
  /// some of them reach the print engine: the rest accept writes and drop
  /// them, so printing "succeeds" with nothing on paper. This sends a status
  /// request to each known candidate in turn and keeps the first one the
  /// printer answers on.
  ///
  /// Not every printer replies over BLE, so with no answer it keeps the first
  /// of [ranked]. Skipped when a saved pair is still present, or when there is
  /// only one known candidate to choose from.
  Future<BleCharacteristicInfo> _confirmWriteCharacteristic(
    List<BluetoothService> services,
    List<BleCharacteristicInfo> ranked,
  ) async {
    final first = ranked.first;
    final cachedService = _printer.serviceUuid;
    final cachedCharacteristic = _printer.characteristicUuid;
    final isCached =
        cachedService != null &&
        cachedCharacteristic != null &&
        normalizeUuid(first.serviceUuid) == normalizeUuid(cachedService) &&
        normalizeUuid(first.characteristicUuid) == normalizeUuid(cachedCharacteristic);
    final known = ranked
        .where((c) => isKnownPrinterCharacteristic(c, preferred: _services))
        .toList();
    if (isCached || known.length < 2) return first;

    // Listen on every known printer service: the answer can come on another
    // service than the one written to (the Deli ES421 answers 18F0 and FF00
    // writes on 18F0/FF03).
    final knownServices = {for (final s in _services) normalizeUuid(s.serviceUuid)};
    final enabled = <BluetoothCharacteristic>[];
    final subscriptions = <StreamSubscription<List<int>>>[];
    Completer<void>? answer;
    try {
      for (final c in services.expand((s) => s.characteristics)) {
        if (!knownServices.contains(normalizeUuid(c.serviceUuid.str128))) continue;
        if (!c.properties.notify && !c.properties.indicate) continue;
        try {
          if (await c.setNotifyValue(true, timeout: 3)) enabled.add(c);
        } catch (_) {
          // Some characteristics refuse; the others may still answer.
        }
      }
      if (enabled.isEmpty) return first;
      for (final c in enabled) {
        subscriptions.add(
          c.onValueReceived.listen((_) {
            final waiting = answer;
            if (waiting != null && !waiting.isCompleted) waiting.complete();
          }),
        );
      }

      for (final info in known) {
        final waiting = answer = Completer<void>();
        try {
          await _characteristicFor(
            services,
            info,
          ).write(_statusRequest, withoutResponse: !info.canWrite, timeout: 3);
          final answered = await waiting.future
              .then((_) => true)
              .timeout(_probeTimeout, onTimeout: () => false);
          if (answered) return info;
        } catch (_) {
          // A refused write means this is not the one; try the next.
        }
      }
      return first;
    } finally {
      answer = null;
      for (final s in subscriptions) {
        await s.cancel();
      }
      for (final c in enabled) {
        try {
          await c.setNotifyValue(false, timeout: 3);
        } catch (_) {}
      }
    }
  }

  BluetoothCharacteristic _characteristicFor(
    List<BluetoothService> services,
    BleCharacteristicInfo info,
  ) {
    return services
        .expand((s) => s.characteristics)
        .firstWhere(
          (c) =>
              normalizeUuid(c.serviceUuid.str128) == normalizeUuid(info.serviceUuid) &&
              normalizeUuid(c.characteristicUuid.str128) == normalizeUuid(info.characteristicUuid),
        );
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

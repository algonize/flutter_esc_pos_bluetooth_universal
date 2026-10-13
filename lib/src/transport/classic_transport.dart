import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../enums.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import 'printer_transport.dart';

/// Bluetooth Classic (SPP / RFCOMM) printers through flutter_classic_bluetooth.
/// Android, Windows, macOS and Linux. Native platforms only.
class ClassicTransport implements PrinterTransport {
  ClassicTransport(this._printer, {required this._options});

  final BluetoothPrinter _printer;
  final BluetoothWriteOptions _options;
  final FlutterClassicBluetooth _bluetooth = FlutterClassicBluetooth();

  BtcConnection? _connection;

  @override
  BluetoothPrinter get printer => _printer;

  @override
  bool get isConnected => _connection?.isConnected ?? false;

  @override
  Future<void> connect(Duration timeout) async {
    if (isConnected) return;
    try {
      // Retries only transient failures (asleep, out of range, busy), so an
      // unpaired printer fails fast with a clear reason.
      _connection = await _bluetooth.connectWithRetry(
        address: _printer.id,
        secure: _options.classicSecureConnection,
        timeout: timeout,
      );
    } on BtcTimeoutException catch (e) {
      throw PrinterTransportException(PosPrintResult.timeout, e);
    } on BtcPermissionException catch (e) {
      throw PrinterTransportException(PosPrintResult.permissionDenied, e);
    } on BtcDisabledException catch (e) {
      throw PrinterTransportException(PosPrintResult.bluetoothUnavailable, e);
    } on BtcUnsupportedException catch (e) {
      throw PrinterTransportException(PosPrintResult.unsupported, e);
    } on BtcConnectionException catch (e) {
      throw PrinterTransportException(switch (e.cause) {
        BtcConnectFailure.timeout => PosPrintResult.timeout,
        BtcConnectFailure.adapterOff => PosPrintResult.bluetoothUnavailable,
        BtcConnectFailure.permissionDenied => PosPrintResult.permissionDenied,
        _ => PosPrintResult.connectionFailed,
      }, e);
    } catch (e) {
      throw PrinterTransportException(PosPrintResult.connectionFailed, e);
    }
  }

  @override
  Future<void> write(List<int> data) async {
    final connection = _connection;
    if (connection == null || !connection.isConnected) {
      throw const PrinterTransportException(PosPrintResult.printerNotConnected);
    }
    try {
      final size = _options.classicChunkSize;
      for (var offset = 0; offset < data.length; offset += size) {
        final end = offset + size < data.length ? offset + size : data.length;
        await connection.output.add(Uint8List.fromList(data.sublist(offset, end)));
        if (_options.classicChunkDelay > Duration.zero) {
          await Future<void>.delayed(_options.classicChunkDelay);
        }
      }
      await connection.output.allSent;
    } catch (e) {
      throw PrinterTransportException(
        connection.isConnected ? PosPrintResult.writeFailed : PosPrintResult.printerNotConnected,
        e,
      );
    }
  }

  @override
  Future<void> disconnect() async {
    final connection = _connection;
    _connection = null;
    if (connection == null) return;
    try {
      // Waits for queued writes, so the end of the ticket is not cut off.
      await connection.finish();
    } catch (_) {
      // The link may already be gone.
    } finally {
      connection.dispose();
    }
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_classic_bluetooth/flutter_classic_bluetooth.dart';

import '../enums.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../utils/write_pacer.dart';
import 'printer_transport.dart';

/// Bluetooth Classic (SPP / RFCOMM) printers through flutter_classic_bluetooth.
/// Android, Windows, macOS and Linux. Native platforms only.
class ClassicTransport implements PrinterTransport {
  ClassicTransport(this._printer, {required this._options, this._pacer});

  final BluetoothPrinter _printer;
  final BluetoothWriteOptions _options;

  /// Keeps the data at the printer's print speed. RFCOMM has flow control,
  /// but most printers take the data before checking for room in their own
  /// buffer, which a long ticket sent at link speed overruns.
  final WritePacer? _pacer;
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
        // A retry fired while the first attempt is still finishing natively
        // tends to fail as busy, so allow one retry only. None on macOS, where
        // an RFCOMM open that stalls never completes, so a retry only doubles
        // the wait (see MacClassicTransport).
        maxAttempts: Platform.isMacOS ? 1 : 2,
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
        await _pacer?.waitFor(data, offset, end);
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

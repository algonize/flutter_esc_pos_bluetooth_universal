import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../enums.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import 'printer_transport.dart';
import 'web_serial_bindings.dart';

/// Bluetooth Classic printers in Chromium browsers, through Web Serial over
/// RFCOMM. Web only.
class WebSerialTransport implements PrinterTransport {
  WebSerialTransport(this._printer, this._port, {required this._options});

  final BluetoothPrinter _printer;

  /// The port granted to this page, or null when the page has to ask again.
  final SerialPort? _port;
  final BluetoothWriteOptions _options;
  bool _open = false;

  @override
  BluetoothPrinter get printer => _printer;

  @override
  bool get isConnected => _open;

  @override
  Future<void> connect(Duration timeout) async {
    if (_open) return;
    final port = _port;
    if (port == null) throw const PrinterTransportException(PosPrintResult.printerAccessRequired);
    try {
      await port.open(SerialOptions(baudRate: _options.webSerialBaudRate)).toDart.timeout(timeout);
      _open = true;
    } on TimeoutException catch (e) {
      throw PrinterTransportException(PosPrintResult.timeout, e);
    } catch (e) {
      // "InvalidStateError": the port is already open in this page.
      if (isDomError(e, 'InvalidStateError')) {
        _open = true;
        return;
      }
      throw PrinterTransportException(PosPrintResult.connectionFailed, e);
    }
  }

  @override
  Future<void> write(List<int> data) async {
    final writable = _port?.writable;
    if (!_open || writable == null) {
      throw const PrinterTransportException(PosPrintResult.printerNotConnected);
    }
    final writer = writable.getWriter();
    try {
      final size = _options.webSerialChunkSize;
      for (var offset = 0; offset < data.length; offset += size) {
        final end = offset + size < data.length ? offset + size : data.length;
        await writer.ready.toDart;
        await writer.write(Uint8List.fromList(data.sublist(offset, end)).toJS).toDart;
        if (_options.webSerialChunkDelay > Duration.zero) {
          await Future<void>.delayed(_options.webSerialChunkDelay);
        }
      }
      await writer.ready.toDart;
    } catch (e) {
      throw PrinterTransportException(PosPrintResult.writeFailed, e);
    } finally {
      writer.releaseLock();
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_open) return;
    _open = false;
    try {
      await _port?.close().toDart;
    } catch (_) {
      // Already closed, or the device went away.
    }
  }
}

/// Whether a browser error is the DOMException named [name], such as
/// "NotFoundError". Matched on the error text, which works the same whether the
/// app is compiled to JavaScript or WebAssembly.
bool isDomError(Object error, String name) => error.toString().contains(name);

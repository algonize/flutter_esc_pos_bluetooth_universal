import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import '../enums.dart';
import '../models/bluetooth_printer.dart';
import '../models/bluetooth_write_options.dart';
import '../utils/write_pacer.dart';
import 'printer_transport.dart';
import 'web_serial_bindings.dart';

/// Bluetooth Classic printers in Chromium browsers, through Web Serial over
/// RFCOMM. Web only.
class WebSerialTransport implements PrinterTransport {
  WebSerialTransport(this._printer, this._port, {required this._options, this._pacer});

  final BluetoothPrinter _printer;

  /// Keeps the data at the printer's print speed, so a long ticket does not
  /// overrun the printer's buffer (see `WritePacing`).
  final WritePacer? _pacer;

  /// The port granted to this page, or null when the page has to ask again.
  final SerialPort? _port;
  final BluetoothWriteOptions _options;
  bool _open = false;

  /// How long closing the port may take. Chrome only closes it once the
  /// writable stream has finished, so a stalled link could hold it forever.
  static const _closeTimeout = Duration(seconds: 5);

  /// Chrome's buffer between the page and the Bluetooth link. Chrome sends
  /// what the buffer holds as one burst and reads nothing more until the burst
  /// is done, so with the default of 255 bytes a widget receipt (8 to 100 KB)
  /// went out 255 bytes at a time, waiting on the link after each. A larger
  /// buffer lets each burst fill the link.
  static const webSerialBufferSize = 16 * 1024;

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
      await port
          .open(
            SerialOptions(baudRate: _options.webSerialBaudRate, bufferSize: webSerialBufferSize),
          )
          .toDart
          .timeout(timeout);
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
    // Each print gets a fresh stream: the previous one was closed to drain it.
    final writable = _port?.writable;
    if (!_open || writable == null) {
      throw const PrinterTransportException(PosPrintResult.printerNotConnected);
    }
    final writer = writable.getWriter();
    try {
      final size = _options.webSerialChunkSize;
      for (var offset = 0; offset < data.length; offset += size) {
        final end = offset + size < data.length ? offset + size : data.length;
        await _pacer?.waitFor(data, offset, end);
        await writer.ready.toDart;
        await writer.write(Uint8List.fromList(data.sublist(offset, end)).toJS).toDart;
        if (_options.webSerialChunkDelay > Duration.zero) {
          await Future<void>.delayed(_options.webSerialChunkDelay);
        }
      }
      // A write resolves once Chrome has buffered the bytes, not sent them,
      // and closing the port aborts the stream, which throws that buffer away
      // and drops the Bluetooth link at once. That is how a ticket "printed"
      // with nothing on paper. Closing the stream instead resolves only after
      // every byte has gone out over Bluetooth.
      await writer.close().toDart.timeout(drainTimeout(data.length));
    } on TimeoutException catch (e) {
      throw PrinterTransportException(PosPrintResult.timeout, e);
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
      await _port?.close().toDart.timeout(_closeTimeout);
    } catch (_) {
      // Already closed, the device went away, or the link stalled.
    }
  }
}

/// How long sending [bytes] may take before the link is considered stalled.
/// Printers hold data back while they print, so this allows for slow ones:
/// 10 seconds plus a millisecond per byte.
Duration drainTimeout(int bytes) => Duration(seconds: 10, milliseconds: bytes);

/// Whether a browser error is the DOMException named [name], such as
/// "NotFoundError". Matched on the error text, which works the same whether the
/// app is compiled to JavaScript or WebAssembly.
bool isDomError(Object error, String name) => error.toString().contains(name);

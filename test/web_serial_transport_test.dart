@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/transport/web_serial_bindings.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/transport/web_serial_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// A serial port that behaves like Chrome's Bluetooth serial ports:
/// - a write resolves once the bytes are buffered, and the "radio" sends them
///   a little at a time;
/// - closing the writable stream waits until everything is sent (Drain);
/// - closing the port aborts the stream, which throws the buffer away
///   (Flush(kTransmit)), then drops the link.
const _fakePort = r'''
(() => {
  const port = { sent: [], pipe: [], stream: null, opened: false, closing: false };
  const radio = setInterval(() => {
    port.sent.push(...port.pipe.splice(0, 64));
    if (port.pipe.length === 0 && port.onDrained) {
      const drained = port.onDrained;
      port.onDrained = null;
      drained();
    }
  }, 2);
  port.open = async (options) => { port.opened = true; port.bufferSize = options.bufferSize; };
  Object.defineProperty(port, 'writable', {
    get() {
      if (!port.opened || port.closing) return null;
      if (port.stream) return port.stream;
      port.stream = new WritableStream({
        write(chunk) { port.pipe.push(...chunk); },
        close() {
          return new Promise((resolve) => {
            const done = () => { port.stream = null; resolve(); };
            if (port.pipe.length === 0) done(); else port.onDrained = done;
          });
        },
        abort() { port.pipe.length = 0; port.stream = null; },
      });
      return port.stream;
    },
  });
  port.close = async () => {
    port.closing = true;
    if (port.stream) await port.stream.abort();
    port.pipe.length = 0;
    clearInterval(radio);
    port.opened = false;
  };
  port.getInfo = () => ({});
  return port;
})()
''';

@JS('eval')
external JSAny? _eval(String code);

SerialPort _newPort() => _eval(_fakePort) as SerialPort;

List<int> _sent(SerialPort port) => [
  for (final b in (port as JSObject).getProperty<JSArray<JSNumber>>('sent'.toJS).toDart)
    b.toDartInt,
];

WebSerialTransport _transport(SerialPort port) => WebSerialTransport(
  const BluetoothPrinter(id: 'webserial:1', type: BluetoothPrinterType.classic),
  port,
  options: const BluetoothWriteOptions(),
);

List<int> _ticket(int length, [int seed = 0]) =>
    List<int>.generate(length, (i) => (i + seed) % 256);

void main() {
  test('the fake loses unsent bytes when the port is closed straight away', () async {
    // What the transport used to do, and why tickets came out blank.
    final port = _newPort();
    await port.open(SerialOptions(baudRate: 9600)).toDart;
    final writer = port.writable!.getWriter();
    await writer.write(Uint8List.fromList(_ticket(3000)).toJS).toDart;
    writer.releaseLock();
    await port.close().toDart;
    expect(_sent(port).length, lessThan(3000));
  });

  test('sends every byte before the port closes', () async {
    final port = _newPort();
    final transport = _transport(port);
    final ticket = _ticket(3000);
    await transport.connect(const Duration(seconds: 5));
    await transport.write(ticket);
    await transport.disconnect();
    expect(_sent(port), ticket);
  });

  test('opens the port with a buffer far above the 255 byte default', () async {
    // Chrome sends one buffer at a time, waiting on the link after each.
    final port = _newPort();
    final transport = _transport(port);
    await transport.connect(const Duration(seconds: 5));
    final bufferSize = (port as JSObject).getProperty<JSNumber>('bufferSize'.toJS).toDartInt;
    await transport.disconnect();
    expect(bufferSize, WebSerialTransport.webSerialBufferSize);
    expect(bufferSize, greaterThanOrEqualTo(16 * 1024));
  });

  test('prints again on a port kept open', () async {
    final port = _newPort();
    final transport = _transport(port);
    final first = _ticket(1500);
    final second = _ticket(700, 7);
    await transport.connect(const Duration(seconds: 5));
    await transport.write(first);
    await transport.write(second);
    await transport.disconnect();
    expect(_sent(port), [...first, ...second]);
  });
}

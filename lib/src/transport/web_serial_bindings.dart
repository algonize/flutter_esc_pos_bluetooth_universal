// Minimal Web Serial API bindings (https://wicg.github.io/serial/).
// package:web does not ship them, and only this small part is needed: request
// and list ports, open, write, close. Web only.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// The Serial Port Profile service class. Chrome lists paired Bluetooth Classic
/// devices that offer it as serial ports (desktop Chrome 117+).
const String sppServiceClassId = '00001101-0000-1000-8000-00805f9b34fb';

/// `navigator.serial`, or null when the browser has no Web Serial.
Serial? get navigatorSerial {
  final navigator = web.window.navigator as JSObject;
  if (!navigator.has('serial')) return null;
  return navigator.getProperty<JSObject?>('serial'.toJS) as Serial?;
}

extension type Serial._(JSObject _) implements JSObject {
  external JSPromise<SerialPort> requestPort([SerialPortRequestOptions options]);
  external JSPromise<JSArray<SerialPort>> getPorts();
}

extension type SerialPortRequestOptions._(JSObject _) implements JSObject {
  external factory SerialPortRequestOptions({
    JSArray<SerialPortFilter> filters,
    JSArray<JSString> allowedBluetoothServiceClassIds,
  });
}

extension type SerialPortFilter._(JSObject _) implements JSObject {
  external factory SerialPortFilter({String bluetoothServiceClassId});
}

extension type SerialOptions._(JSObject _) implements JSObject {
  external factory SerialOptions({int baudRate});
}

extension type SerialPortInfo._(JSObject _) implements JSObject {
  external String? get bluetoothServiceClassId;
  external int? get usbVendorId;
}

extension type SerialPort._(JSObject _) implements JSObject {
  external JSPromise<JSAny?> open(SerialOptions options);
  external JSPromise<JSAny?> close();
  external web.WritableStream? get writable;
  external SerialPortInfo getInfo();
}

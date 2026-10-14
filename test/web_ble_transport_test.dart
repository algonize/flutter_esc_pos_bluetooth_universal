@TestOn('browser')
library;

import 'dart:async';

import 'package:flutter_blue_plus_platform_interface/flutter_blue_plus_platform_interface.dart';
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/transport/ble_transport.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/transport/printer_transport.dart';
import 'package:flutter_test/flutter_test.dart';

const _id = 'printer';
final _service = Guid('000018f0-0000-1000-8000-00805f9b34fb');
final _characteristic = Guid('00002af1-0000-1000-8000-00805f9b34fb');

/// One write as the printer saw it.
typedef _Write = ({bool withResponse, List<int> value});

// Shared by every fake: flutter_blue_plus subscribes to them once per run.
final _connection = StreamController<BmConnectionStateResponse>.broadcast();
final _services = StreamController<BmDiscoverServicesResult>.broadcast();
final _written = StreamController<BmCharacteristicData>.broadcast();

/// Stands in for flutter_blue_plus_web, with a printer that has a single
/// 18F0/2AF1 characteristic, which always takes write without response. Like
/// Chrome it rejects a write with response the link can't carry, and fails
/// writes once the link has dropped.
final class _FakeWebBluetooth extends FlutterBluePlusPlatform {
  _FakeWebBluetooth({this.canWrite = true, this.longestWrite = 512});

  final bool canWrite;

  /// The longest write with response the printer accepts.
  final int longestWrite;

  /// Set to drop the link silently, as a printer going to sleep does.
  bool linkDropped = false;

  /// Writes the printer accepted, in order.
  final writes = <_Write>[];
  int rejected = 0;

  List<int> get received => [for (final w in writes) ...w.value];

  @override
  Stream<BmConnectionStateResponse> get onConnectionStateChanged => _connection.stream;

  @override
  Stream<BmDiscoverServicesResult> get onDiscoveredServices => _services.stream;

  @override
  Stream<BmCharacteristicData> get onCharacteristicWritten => _written.stream;

  @override
  Future<bool> isSupported(BmIsSupportedRequest request) async => true;

  @override
  Future<BmBluetoothAdapterState> getAdapterState(BmBluetoothAdapterStateRequest request) async =>
      BmBluetoothAdapterState(adapterState: BmAdapterStateEnum.on);

  @override
  Future<bool> connect(BmConnectRequest request) async {
    _connection.add(_state(BmConnectionStateEnum.connected));
    return true;
  }

  @override
  Future<bool> disconnect(BmDisconnectRequest request) async {
    _connection.add(_state(BmConnectionStateEnum.disconnected));
    return true;
  }

  @override
  Future<bool> discoverServices(BmDiscoverServicesRequest request) async {
    _services.add(
      BmDiscoverServicesResult(
        remoteId: request.remoteId,
        services: [
          BmBluetoothService(
            remoteId: request.remoteId,
            primaryServiceUuid: null,
            serviceUuid: _service,
            characteristics: [
              BmBluetoothCharacteristic(
                remoteId: request.remoteId,
                primaryServiceUuid: null,
                serviceUuid: _service,
                characteristicUuid: _characteristic,
                instanceId: 0,
                descriptors: const [],
                properties: BmCharacteristicProperties(
                  broadcast: false,
                  read: false,
                  writeWithoutResponse: true,
                  write: canWrite,
                  notify: false,
                  indicate: false,
                  authenticatedSignedWrites: false,
                  extendedProperties: false,
                  notifyEncryptionRequired: false,
                  indicateEncryptionRequired: false,
                ),
              ),
            ],
          ),
        ],
        success: true,
        errorCode: 0,
        errorString: '',
      ),
    );
    return true;
  }

  @override
  Future<bool> writeCharacteristic(BmWriteCharacteristicRequest request) async {
    final withResponse = request.writeType == BmWriteType.withResponse;
    String? error;
    if (linkDropped) {
      error = 'NetworkError: GATT Server is disconnected. Cannot perform GATT operations.';
    } else if (withResponse && request.value.length > longestWrite) {
      error = 'NotSupportedError: GATT Error: Not supported.';
    }
    if (error == null) {
      writes.add((withResponse: withResponse, value: request.value));
    } else {
      rejected++;
    }
    _written.add(
      BmCharacteristicData(
        remoteId: request.remoteId,
        primaryServiceUuid: null,
        serviceUuid: request.serviceUuid,
        characteristicUuid: request.characteristicUuid,
        instanceId: request.instanceId,
        value: request.value,
        success: error == null,
        errorCode: 0,
        errorString: error ?? '',
      ),
    );
    return error == null;
  }

  BmConnectionStateResponse _state(BmConnectionStateEnum state) => BmConnectionStateResponse(
    remoteId: const DeviceIdentifier(_id),
    connectionState: state,
    disconnectReasonCode: null,
    disconnectReasonString: null,
  );
}

Future<BleTransport> _connected(_FakeWebBluetooth fake) async {
  FlutterBluePlusPlatform.instance = fake;
  final transport = BleTransport(
    const BluetoothPrinter(id: _id, type: BluetoothPrinterType.ble),
    license: License.nonprofit,
    options: const BluetoothWriteOptions(),
    services: defaultBlePrinterServices,
  );
  await transport.connect(const Duration(seconds: 5));
  return transport;
}

List<int> _ticket(int length) => List<int>.generate(length, (i) => i % 256);

void main() {
  test('every chunk is confirmed by the printer, even when it allows no-response writes', () async {
    final fake = _FakeWebBluetooth();
    final transport = await _connected(fake);
    final ticket = _ticket(1000);
    await transport.write(ticket);
    await transport.disconnect();

    expect(fake.writes.every((w) => w.withResponse), isTrue);
    expect(fake.writes.first.value.length, 182);
    expect(fake.received, ticket);
  });

  test('a write too long for the link steps down and resends the same bytes', () async {
    final fake = _FakeWebBluetooth(longestWrite: 100);
    final transport = await _connected(fake);
    final ticket = _ticket(1000);
    await transport.write(ticket);
    await transport.disconnect();

    expect(fake.rejected, 2); // 182, then 128
    expect(fake.writes.every((w) => w.value.length <= 100), isTrue);
    expect(fake.received, ticket);
  });

  test('paces a printer that only takes write without response, 20 bytes at a time', () async {
    final fake = _FakeWebBluetooth(canWrite: false);
    final transport = await _connected(fake);
    final ticket = _ticket(100);
    final watch = Stopwatch()..start();
    await transport.write(ticket);
    watch.stop();
    await transport.disconnect();

    expect(fake.writes.every((w) => !w.withResponse && w.value.length == 20), isTrue);
    expect(fake.received, ticket);
    // Four 20 ms pauses between five chunks, then the 500 ms drain.
    expect(watch.elapsedMilliseconds, greaterThanOrEqualTo(4 * 20 + 500));
  });

  test('a link the printer dropped is reported as such, not retried smaller', () async {
    final fake = _FakeWebBluetooth();
    final transport = await _connected(fake);
    fake.linkDropped = true;

    await expectLater(
      transport.write(_ticket(500)),
      throwsA(
        isA<PrinterTransportException>().having(
          (e) => e.result,
          'result',
          PosPrintResult.printerNotConnected,
        ),
      ),
    );
    expect(fake.rejected, 1);
    await transport.disconnect();
  });
}

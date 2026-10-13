import 'dart:typed_data';

import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/models/ble_printer_service.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/raster/widget_raster.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/utils/chunking.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

BleCharacteristicInfo _c(
  String service,
  String characteristic, {
  bool write = false,
  bool noResponse = false,
}) => BleCharacteristicInfo(
  serviceUuid: service,
  characteristicUuid: characteristic,
  canWrite: write,
  canWriteWithoutResponse: noResponse,
);

void main() {
  group('normalizeUuid', () {
    test('expands 16 and 32 bit forms and lowercases', () {
      expect(normalizeUuid('FF02'), '0000ff02-0000-1000-8000-00805f9b34fb');
      expect(normalizeUuid('000018F0'), '000018f0-0000-1000-8000-00805f9b34fb');
      expect(
        normalizeUuid(' 49535343-FE7D-4AE5-8FA9-9FAFD205E455 '),
        '49535343-fe7d-4ae5-8fa9-9fafd205e455',
      );
    });
  });

  group('resolveWriteCharacteristic', () {
    final issc = _c(
      '49535343-fe7d-4ae5-8fa9-9fafd205e455',
      '49535343-8841-43f4-a8d4-ecbe34729bb3',
      write: true,
      noResponse: true,
    );
    final custom = _c(
      '0000abcd-0000-1000-8000-00805f9b34fb',
      '0000abce-0000-1000-8000-00805f9b34fb',
      noResponse: true,
    );
    final deviceName = _c('1800', '2a00', write: true);

    test('returns null when nothing is writable', () {
      expect(resolveWriteCharacteristic([_c('ff00', 'ff01')]), isNull);
    });

    test('prefers a known printer service over other writable ones', () {
      expect(resolveWriteCharacteristic([custom, issc]), issc);
    });

    test('prefers the cached pair over everything else', () {
      expect(
        resolveWriteCharacteristic(
          [issc, custom],
          cachedService: custom.serviceUuid,
          cachedCharacteristic: custom.characteristicUuid,
        ),
        custom,
      );
    });

    test('falls back to a custom writable characteristic, skipping standard services', () {
      expect(resolveWriteCharacteristic([deviceName, custom]), custom);
      expect(resolveWriteCharacteristic([deviceName]), isNull);
    });

    test('matches 16-bit UUIDs against the known table', () {
      final ff02 = _c('ff00', 'ff02', write: true);
      expect(resolveWriteCharacteristic([custom, ff02]), ff02);
    });

    test('ranks printer services before the module UART (Deli ES421 layout)', () {
      // The ES421 exposes all four known pairs; only 18F0 and FF00 reach the printer.
      final s18f0 = _c('18f0', '2af1', write: true, noResponse: true);
      final ff02 = _c('ff00', 'ff02', write: true, noResponse: true);
      final e781 = _c(
        'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
        'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
        write: true,
        noResponse: true,
      );
      expect(rankWriteCharacteristics([issc, custom, e781, ff02, s18f0, deviceName]), [
        s18f0,
        ff02,
        e781,
        issc,
        custom,
      ]);
      expect(resolveWriteCharacteristic([issc, s18f0]), s18f0);
    });

    test('ranks the cached pair first without repeating it', () {
      final ranked = rankWriteCharacteristics(
        [custom, issc],
        cachedService: issc.serviceUuid,
        cachedCharacteristic: issc.characteristicUuid,
      );
      expect(ranked, [issc, custom]);
    });

    test('tells known printer characteristics from fallback ones', () {
      expect(isKnownPrinterCharacteristic(issc), isTrue);
      expect(isKnownPrinterCharacteristic(_c('ff00', 'ff02', write: true)), isTrue);
      expect(isKnownPrinterCharacteristic(custom), isFalse);
    });
  });

  group('chunking', () {
    test('splits into slices of at most the given size', () {
      final data = List<int>.generate(10, (i) => i);
      expect(chunked(data, 4).toList(), [
        [0, 1, 2, 3],
        [4, 5, 6, 7],
        [8, 9],
      ]);
      expect(chunked(const [], 4), isEmpty);
    });

    test('steps BLE chunks down to 20 bytes', () {
      expect(nextSmallerBleChunk(512), 244);
      expect(nextSmallerBleChunk(150), 128);
      expect(nextSmallerBleChunk(20), 20);
    });

    test('derives the chunk from the MTU', () {
      expect(bleChunkForMtu(23), 20);
      expect(bleChunkForMtu(185), 182);
      expect(bleChunkForMtu(517), 512);
    });
  });

  group('BluetoothPrinter', () {
    const printer = BluetoothPrinter(
      id: 'AA:BB:CC:DD:EE:FF',
      type: BluetoothPrinterType.ble,
      name: 'MTP-II',
      rssi: -60,
      serviceUuid: '49535343-fe7d-4ae5-8fa9-9fafd205e455',
      characteristicUuid: '49535343-8841-43f4-a8d4-ecbe34729bb3',
    );

    test('round-trips through JSON, without the RSSI', () {
      final restored = BluetoothPrinter.fromJson(printer.toJson());
      expect(restored, printer);
      expect(restored.name, 'MTP-II');
      expect(restored.serviceUuid, printer.serviceUuid);
      expect(restored.characteristicUuid, printer.characteristicUuid);
      expect(restored.rssi, isNull);
    });

    test('is equal by type and case-insensitive id', () {
      expect(
        printer,
        const BluetoothPrinter(id: 'aa:bb:cc:dd:ee:ff', type: BluetoothPrinterType.ble),
      );
      expect(
        printer ==
            const BluetoothPrinter(id: 'AA:BB:CC:DD:EE:FF', type: BluetoothPrinterType.classic),
        isFalse,
      );
    });

    test('falls back to the id for the display name', () {
      expect(
        const BluetoothPrinter(id: 'X', type: BluetoothPrinterType.classic, name: ' ').displayName,
        'X',
      );
    });
  });

  group('enums', () {
    test('page sizes map to print-head widths', () {
      expect(ThermalPosPrinterPageSize.size58mm.widthPx, 384);
      expect(ThermalPosPrinterPageSize.size80mm.widthPx, 576);
      expect('58mm'.toThermalPosPrinterPageSize, ThermalPosPrinterPageSize.size58mm);
      expect('nonsense'.toThermalPosPrinterPageSize, ThermalPosPrinterPageSize.size80mm);
    });

    test('results carry a message', () {
      expect(PosPrintResult.success.isSuccess, isTrue);
      expect(PosPrintResult.writeFailed.msg, isNotEmpty);
    });
  });

  test('encodes a widget image into ESC/POS image bands plus feed and cut', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final profile = await CapabilityProfile.load();
    // A 700px wide image must be scaled down to the 576 dot print head.
    final image = img.Image(width: 700, height: 40)..clear(img.ColorRgb8(255, 255, 255));
    final png = Uint8List.fromList(img.encodePng(image));
    final bytes = encodeTicketImage((png, ThermalPosPrinterPageSize.size80mm, profile));
    expect(bytes, isNotEmpty);
    bool contains(List<int> pattern) {
      for (var i = 0; i + pattern.length <= bytes.length; i++) {
        var match = true;
        for (var j = 0; j < pattern.length; j++) {
          if (bytes[i + j] != pattern[j]) {
            match = false;
            break;
          }
        }
        if (match) return true;
      }
      return false;
    }

    // ESC * bit-image bands, the same output as flutter_esc_pos_network_universal.
    expect(contains([0x1B, 0x2A]), isTrue, reason: 'ESC * image data');
    // Ends with a paper cut (GS V).
    final tail = bytes.sublist(bytes.length - 6);
    expect(tail.contains(0x1D) && tail.contains(0x56), isTrue, reason: 'GS V cut at the end');
  });
}

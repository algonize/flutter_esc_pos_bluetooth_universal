import 'package:flutter/foundation.dart';

/// A BLE service and the characteristic a printer accepts print data on.
///
/// There is no standard BLE printing service, so each printer vendor picks its
/// own UUIDs. The package tries [defaultBlePrinterServices] first, then falls
/// back to any writable characteristic (see [resolveWriteCharacteristic]).
/// Add your printer's pair to the list you pass to the manager if it needs one.
@immutable
class BlePrinterService {
  const BlePrinterService(this.serviceUuid, this.writeCharacteristicUuid, {this.label});

  final String serviceUuid;
  final String writeCharacteristicUuid;

  /// Where this pair is commonly seen. For logs and docs only.
  final String? label;
}

/// UUID pairs used by common ESC/POS BLE printers and dual-mode modules.
///
/// Many printers expose several of these, and not all of them are wired to the
/// print engine: on the Deli ES421, for one, the ISSC pair accepts writes and
/// drops them, while 18F0 and FF00 reach the printer. The printer-specific services
/// therefore come first, the Bluetooth module's generic UART last, and the
/// transport confirms which one the printer answers on (see
/// [rankWriteCharacteristics]).
///
/// On the web these services must be listed when the device is requested, or
/// the browser hides them, so this list is also passed as `optionalServices`.
const List<BlePrinterService> defaultBlePrinterServices = [
  BlePrinterService(
    '000018f0-0000-1000-8000-00805f9b34fb',
    '00002af1-0000-1000-8000-00805f9b34fb',
    label: '18F0 printer service (many mini and POS printers)',
  ),
  BlePrinterService(
    '0000ff00-0000-1000-8000-00805f9b34fb',
    '0000ff02-0000-1000-8000-00805f9b34fb',
    label: 'FF00 printer service (older firmware)',
  ),
  BlePrinterService(
    'e7810a71-73ae-499d-8c15-faa9aef0c3f2',
    'bef8d6c9-9c21-4c9e-b632-bd58c1009f9f',
    label: 'E7810A71 printer service',
  ),
  BlePrinterService(
    '49535343-fe7d-4ae5-8fa9-9fafd205e455',
    '49535343-8841-43f4-a8d4-ecbe34729bb3',
    label: 'ISSC/Microchip transparent UART (many dual-mode printers)',
  ),
];

/// A writable characteristic found on a connected device. Kept free of any
/// Bluetooth plugin types so the selection logic can be unit tested.
@immutable
class BleCharacteristicInfo {
  const BleCharacteristicInfo({
    required this.serviceUuid,
    required this.characteristicUuid,
    required this.canWrite,
    required this.canWriteWithoutResponse,
  });

  final String serviceUuid;
  final String characteristicUuid;
  final bool canWrite;
  final bool canWriteWithoutResponse;

  bool get isWritable => canWrite || canWriteWithoutResponse;

  @override
  String toString() =>
      'BleCharacteristicInfo($serviceUuid / $characteristicUuid, '
      'write: $canWrite, writeWithoutResponse: $canWriteWithoutResponse)';
}

/// Standard GATT services that never carry print data, skipped by the fallback.
const _standardServices = {
  '00001800-0000-1000-8000-00805f9b34fb', // Generic Access
  '00001801-0000-1000-8000-00805f9b34fb', // Generic Attribute
  '0000180a-0000-1000-8000-00805f9b34fb', // Device Information
  '0000180f-0000-1000-8000-00805f9b34fb', // Battery
};

/// Lower-case 128-bit form of a UUID. Accepts 16-bit (`ff02`) and 32-bit forms.
String normalizeUuid(String uuid) {
  final value = uuid.trim().toLowerCase();
  if (value.length == 4) return '0000$value-0000-1000-8000-00805f9b34fb';
  if (value.length == 8) return '$value-0000-1000-8000-00805f9b34fb';
  return value;
}

/// Every characteristic print data could be sent to, most likely first:
/// 1. the pair saved from a previous connection ([cachedService] and
///    [cachedCharacteristic]),
/// 2. matches from [preferred], in its order,
/// 3. other characteristics that support write without response, outside the
///    standard GATT services,
/// 4. other characteristics that support write, outside the standard services.
///
/// Empty when the device has nothing writable.
List<BleCharacteristicInfo> rankWriteCharacteristics(
  List<BleCharacteristicInfo> available, {
  List<BlePrinterService> preferred = defaultBlePrinterServices,
  String? cachedService,
  String? cachedCharacteristic,
}) {
  final writable = available.where((c) => c.isWritable).toList();
  final ranked = <BleCharacteristicInfo>[];
  void add(BleCharacteristicInfo? info) {
    if (info != null && !ranked.contains(info)) ranked.add(info);
  }

  if (cachedService != null && cachedCharacteristic != null) {
    add(_find(writable, cachedService, cachedCharacteristic));
  }
  for (final known in preferred) {
    add(_find(writable, known.serviceUuid, known.writeCharacteristicUuid));
  }

  final custom = writable.where((c) => !_standardServices.contains(normalizeUuid(c.serviceUuid)));
  custom.where((c) => c.canWriteWithoutResponse).forEach(add);
  custom.forEach(add);
  return ranked;
}

/// The first of [rankWriteCharacteristics], or null when nothing is writable.
BleCharacteristicInfo? resolveWriteCharacteristic(
  List<BleCharacteristicInfo> available, {
  List<BlePrinterService> preferred = defaultBlePrinterServices,
  String? cachedService,
  String? cachedCharacteristic,
}) {
  return rankWriteCharacteristics(
    available,
    preferred: preferred,
    cachedService: cachedService,
    cachedCharacteristic: cachedCharacteristic,
  ).firstOrNull;
}

/// Whether [info] is one of the [preferred] printer characteristics, as
/// opposed to an unknown writable one found by the fallback.
bool isKnownPrinterCharacteristic(
  BleCharacteristicInfo info, {
  List<BlePrinterService> preferred = defaultBlePrinterServices,
}) {
  return preferred.any(
    (known) => _find([info], known.serviceUuid, known.writeCharacteristicUuid) != null,
  );
}

BleCharacteristicInfo? _find(
  List<BleCharacteristicInfo> candidates,
  String service,
  String characteristic,
) {
  final s = normalizeUuid(service);
  final c = normalizeUuid(characteristic);
  for (final info in candidates) {
    if (normalizeUuid(info.serviceUuid) == s && normalizeUuid(info.characteristicUuid) == c) {
      return info;
    }
  }
  return null;
}

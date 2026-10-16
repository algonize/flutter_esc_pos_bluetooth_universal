import 'package:flutter/foundation.dart';

import '../enums.dart';

/// A Bluetooth printer found by a scan, the paired list or a browser chooser.
///
/// It is plain data, so it can be saved (see [toJson]) and used again later to
/// reconnect without scanning.
@immutable
class BluetoothPrinter {
  const BluetoothPrinter({
    required this.id,
    required this.type,
    this.name,
    this.rssi,
    this.isPaired = false,
    this.serviceUuid,
    this.characteristicUuid,
  });

  /// Platform identifier of the device:
  /// - Android, Windows, Linux: the MAC address.
  /// - iOS, macOS (BLE): the CoreBluetooth identifier.
  /// - Web: the Web Bluetooth device id, or `webserial:<n>` for Web Serial ports.
  final String id;

  final BluetoothPrinterType type;

  /// Advertised or paired name. Can be null for devices that don't share one.
  final String? name;

  /// Signal strength in dBm at discovery time. Not saved by [toJson].
  final int? rssi;

  /// Whether the device is paired with the operating system (Classic).
  final bool isPaired;

  /// BLE only: the service that carries the printer's write characteristic.
  /// Filled in after the first successful connection and reused afterwards.
  final String? serviceUuid;

  /// BLE only: the characteristic the print data is written to.
  final String? characteristicUuid;

  bool get isBle => type == BluetoothPrinterType.ble;
  bool get isClassic => type == BluetoothPrinterType.classic;

  /// [name] when available, otherwise [id].
  String get displayName {
    final trimmed = name?.trim();
    return trimmed == null || trimmed.isEmpty ? id : trimmed;
  }

  BluetoothPrinter copyWith({
    String? name,
    int? rssi,
    bool? isPaired,
    String? serviceUuid,
    String? characteristicUuid,
  }) {
    return BluetoothPrinter(
      id: id,
      type: type,
      name: name ?? this.name,
      rssi: rssi ?? this.rssi,
      isPaired: isPaired ?? this.isPaired,
      serviceUuid: serviceUuid ?? this.serviceUuid,
      characteristicUuid: characteristicUuid ?? this.characteristicUuid,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    if (name != null) 'name': name,
    'isPaired': isPaired,
    if (serviceUuid != null) 'serviceUuid': serviceUuid,
    if (characteristicUuid != null) 'characteristicUuid': characteristicUuid,
  };

  /// Reads what [toJson] wrote. Keys it does not know, such as those saved by
  /// earlier versions, are ignored.
  factory BluetoothPrinter.fromJson(Map<String, dynamic> json) {
    return BluetoothPrinter(
      id: json['id'] as String,
      type: BluetoothPrinterType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => BluetoothPrinterType.ble,
      ),
      name: json['name'] as String?,
      isPaired: json['isPaired'] as bool? ?? false,
      serviceUuid: json['serviceUuid'] as String?,
      characteristicUuid: json['characteristicUuid'] as String?,
    );
  }

  /// Two printers are the same device when their [type] and [id] match.
  /// Ids are compared case-insensitively, as MAC addresses differ in case
  /// between platforms.
  @override
  bool operator ==(Object other) =>
      other is BluetoothPrinter && other.type == type && other.id.toLowerCase() == id.toLowerCase();

  @override
  int get hashCode => Object.hash(type, id.toLowerCase());

  @override
  String toString() => 'BluetoothPrinter(${type.name}, $displayName, $id)';
}

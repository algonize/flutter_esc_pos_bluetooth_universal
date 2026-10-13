import 'package:flutter/material.dart';
import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

import 'enums.dart';

/// The printing surface shared with `flutter_esc_pos_network_universal`'s
/// `BasePrinterNetworkManager`, so apps can drive Wi-Fi and Bluetooth printers
/// through the same code.
abstract class BasePrinterBluetoothManager {
  bool get isConnected;
  ThermalPosPrinterPageSize get paperSize;
  CapabilityProfile? get profile;

  Future<PosPrintResult> connect({Duration? timeout});
  Future<PosPrintResult> disconnect({Duration? timeout});
  Future<PosPrintResult> printTicket(List<int> data, {bool isDisconnect = true});
  Future<PosPrintResult> printWidget(
    BuildContext context, {
    required Widget child,
    bool isDisconnect = true,
  });
}

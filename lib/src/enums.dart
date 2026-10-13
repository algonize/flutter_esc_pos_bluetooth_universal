import 'package:flutter_esc_pos_utils/flutter_esc_pos_utils.dart';

/// The outcome of a printer operation.
///
/// The shared values ([success], [timeout], [ticketEmpty], [printInProgress],
/// [scanInProgress], [disconnectError], [unknown]) match
/// `flutter_esc_pos_network_universal`, so apps can handle both packages alike.
enum PosPrintResult {
  success('Success'),
  timeout('Error. Printer connection timeout'),
  printerNotSelected('Error. No printer selected'),
  printerNotConnected('Error. Printer not connected'),
  ticketEmpty('Error. Ticket is empty'),
  printInProgress('Error. Another print in progress'),
  scanInProgress('Error. Printer scanning in progress'),
  connectionFailed('Error. Could not connect to the printer'),
  writeFailed('Error. Failed to send data to the printer'),
  disconnectError('Error. Failed to disconnect'),
  bluetoothUnavailable('Error. Bluetooth is off or not available'),
  permissionDenied('Error. Bluetooth permission denied'),
  unsupported('Error. This printer type is not supported on this platform'),
  userCancelled('Cancelled. No printer was chosen'),
  printerAccessRequired('Error. Choose the printer again to give this page access'),
  noWritableCharacteristic('Error. No writable printer service found on this device'),
  unknown('Unknown error');

  const PosPrintResult(this.msg);

  /// A short, human-readable description of the result.
  final String msg;

  bool get isSuccess => this == PosPrintResult.success;
}

/// How a printer talks Bluetooth.
enum BluetoothPrinterType {
  /// Bluetooth Low Energy (GATT). Works on every platform, including iOS and web.
  ble,

  /// Bluetooth Classic, Serial Port Profile (RFCOMM). Most 58/80 mm POS printers.
  /// Android, Windows, macOS, Linux, and Chromium browsers through Web Serial.
  classic,
}

/// Connection lifecycle of the selected printer.
enum BluetoothConnectionStatus { disconnected, connecting, connected, disconnecting }

/// Whether Bluetooth can be used right now.
enum BluetoothAvailability {
  /// Ready to scan and connect.
  available,

  /// The adapter exists but is switched off.
  poweredOff,

  /// The app or page is not allowed to use Bluetooth.
  unauthorized,

  /// No Bluetooth on this device, or the browser has no Bluetooth APIs.
  unsupported,

  /// The state could not be determined yet.
  unknown,
}

/// Thermal paper widths.
enum ThermalPosPrinterPageSize {
  size58mm('58mm'),
  size72mm('72mm'),
  size80mm('80mm');

  const ThermalPosPrinterPageSize(this.title);
  final String title;
}

extension ThermalPosPrinterPageSizeStringExt on String {
  ThermalPosPrinterPageSize get toThermalPosPrinterPageSize => switch (this) {
    '58mm' => ThermalPosPrinterPageSize.size58mm,
    '72mm' => ThermalPosPrinterPageSize.size72mm,
    _ => ThermalPosPrinterPageSize.size80mm,
  };
}

extension ThermalPosPrinterPageSizeExt on ThermalPosPrinterPageSize {
  /// Printable width of the print head in dots.
  double get widthPx => switch (this) {
    ThermalPosPrinterPageSize.size58mm => 384.0,
    ThermalPosPrinterPageSize.size72mm => 512.0,
    ThermalPosPrinterPageSize.size80mm => 576.0,
  };

  /// The [PaperSize] used by the ESC/POS [Generator].
  PaperSize get toPaperSize => switch (this) {
    ThermalPosPrinterPageSize.size58mm => PaperSize.mm58,
    ThermalPosPrinterPageSize.size72mm => PaperSize.mm80,
    ThermalPosPrinterPageSize.size80mm => PaperSize.mm80,
  };
}

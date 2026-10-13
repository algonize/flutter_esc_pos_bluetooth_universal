import '../enums.dart';
import '../models/bluetooth_printer.dart';

/// Moves bytes to one printer over one kind of link (BLE, Classic RFCOMM or
/// Web Serial). The manager owns exactly one transport per connected printer.
abstract interface class PrinterTransport {
  /// The printer, updated after [connect] with anything learned while
  /// connecting (for BLE, the resolved write service and characteristic).
  BluetoothPrinter get printer;

  bool get isConnected;

  /// Opens the link. Throws [PrinterTransportException] on failure.
  Future<void> connect(Duration timeout);

  /// Sends [data], split and paced for this link.
  /// Throws [PrinterTransportException] on failure.
  Future<void> write(List<int> data);

  /// Closes the link after pending data has been sent. Never throws.
  Future<void> disconnect();
}

/// A transport failure, already translated into a [PosPrintResult].
class PrinterTransportException implements Exception {
  const PrinterTransportException(this.result, [this.cause]);

  final PosPrintResult result;

  /// The underlying error, for logging.
  final Object? cause;

  @override
  String toString() =>
      'PrinterTransportException(${result.name}${cause == null ? '' : ': $cause'})';
}

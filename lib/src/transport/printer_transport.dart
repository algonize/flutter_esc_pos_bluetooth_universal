import '../enums.dart';
import '../models/bluetooth_printer.dart';

/// Called by a transport before each piece of a write goes out, with the
/// piece's range in the data: `data[start..end)`. The transport writes the
/// piece once the returned future completes, so the sender can pace it.
///
/// A piece the link refused is offered again, so the same range (or part of
/// it) can come twice.
typedef WriteGate = Future<void> Function(List<int> data, int start, int end);

/// Moves bytes to one printer over one kind of link (BLE, Classic RFCOMM or
/// Web Serial). The manager owns exactly one transport per connected printer.
abstract interface class PrinterTransport {
  /// The printer, updated after [connect] with anything learned while
  /// connecting (for BLE, the resolved write service and characteristic).
  BluetoothPrinter get printer;

  bool get isConnected;

  /// Opens the link. Throws [PrinterTransportException] on failure.
  Future<void> connect(Duration timeout);

  /// Sends [data], split for this link, awaiting [gate] before each piece.
  /// Completes once the link has taken every byte, so closing it afterwards
  /// cannot cut the end off. Throws [PrinterTransportException] on failure.
  Future<void> write(List<int> data, {WriteGate? gate});

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

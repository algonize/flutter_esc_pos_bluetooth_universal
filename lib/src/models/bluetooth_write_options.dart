import 'package:flutter/foundation.dart';

/// How print data is split and paced on the way to the printer.
///
/// The defaults suit most printers. Tune them only if long tickets or images
/// come out cut short or garbled: a smaller chunk or a short delay gives slow
/// printers time to empty their buffer.
@immutable
class BluetoothWriteOptions {
  const BluetoothWriteOptions({
    this.bleChunkSize,
    this.bleChunkDelay = Duration.zero,
    this.preferWriteWithoutResponse = true,
    this.classicChunkSize = 4096,
    this.classicChunkDelay = const Duration(milliseconds: 10),
    this.classicSecureConnection = true,
    this.webSerialChunkSize = 4096,
    this.webSerialChunkDelay = const Duration(milliseconds: 10),
    this.webSerialBaudRate = 9600,
  }) : assert(bleChunkSize == null || (bleChunkSize >= 20 && bleChunkSize <= 512)),
       assert(classicChunkSize > 0),
       assert(webSerialChunkSize > 0);

  /// Bytes per BLE write. When null (recommended) it follows the connection:
  /// - Android, iOS, macOS, Windows, Linux: the negotiated MTU minus 3.
  /// - Web: 20 bytes, because browsers don't expose the MTU and larger writes
  ///   can be cut short silently on some systems. Raise it (for example to 180)
  ///   for faster printing once you've tested your printer.
  ///
  /// When a write is rejected, the size is lowered step by step automatically.
  final int? bleChunkSize;

  /// Pause after each BLE write. Usually not needed: writes already wait until
  /// the operating system accepts each packet.
  final Duration bleChunkDelay;

  /// Use "write without response" when the printer supports it. It is several
  /// times faster; turn it off for printers that drop data. The last chunk is
  /// still sent with response when the printer allows it, so the ticket is
  /// known to have arrived before the link is closed.
  final bool preferWriteWithoutResponse;

  /// Bytes per write on Bluetooth Classic (native platforms).
  final int classicChunkSize;

  /// Pause after each Classic write, giving the printer time to empty its buffer.
  final Duration classicChunkDelay;

  /// Use an authenticated, encrypted RFCOMM link. Some older printers only
  /// accept an insecure link; set this to false for them.
  final bool classicSecureConnection;

  /// Bytes per write on Web Serial (Classic printers in the browser).
  final int webSerialChunkSize;

  /// Pause after each Web Serial write.
  final Duration webSerialChunkDelay;

  /// Baud rate passed to Web Serial. Ignored by Bluetooth RFCOMM links, but
  /// required by the API.
  final int webSerialBaudRate;
}

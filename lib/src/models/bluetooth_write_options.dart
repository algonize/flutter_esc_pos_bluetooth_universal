import 'package:flutter/foundation.dart';

import 'write_pacing.dart';

/// How print data is split and paced on the way to the printer.
///
/// The defaults suit most printers. Data is paced to the printer's print speed
/// (see [pacing]), which is what keeps long tickets from coming out garbled;
/// the chunk sizes and delays only shape how the bytes are handed to the link.
@immutable
class BluetoothWriteOptions {
  const BluetoothWriteOptions({
    this.pacing = const WritePacing(),
    this.bleChunkSize,
    this.bleChunkDelay = Duration.zero,
    this.preferWriteWithoutResponse = true,
    this.webBleBatchSize = 4,
    this.classicChunkSize = 4096,
    this.classicChunkDelay = const Duration(milliseconds: 10),
    this.classicSecureConnection = true,
    this.webSerialChunkSize = 4096,
    this.webSerialChunkDelay = const Duration(milliseconds: 10),
    this.webSerialBaudRate = 9600,
  }) : assert(bleChunkSize == null || (bleChunkSize >= 20 && bleChunkSize <= 512)),
       assert(webBleBatchSize >= 1),
       assert(classicChunkSize > 0),
       assert(webSerialChunkSize > 0);

  /// Feeds data to the printer no faster than it prints, so its input buffer
  /// never overflows on a long ticket. Null turns pacing off.
  ///
  /// This applies to every link. Bluetooth has no flow control that reaches
  /// the print engine: a BLE write without response is never refused, and
  /// Classic printers take data before checking for room, so a long receipt
  /// sent at link speed overruns the buffer and its bottom part prints as
  /// garbage. See [WritePacing] for the default and how to tune it.
  final WritePacing? pacing;

  /// Bytes per BLE write. When null (recommended) it follows the connection:
  /// - Android, iOS, macOS, Windows, Linux: the negotiated MTU minus 3.
  /// - Web: 182 bytes, written with response. Browsers don't expose the MTU,
  ///   but a write with response that is too long is either sent as a long
  ///   write or rejected, never cut short.
  /// - Web, on a printer that only takes write without response: 20 bytes,
  ///   as a longer write could be cut short without an error.
  ///
  /// When a write is rejected, the size is lowered step by step automatically.
  final int? bleChunkSize;

  /// Pause between BLE writes. Usually not needed: writes already wait until
  /// the operating system accepts each packet, or until the printer confirms
  /// it. In a browser, on a printer that only takes write without response,
  /// 20 ms is used when this is zero, as browsers give no sign of when such a
  /// write has left.
  final Duration bleChunkDelay;

  /// Use "write without response" when the printer supports it. It is several
  /// times faster; turn it off for printers that drop data. The last chunk is
  /// still sent with response when the printer allows it, so the ticket is
  /// known to have arrived before the link is closed.
  ///
  /// Ignored on the web when the printer accepts write with response: there
  /// writes go out in batches (see [webBleBatchSize]), because browsers report a
  /// write without response as done at once, and Chrome on macOS drops the ones
  /// that don't fit the system's queue without an error.
  final bool preferWriteWithoutResponse;

  /// Web BLE only: how many chunks are written without response in a row before
  /// one is written with response, which the printer confirms. Browsers give no
  /// flow control for writes without response, and Chrome on macOS silently
  /// drops them once its queue overflows, so this acknowledged write every
  /// [webBleBatchSize] chunks keeps the queue shallow while staying about twice
  /// as fast as confirming every chunk. Only used when the printer accepts both
  /// kinds of write. Raise it for more speed on a printer you've tested, lower
  /// it (1 confirms every chunk) if a receipt ever comes out short.
  final int webBleBatchSize;

  /// Bytes per write on Bluetooth Classic (native platforms).
  final int classicChunkSize;

  /// Pause after each Classic write, giving the printer time to empty its buffer.
  final Duration classicChunkDelay;

  /// Use an authenticated, encrypted RFCOMM link. Some older printers only
  /// accept an insecure link; set this to false for them.
  final bool classicSecureConnection;

  /// Bytes per write on Web Serial (Classic printers in the browser). However
  /// it is split, a print only finishes once the browser has sent every byte.
  final int webSerialChunkSize;

  /// Pause after each Web Serial write.
  final Duration webSerialChunkDelay;

  /// Baud rate passed to Web Serial. Ignored by Bluetooth RFCOMM links, but
  /// required by the API.
  final int webSerialBaudRate;
}

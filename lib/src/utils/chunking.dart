/// Splits [data] into consecutive slices of at most [size] bytes.
Iterable<List<int>> chunked(List<int> data, int size) sync* {
  assert(size > 0);
  for (var offset = 0; offset < data.length; offset += size) {
    final end = offset + size < data.length ? offset + size : data.length;
    yield data.sublist(offset, end);
  }
}

/// BLE write sizes to step down through when a write is rejected. 20 bytes
/// always fits, as it is the payload of the smallest possible MTU (23).
const List<int> bleChunkLadder = [512, 244, 182, 128, 100, 64, 20];

/// The smallest BLE write size.
const int minBleChunk = 20;

/// The first BLE write size tried in a browser, for writes with response. It
/// fills one packet at the MTU of 185 that Apple devices and many printers
/// settle on. On a smaller MTU it goes as a long write, or is rejected and
/// stepped down.
const int webBleChunkWithResponse = 182;

/// The next smaller size from [bleChunkLadder], or [minBleChunk].
int nextSmallerBleChunk(int current) {
  for (final size in bleChunkLadder) {
    if (size < current) return size;
  }
  return minBleChunk;
}

/// The usable write size for a negotiated [mtu]: the ATT header takes 3 bytes.
/// Clamped to 20..512, the limits of a single BLE characteristic write.
int bleChunkForMtu(int mtu) => (mtu - 3).clamp(minBleChunk, 512);

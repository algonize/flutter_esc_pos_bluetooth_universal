import 'package:fake_async/fake_async.dart';
import 'package:flutter_esc_pos_bluetooth_universal/flutter_esc_pos_bluetooth_universal.dart';
import 'package:flutter_esc_pos_bluetooth_universal/src/utils/write_pacer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('WritePacing', () {
    test('a millimetre of raster is the paper width in bytes', () {
      // 8 rows per mm, widthDots / 8 bytes per row.
      expect(const WritePacing(mmPerSecond: 60).bytesPerSecond(384), 384 * 60);
      expect(const WritePacing(mmPerSecond: 40).bytesPerSecond(576), 576 * 40);
      expect(const WritePacing(mmPerSecond: 0.5, darkMmPerSecond: 0.5).bytesPerSecond(1), 1);
    });

    test('a dense byte costs the ratio of the two speeds', () {
      expect(const WritePacing(mmPerSecond: 50, darkMmPerSecond: 5).darkRatio, 10);
      expect(const WritePacing(mmPerSecond: 40, darkMmPerSecond: 40).darkRatio, 1);
    });

    test('defaults to the speeds that printed a whole receipt cleanly', () {
      const pacing = WritePacing();
      expect(pacing.mmPerSecond, 50);
      expect(pacing.darkMmPerSecond, 5);
      expect(pacing.burstBytes, 4096);
      expect(pacing.denseThreshold, 0.25);
    });

    test('is on by default in the write options', () {
      expect(const BluetoothWriteOptions().pacing, isNotNull);
      expect(const BluetoothWriteOptions(pacing: null).pacing, isNull);
    });
  });

  group('WritePacer', () {
    test('null pacing gives no pacer', () {
      expect(WritePacer.of(null, widthDots: 384), isNull);
      expect(WritePacer.of(const WritePacing(), widthDots: 384), isNotNull);
    });

    test('lets the burst through at once, then holds data to the rate', () {
      fakeAsync((async) {
        final pacer = WritePacer(
          bytesPerSecond: 1000,
          burstBytes: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        final sentAt = <int>[];
        void send(int bytes) =>
            pacer.wait(bytes).then((_) => sentAt.add(async.elapsed.inMilliseconds));

        // 100 bytes of burst, then 1 byte per millisecond.
        send(60);
        send(40);
        send(50);
        send(50);
        async.flushMicrotasks();
        expect(sentAt, [0, 0], reason: 'the burst goes out without waiting');
        async.elapse(const Duration(milliseconds: 49));
        expect(sentAt, [0, 0]);
        async.elapse(const Duration(milliseconds: 1));
        expect(sentAt, [0, 0, 50]);
        async.elapse(const Duration(milliseconds: 50));
        expect(sentAt, [0, 0, 50, 100]);
      });
    });

    test('a long ticket leaves at the rate, whatever the chunk size', () {
      fakeAsync((async) {
        final pacer = WritePacer(
          bytesPerSecond: 10000,
          burstBytes: 4096,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        var sent = 0;
        Future<void> run() async {
          for (var i = 0; i < 100; i++) {
            await pacer.wait(182);
            sent += 182;
          }
        }

        run();
        async.elapse(const Duration(seconds: 1));
        // Burst plus one second at the rate, give or take a chunk.
        expect(sent, closeTo(4096 + 10000, 182));
        async.elapse(const Duration(seconds: 1));
        expect(sent, 18200);
      });
    });

    test('a write larger than the burst waits for the burst and runs a debt', () {
      fakeAsync((async) {
        final pacer = WritePacer(
          bytesPerSecond: 1000,
          burstBytes: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        final sentAt = <int>[];
        pacer.wait(300).then((_) => sentAt.add(async.elapsed.inMilliseconds));
        pacer.wait(100).then((_) => sentAt.add(async.elapsed.inMilliseconds));
        async.flushMicrotasks();
        // 300 bytes: the burst covers 100, the other 200 take 200 ms.
        async.elapse(const Duration(milliseconds: 199));
        expect(sentAt, isEmpty);
        async.elapse(const Duration(milliseconds: 1));
        expect(sentAt, [200]);
        // The bucket is empty: the next 100 bytes take 100 ms more.
        async.elapse(const Duration(milliseconds: 100));
        expect(sentAt, [200, 300]);
      });
    });

    test('a booked debt holds back the next write, even one that costs nothing', () {
      fakeAsync((async) {
        final pacer = WritePacer(
          bytesPerSecond: 1000,
          burstBytes: 0,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        pacer.book(150);
        final sentAt = <int>[];
        pacer.wait(0).then((_) => sentAt.add(async.elapsed.inMilliseconds));
        async.flushMicrotasks();
        expect(sentAt, isEmpty);
        async.elapse(const Duration(milliseconds: 150));
        expect(sentAt, [150]);
        // Paid off: nothing more to wait for.
        pacer.wait(0).then((_) => sentAt.add(async.elapsed.inMilliseconds));
        async.flushMicrotasks();
        expect(sentAt, [150, 150]);
      });
    });

    test('idle time refills the bucket, but never past the burst', () {
      fakeAsync((async) {
        final pacer = WritePacer(
          bytesPerSecond: 1000,
          burstBytes: 100,
          nowMicros: () => async.elapsed.inMicroseconds,
        );
        var done = false;
        pacer.wait(100).then((_) => done = true);
        async.flushMicrotasks();
        expect(done, isTrue);
        // A long pause (another ticket's worth of printing) refills to the
        // burst only, so the next ticket cannot overrun the buffer either.
        async.elapse(const Duration(seconds: 10));
        final sentAt = <int>[];
        pacer.wait(100).then((_) => sentAt.add(async.elapsed.inMilliseconds));
        pacer.wait(100).then((_) => sentAt.add(async.elapsed.inMilliseconds));
        async.flushMicrotasks();
        expect(sentAt, [10000]);
        async.elapse(const Duration(milliseconds: 100));
        expect(sentAt, [10000, 10100]);
      });
    });
  });
}

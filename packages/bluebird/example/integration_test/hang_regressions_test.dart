// Fixture-less regressions for the ways bluebird used to wedge for the life of
// the process, against the real platform. Needs an adapter that is on and, for
// the connect cases, any non-connectable advertiser in range (an Apple device
// will do). Run with:
//   flutter test integration_test/hang_regressions_test.dart -d macos
// On Android the harness installs fresh, so either accept the permission
// dialog or grant BLUETOOTH_SCAN and BLUETOOTH_CONNECT with `pm grant` first.

import 'package:bluebird/bluebird.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

Matcher throwsCode(BluebirdErrorCode code) => throwsA(isA<BluebirdException>().having((e) => e.code, 'code', code));

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() => Bluebird.adapterReady());

  // the connect group scans first: the cancel loop below trips Android's
  // 30 s scan throttle, which silently returns nothing
  group('a connect the platform never completes', () {
    late BluetoothDevice device;

    setUpAll(() async {
      final advertiser = await Bluebird.performScan(timeout: const Duration(seconds: 15))
          .firstWhere((r) => !r.advertisementData.connectable)
          .timeout(const Duration(seconds: 20), onTimeout: () => fail('no non-connectable advertiser in range'));
      device = advertiser.device;
    });

    test('times out, then wedges nothing and can be retried', () async {
      final stopwatch = Stopwatch()..start();
      await expectLater(device.connect(timeout: const Duration(seconds: 5)), throwsCode(BluebirdErrorCode.timeout));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 15)));
      expect(device.isConnected, isFalse);

      // an unrelated call is not queued behind it
      await Bluebird.isSupported.timeout(const Duration(seconds: 2));

      // and the retry does not hit operation_in_progress
      await expectLater(device.connect(timeout: const Duration(seconds: 3)), throwsCode(BluebirdErrorCode.timeout));
    });

    test('disconnect(queue: false) cancels it promptly', () async {
      final connect = expectLater(
        device.connect(timeout: const Duration(seconds: 30)),
        throwsCode(BluebirdErrorCode.userCanceled),
      );
      await Future<void>.delayed(const Duration(milliseconds: 300));

      final stopwatch = Stopwatch()..start();
      await device.disconnect(queue: false).timeout(const Duration(seconds: 5));
      await connect.timeout(const Duration(seconds: 5));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
      expect(device.isConnected, isFalse);
    });
  });

  test('cancelling a scan while it starts never wedges scanning', () async {
    for (var i = 0; i < 30; i++) {
      // Android throttles frequent scan starts with a scan-failed event; that
      // ends the scan, which is fine, it just must not wedge it
      final subscription = Bluebird.performScan().listen((_) {}, onError: (_) {});
      // 0-2 ms, to land on both sides of startScan returning
      await Future<void>.delayed(Duration(milliseconds: i % 3));
      await subscription.cancel().timeout(const Duration(seconds: 5));
      expect(Bluebird.isScanning.value, isFalse, reason: 'iteration $i');
    }

    // and scanning still works afterwards (or is throttled, which also ends cleanly)
    try {
      await Bluebird.performScan(timeout: const Duration(seconds: 2)).toList().timeout(const Duration(seconds: 10));
    } on BluebirdException catch (e) {
      expect(e.code, BluebirdErrorCode.platform, reason: 'only the throttle is acceptable here');
    }
    expect(Bluebird.isScanning.value, isFalse);
  });
}

import 'package:bluebird/bluebird.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_platform.dart';

void main() {
  late FakePlatform fake;

  setUp(() {
    fake = FakePlatform();
    FakePlatform.install(fake);
  });

  test('cancelling a scan while startScan is in flight releases the scan guard', () async {
    fake.stubs['startScan'] = () => Future<void>.delayed(const Duration(milliseconds: 100));

    final subscription = Bluebird.performScan().listen((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await subscription.cancel();

    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(Bluebird.isScanning.value, isFalse);
    expect(fake.calls, contains('stopScan'));
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(OfflineConnectivity.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('hardware support does not imply implemented connectivity', () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getCapabilities');
      expect(call.arguments, isNull);
      return {
        'platform': 'android',
        'wifiDirectSupported': true,
        'implementationReady': false,
        'description': 'Adapter pending.',
      };
    });
    final capabilities = await const OfflineConnectivity().getCapabilities();
    expect(capabilities.wifiDirectSupported, isTrue);
    expect(capabilities.implementationReady, isFalse);
  });

  test(
    'malformed native response fails rather than implying readiness',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        return {'platform': 'android', 'implementationReady': 'true'};
      });
      await expectLater(
        const OfflineConnectivity().getCapabilities(),
        throwsFormatException,
      );
    },
  );

  test('native failures propagate to the UI boundary', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'unavailable');
    });
    await expectLater(
      const OfflineConnectivity().getCapabilities(),
      throwsA(isA<PlatformException>()),
    );
  });
}

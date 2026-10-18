import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'group_invitation_test.dart' show validInvitation;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel(OfflineConnectivity.channelName);
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const api = OfflineConnectivity();
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'NFC methods use the shared invitation without automatically joining',
    () async {
      final calls = <MethodCall>[];
      final invitation = GroupInvitation.fromMap(validInvitation());
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return call.method == 'readNfcInvitation' ? invitation.encode() : null;
      });
      await api.startNfcSharing();
      expect((await api.readNfcInvitation()).toMap(), invitation.toMap());
      await api.stopNfc();
      expect(calls.map((c) => c.method), [
        'startNfcSharing',
        'readNfcInvitation',
        'stopNfc',
      ]);
      expect(calls.every((c) => c.arguments == null), isTrue);
    },
  );

  test('malformed NFC payloads and native failures are not accepted', () async {
    for (final raw in [null, '{}', 'https://example.com', 'x' * 2049]) {
      messenger.setMockMethodCallHandler(channel, (_) async => raw);
      await expectLater(api.readNfcInvitation(), throwsFormatException);
    }
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => throw PlatformException(code: 'nfc_disabled'),
    );
    await expectLater(
      api.readNfcInvitation(),
      throwsA(isA<PlatformException>()),
    );
  });

  test('NFC capabilities are independent and default to unsupported', () {
    final map = <String, dynamic>{
      'platform': 'android',
      'wifiDirectSupported': true,
      'implementationReady': true,
      'description': 'Ready',
    };
    expect(ConnectionCapabilities.fromMap(map).canJoinNfc, isFalse);
    expect(ConnectionCapabilities.fromMap(map).canShareNfc, isFalse);
    map['canJoinNfc'] = true;
    final reader = ConnectionCapabilities.fromMap(map);
    expect(reader.canJoinNfc, isTrue);
    expect(reader.canShareNfc, isFalse);
  });
}

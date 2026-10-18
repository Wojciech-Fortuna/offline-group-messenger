import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

Map<String, dynamic> validInvitation() => {
  'app': 'offline-group-messenger',
  'version': 1,
  'transport': 'wifi-direct',
  'networkName': 'DIRECT-ab-Group',
  'passphrase': 'test-password-123',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('invitation round trips escaped credentials', () {
    final map = validInvitation()..['passphrase'] = 'a"b:c;d\\e123';
    final invitation = GroupInvitation.fromMap(map);
    expect(GroupInvitation.parse(invitation.encode()).toMap(), map);
  });
  test(
    'rejects other QR formats, versions, invalid credentials and large input',
    () {
      for (final raw in [
        'https://example.com',
        '[]',
        '{}',
        'WIFI:S:example;P:password;;',
        jsonEncode(validInvitation()..['version'] = 2),
        jsonEncode(validInvitation()..['app'] = 'another-app'),
        jsonEncode(validInvitation()..['passphrase'] = 'short'),
        jsonEncode(validInvitation()..['networkName'] = 'Home Wi-Fi'),
        jsonEncode(
          validInvitation()..['networkName'] = 'DIRECT-ab-${'x' * 40}',
        ),
        'x' * 2049,
      ]) {
        expect(() => GroupInvitation.parse(raw), throwsFormatException);
      }
    },
  );
  test('host retrieval and QR join preserve the typed payload', () async {
    const channel = MethodChannel(OfflineConnectivity.channelName);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return call.method == 'getInvitation' ? validInvitation() : null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    const api = OfflineConnectivity();
    final invitation = await api.getInvitation();
    await api.joinInvitation(invitation);
    expect(calls.map((c) => c.method), ['getInvitation', 'joinInvitation']);
    expect(calls.last.arguments, validInvitation());
  });
}

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

  test('operations use the native methods and selected peer ID', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    const api = OfflineConnectivity();
    await api.createGroup();
    await api.discoverPeers();
    await api.joinGroup('02:11:22:33:44:55');
    await api.disconnect();
    expect(calls.map((c) => c.method), [
      'createGroup',
      'discoverPeers',
      'joinGroup',
      'disconnect',
    ]);
    expect(calls[2].arguments, {'peerId': '02:11:22:33:44:55'});
  });

  test('connection snapshot preserves actual host address and role', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => {
        'status': 'connected',
        'wifiEnabled': true,
        'permissionGranted': true,
        'isHost': false,
        'hostAddress': '192.168.88.7',
        'peers': <Object>[],
        'errorCode': null,
        'errorMessage': null,
      },
    );
    final state = await const OfflineConnectivity().getState();
    expect(state.hostAddress, '192.168.88.7');
    expect(state.isHost, isFalse);
    expect(state.status, GroupStatus.connected);
  });

  test('connected without an address is rejected', () {
    expect(
      () => GroupConnectionState.fromMap({
        'status': 'connected',
        'wifiEnabled': true,
        'permissionGranted': true,
        'isHost': true,
        'hostAddress': null,
        'peers': <Object>[],
      }),
      throwsFormatException,
    );
  });

  test(
    'events deliver peers and host changes and cancel native subscription',
    () async {
      const eventChannel = MethodChannel(OfflineConnectivity.eventChannelName);
      final lifecycle = <String>[];
      messenger.setMockMethodCallHandler(eventChannel, (call) async {
        lifecycle.add(call.method);
        return null;
      });
      final received = <GroupConnectionState>[];
      final subscription = const OfflineConnectivity().states.listen(
        received.add,
      );
      await Future<void>.delayed(Duration.zero);
      final event = {
        'status': 'discovering',
        'wifiEnabled': true,
        'permissionGranted': true,
        'isHost': false,
        'hostAddress': null,
        'peers': [
          {'id': 'peer-1', 'name': 'Host phone', 'isGroupOwner': true},
        ],
      };
      await messenger.handlePlatformMessage(
        OfflineConnectivity.eventChannelName,
        const StandardMethodCodec().encodeSuccessEnvelope(event),
        (_) {},
      );
      await Future<void>.delayed(Duration.zero);
      expect(received.single.peers.single.id, 'peer-1');
      await subscription.cancel();
      expect(lifecycle, ['listen', 'cancel']);
      messenger.setMockMethodCallHandler(eventChannel, null);
    },
  );
}

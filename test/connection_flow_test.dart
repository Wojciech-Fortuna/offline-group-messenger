import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/app/app.dart';

class FakeConnection extends OfflineConnectivity {
  final updates = StreamController<GroupConnectionState>.broadcast();
  int creates = 0;
  int disconnects = 0;
  String? joined;
  bool denied = false;
  @override
  Future<ConnectionCapabilities> getCapabilities() async =>
      const ConnectionCapabilities(
        platform: 'android',
        wifiDirectSupported: true,
        implementationReady: true,
        description: 'Android ready',
      );
  @override
  Stream<GroupConnectionState> get states => updates.stream;
  @override
  Future<void> createGroup() async {
    creates++;
    if (denied) {
      throw PlatformException(
        code: 'permission_denied',
        message: 'Permission denied.',
      );
    }
    updates.add(
      const GroupConnectionState(
        status: GroupStatus.connecting,
        wifiEnabled: true,
      ),
    );
  }

  @override
  Future<void> joinGroup(String peerId) async {
    joined = peerId;
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
    updates.add(
      const GroupConnectionState(wifiEnabled: true, permissionGranted: true),
    );
  }
}

void main() {
  testWidgets(
    'accepted creation waits for connection info and shows actual IP',
    (tester) async {
      final connection = FakeConnection();
      addTearDown(connection.updates.close);
      await tester.pumpWidget(MessengerApp(connectivity: connection));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create a group'));
      await tester.pumpAndSettle();
      expect(connection.creates, 1);
      expect(find.textContaining('Connecting —'), findsOneWidget);
      expect(find.textContaining('Host IP:'), findsNothing);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      connection.updates.add(
        const GroupConnectionState(
          status: GroupStatus.connected,
          wifiEnabled: true,
          permissionGranted: true,
          isHost: true,
          hostAddress: '192.168.88.7',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Host IP: 192.168.88.7'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Disconnect'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Disconnect'));
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(find.text('End this group?'), findsOneWidget);
      await tester.tap(find.text('End group'));
      await tester.pumpAndSettle();
      expect(connection.disconnects, 1);
      expect(find.textContaining('Host IP:'), findsNothing);
    },
  );

  testWidgets('discovered peer passes its ID to join', (tester) async {
    final connection = FakeConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    connection.updates.add(
      const GroupConnectionState(
        status: GroupStatus.discovering,
        wifiEnabled: true,
        permissionGranted: true,
        peers: [
          NearbyPeer(id: 'peer-42', name: 'Host phone', isGroupOwner: true),
        ],
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Join'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Join'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(connection.joined, 'peer-42');
  });

  testWidgets('permission denial leaves controls usable', (tester) async {
    final connection = FakeConnection()..denied = true;
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create a group'));
    await tester.pumpAndSettle();
    expect(find.text('Permission denied.'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNotNull,
    );
  });
}

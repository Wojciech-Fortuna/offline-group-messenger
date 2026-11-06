import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/core/messaging/chat_session_controller.dart';
import 'package:offline_group_messenger/features/home/home_screen.dart';
import 'nfc_invitation_test.dart' show NfcConnection;
import 'private_membership_test.dart' show invitation;
import 'chat_session_controller_test.dart' show ControlledTransport;

const privateConnection = GroupConnectionState(
  status: GroupStatus.connected,
  privateGroup: true,
  hostAddress: '127.0.0.1',
  wifiEnabled: true,
  permissionGranted: true,
);

class RememberedConnection extends NfcConnection {
  int searches = 0;
  GroupInvitation? lastJoin;
  @override
  Future<void> discoverPeers() async {
    searches++;
  }

  @override
  Future<void> joinInvitation(GroupInvitation value) async {
    lastJoin = value;
    updates.add(privateConnection);
  }
}

void main() {
  testWidgets(
    'nearby groups offers remembered private rejoin without reading NFC again',
    (tester) async {
      final transport = ControlledTransport();
      final chat = ChatSessionController(transport: transport);
      final connection = RememberedConnection();
      addTearDown(chat.dispose);
      addTearDown(connection.updates.close);
      final saved = invitation('a' * 64);
      chat.prepareJoin(invitation: saved);
      chat.updateConnection(privateConnection, displayName: 'Alice');
      await chat.leave();
      chat.updateConnection(const GroupConnectionState(), displayName: 'Alice');
      await tester.pumpWidget(
        MaterialApp(
          home: HomeScreen(connectivity: connection, chat: chat),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Find nearby groups'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Find nearby groups'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Your private group'),
        180,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Availability is checked'), findsOneWidget);
      await tester.tap(find.text('Rejoin'));
      await tester.pumpAndSettle();
      expect(connection.lastJoin, same(saved));
      expect(connection.searches, 1);
      expect(transport.connects, 2);
      expect(connection.read.isCompleted, isFalse);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('uninvited phone has no remembered private entry', (
    tester,
  ) async {
    final connection = RememberedConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(connectivity: connection)),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Find nearby groups'),
      180,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Find nearby groups'));
    await tester.pumpAndSettle();
    expect(find.text('Your private group'), findsNothing);
    expect(find.text('Rejoin'), findsNothing);
  });
}

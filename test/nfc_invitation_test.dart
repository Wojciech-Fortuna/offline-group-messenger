import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/app/app.dart';
import 'package:offline_group_messenger/features/invitations/nfc_invitation_screen.dart';
import 'qr_invitation_test.dart' show QrConnection, invitation;

class NfcConnection extends QrConnection {
  int shares = 0;
  int stops = 0;
  bool disabled = false;
  final read = Completer<GroupInvitation>();
  @override
  Future<ConnectionCapabilities> getCapabilities() async =>
      const ConnectionCapabilities(
        platform: 'android',
        wifiDirectSupported: true,
        implementationReady: true,
        canJoinQr: true,
        canJoinNfc: true,
        canShareNfc: true,
        description: 'Ready',
      );
  @override
  Future<void> startNfcSharing() async {
    shares++;
    if (disabled) {
      throw PlatformException(
        code: 'nfc_disabled',
        message: 'Enable NFC in settings.',
      );
    }
  }

  @override
  Future<GroupInvitation> readNfcInvitation() => read.future;
  @override
  Future<void> stopNfc() async {
    stops++;
  }
}

void main() {
  testWidgets('NFC reading returns to confirmation before joining once', (
    tester,
  ) async {
    final connection = NfcConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Join via NFC'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Join via NFC'));
    await tester.pumpAndSettle();
    expect(find.text('Tap the host phone'), findsOneWidget);
    expect(connection.qrJoins, 0);
    connection.read.complete(invitation);
    await tester.pumpAndSettle();
    expect(find.text('Join this group?'), findsOneWidget);
    expect(connection.qrJoins, 0);
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(connection.qrJoins, 1);
    expect(connection.stops, greaterThanOrEqualTo(1));
  });

  testWidgets('late read after back cannot open confirmation or pop home', (
    tester,
  ) async {
    final connection = NfcConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Join via NFC'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Join via NFC'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    // Complete during the outgoing route animation, not just after disposal.
    connection.read.complete(invitation);
    await tester.pumpAndSettle();
    expect(find.byType(NfcInvitationScreen), findsNothing);
    expect(find.text('Join this group?'), findsNothing);
    expect(connection.qrJoins, 0);
    expect(connection.stops, greaterThanOrEqualTo(1));
  });

  testWidgets('host sharing expires, retries and stops on group loss', (
    tester,
  ) async {
    final connection = NfcConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NfcInvitationScreen(connectivity: connection, sharing: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(connection.shares, 1);
    expect(find.text('Sharing enabled for up to 60 seconds.'), findsOneWidget);
    await tester.pump(const Duration(seconds: 61));
    expect(find.textContaining('Sharing expired'), findsOneWidget);
    expect(connection.stops, 1);
    await tester.tap(find.text('Retry NFC'));
    await tester.pumpAndSettle();
    expect(connection.shares, 2);
    connection.updates.add(const GroupConnectionState());
    await tester.pumpAndSettle();
    expect(
      find.textContaining('host group is no longer available'),
      findsOneWidget,
    );
    expect(connection.stops, 2);
  });

  testWidgets('background revokes sharing and requires an explicit retry', (
    tester,
  ) async {
    final connection = NfcConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NfcInvitationScreen(connectivity: connection, sharing: true),
      ),
    );
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(connection.stops, greaterThanOrEqualTo(1));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(connection.shares, 1);
    expect(find.text('Retry NFC'), findsOneWidget);
  });

  testWidgets('disabled NFC shows recovery and QR fallback', (tester) async {
    final connection = NfcConnection()..disabled = true;
    addTearDown(connection.updates.close);
    await tester.pumpWidget(
      MaterialApp(
        home: NfcInvitationScreen(connectivity: connection, sharing: true),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enable NFC in settings.'), findsOneWidget);
    expect(find.text('Retry NFC'), findsOneWidget);
    expect(find.textContaining('use QR instead'), findsOneWidget);
    expect(connection.qrJoins, 0);
  });
}

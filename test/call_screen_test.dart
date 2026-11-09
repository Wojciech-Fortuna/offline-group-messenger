import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/calling/call_controller.dart';
import 'package:offline_group_messenger/core/contacts/contact_repository.dart';
import 'package:offline_group_messenger/core/messaging/tcp_message_transport.dart';
import 'package:offline_group_messenger/features/calling/call_screen.dart';

class EmptyCallContacts extends ContactRepository {
  @override
  Future<ContactSnapshot> load() async => const ContactSnapshot('self', []);
}

class CallUiFake extends CallController {
  CallUiFake() : super(TcpMessageTransport(), contacts: EmptyCallContacts());
  int answered = 0;
  @override
  Future<void> answer() async {
    answered++;
    state = 'connecting';
    notifyListeners();
  }
}

void main() {
  testWidgets('incoming screen requires Answer and offers Decline', (
    tester,
  ) async {
    final calls = CallUiFake();
    await tester.pumpWidget(MaterialApp(home: CallScreen(calls: calls)));
    await tester.pump();
    calls.callId = 'call';
    calls.state = 'incoming';
    calls.notifyListeners();
    await tester.pump();
    expect(find.text('Incoming voice call'), findsOneWidget);
    expect(find.text('Answer'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(calls.answered, 0);
    await tester.tap(find.text('Answer'));
    await tester.pump();
    expect(calls.answered, 1);
    expect(find.text('Connecting audio…'), findsOneWidget);
    await tester.tap(find.text('Hang up'));
    await tester.pump();
    expect(calls.hasCall, isFalse);
    expect(find.text('Answer'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    calls.dispose();
    calls.transport.dispose();
  });
}

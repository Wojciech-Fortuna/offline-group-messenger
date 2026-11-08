import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_group_messenger/core/contacts/contact_repository.dart';
import 'package:offline_group_messenger/features/contacts/contacts_screen.dart';

class ContactsFake extends ContactRepository {
  int approvals = 0;
  int stops = 0;
  Map<String, dynamic>? state;
  @override
  Future<ContactSnapshot> load() async => const ContactSnapshot('self', [
    SavedContact(id: 'peer', name: 'Bob', trust: ContactTrust.pending),
  ]);
  @override
  Future<void> startPairing(String name, {required bool reader}) async {
    state = {
      'state': 'confirm',
      'name': 'Bob',
      'code': '1234 abcd',
      'approved': false,
    };
  }

  @override
  Future<Map<String, dynamic>?> pairingStatus() async => state;
  @override
  Future<void> approvePairing() async {
    approvals++;
    state!['approved'] = true;
  }

  @override
  Future<void> stopPairing() async {
    stops++;
  }
}

void main() {
  testWidgets('pending contact cannot appear verified or callable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(home: ContactsScreen(repository: ContactsFake())),
    );
    await tester.pumpAndSettle();
    expect(find.text('Bob'), findsOneWidget);
    expect(find.textContaining('Pairing incomplete'), findsOneWidget);
    expect(find.text('Verified by NFC'), findsNothing);
    expect(find.text('Call'), findsNothing);
  });
  testWidgets('NFC comparison requires explicit confirmation and cleans up', (
    tester,
  ) async {
    final repository = ContactsFake();
    await tester.pumpWidget(
      MaterialApp(home: ContactPairingScreen(repository: repository)),
    );
    await tester.enterText(find.byType(TextField), 'Alice');
    await tester.tap(find.text('Read contact'));
    await tester.pumpAndSettle();
    expect(repository.approvals, 0);
    expect(find.text('1234 abcd'), findsOneWidget);
    await tester.ensureVisible(find.text('Codes match — confirm contact'));
    await tester.tap(find.text('Codes match — confirm contact'));
    await tester.pumpAndSettle();
    expect(repository.approvals, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(repository.stops, 1);
  });
}

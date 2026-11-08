import 'package:flutter/services.dart';

enum ContactTrust { pending, verified, blocked }

class SavedContact {
  const SavedContact({
    required this.id,
    required this.name,
    required this.trust,
  });
  factory SavedContact.fromMap(Map<dynamic, dynamic> raw) => SavedContact(
    id: raw['id'] as String,
    name: raw['name'] as String,
    trust: ContactTrust.values.byName(raw['state'] as String),
  );
  final String id;
  final String name;
  final ContactTrust trust;
}

class ContactSnapshot {
  const ContactSnapshot(this.identity, this.contacts);
  final String identity;
  final List<SavedContact> contacts;
}

/// Android owns private keys, encrypted persistence and trust transitions.
class ContactRepository {
  const ContactRepository();
  static const channel = MethodChannel('com.offlinegroupmessenger/contacts');
  Future<ContactSnapshot> load() async {
    final raw = (await channel.invokeMapMethod<String, dynamic>('snapshot'))!;
    return ContactSnapshot(raw['identity'] as String, [
      for (final item in raw['contacts'] as List)
        SavedContact.fromMap(item as Map),
    ]);
  }

  Future<void> rename(String id, String name) =>
      channel.invokeMethod('rename', {'id': id, 'name': name});
  Future<void> block(String id) => channel.invokeMethod('block', {'id': id});
  Future<void> delete(String id) => channel.invokeMethod('delete', {'id': id});
  Future<void> reset() => channel.invokeMethod('reset');
  Future<void> startPairing(String name, {required bool reader}) =>
      channel.invokeMethod('pairingStart', {'name': name, 'reader': reader});
  Future<Map<String, dynamic>?> pairingStatus() =>
      channel.invokeMapMethod<String, dynamic>('pairingStatus');
  Future<void> approvePairing() => channel.invokeMethod('pairingApprove');
  Future<void> stopPairing() => channel.invokeMethod('pairingStop');
}

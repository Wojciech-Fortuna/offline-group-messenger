import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/contacts/contact_repository.dart';
import '../../core/calling/call_controller.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({
    super.key,
    this.repository = const ContactRepository(),
    this.calls,
  });
  final ContactRepository repository;
  final CallController? calls;
  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  ContactSnapshot? snapshot;
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    widget.calls?.addListener(_callsChanged);
    unawaited(load());
  }

  void _callsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.calls?.removeListener(_callsChanged);
    super.dispose();
  }

  Future<void> load() async {
    try {
      final result = await widget.repository.load();
      await widget.calls?.refreshContacts();
      if (mounted) {
        setState(() {
          snapshot = result;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Cannot access contacts on this device. Retry, or reset contacts if their keys were lost.',
        );
      }
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
      await load();
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Could not update contacts. Please retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> confirm(String title, String message) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> change(SavedContact contact, String action) async {
    if (action == 'rename') {
      final field = TextEditingController(text: contact.name);
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Contact name'),
          content: TextField(controller: field, maxLength: 32, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                if (field.text.trim().isNotEmpty) {
                  Navigator.pop(context, field.text.trim());
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      );
      // Dialog route may still be animating; let its TextField detach first.
      Future<void>.delayed(const Duration(seconds: 1), field.dispose);
      if (value != null && mounted) {
        await run(() => widget.repository.rename(contact.id, value));
      }
    } else {
      final block = action == 'block';
      if (await confirm(
            block ? 'Block ${contact.name}?' : 'Delete ${contact.name}?',
            block
                ? 'This contact will not be able to request calls or pair again. Chat group membership stays unchanged.'
                : 'Remove saved trust. You will need to pair by NFC again. Deleting a blocked contact also removes its block.',
          ) &&
          mounted) {
        await run(
          () => block
              ? widget.repository.block(contact.id)
              : widget.repository.delete(contact.id),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Contacts'),
      actions: [
        IconButton(
          onPressed: busy ? null : load,
          tooltip: 'Refresh contacts',
          icon: const Icon(Icons.refresh),
        ),
        IconButton(
          tooltip: 'Reset contact identity',
          icon: const Icon(Icons.delete_forever),
          onPressed: busy
              ? null
              : () async {
                  if (await confirm(
                        'Reset all contacts?',
                        'Deletes your contact identity and all saved contacts. Everyone must pair with you by NFC again.',
                      ) &&
                      mounted) {
                    await run(widget.repository.reset);
                  }
                },
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        FilledButton.icon(
          onPressed: busy || snapshot == null
              ? null
              : () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ContactPairingScreen(repository: widget.repository),
                    ),
                  );
                  if (mounted) await load();
                },
          icon: const Icon(Icons.nfc),
          label: const Text('Add contact by NFC'),
        ),
        const SizedBox(height: 12),
        if (snapshot?.contacts.isEmpty == true)
          const Text(
            'No contacts yet. Add someone by touching your phones together.',
          ),
        for (final contact in snapshot?.contacts ?? <SavedContact>[])
          ListTile(
            leading: Icon(
              contact.trust == ContactTrust.blocked
                  ? Icons.block
                  : Icons.person,
            ),
            title: Text(contact.name),
            subtitle: Text(switch (contact.trust) {
              ContactTrust.pending =>
                'Pairing incomplete — repeat NFC on both phones',
              ContactTrust.verified =>
                widget.calls?.availability(contact.id) ?? 'Verified by NFC',
              ContactTrust.blocked =>
                'Blocked — delete to allow a new NFC pairing',
            }),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (contact.trust == ContactTrust.verified &&
                    widget.calls != null)
                  IconButton(
                    tooltip: 'Call',
                    icon: const Icon(Icons.call),
                    onPressed:
                        busy ||
                            widget.calls!.hasCall ||
                            widget.calls!.peerFor(contact.id) == null
                        ? null
                        : () => widget.calls!.dial(contact.id),
                  ),
                PopupMenuButton<String>(
                  enabled: !busy,
                  onSelected: (value) => change(contact, value),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename')),
                    if (contact.trust != ContactTrust.blocked)
                      const PopupMenuItem(value: 'block', child: Text('Block')),
                    const PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class ContactPairingScreen extends StatefulWidget {
  const ContactPairingScreen({super.key, required this.repository});
  final ContactRepository repository;
  @override
  State<ContactPairingScreen> createState() => _ContactPairingScreenState();
}

class _ContactPairingScreenState extends State<ContactPairingScreen>
    with WidgetsBindingObserver {
  final name = TextEditingController();
  Timer? timer;
  Map<String, dynamic>? pairing;
  bool busy = false;
  bool polling = false;
  bool started = false;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(milliseconds: 500), (_) => poll());
  }

  Future<void> poll() async {
    if (polling || busy || !started) return;
    polling = true;
    try {
      final status = await widget.repository.pairingStatus();
      if (mounted) setState(() => pairing = status);
    } catch (_) {
      /* Actions show failures; polling must not create error loops. */
    } finally {
      polling = false;
    }
  }

  Future<void> run(Future<void> Function() action) async {
    setState(() {
      busy = true;
      error = null;
      started = true;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Pairing failed. Enable NFC, keep both phones unlocked, and start again. Try reversing Read/Receive roles.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await poll();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(widget.repository.stopPairing().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    name.dispose();
    unawaited(widget.repository.stopPairing().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = pairing?['state'];
    final active = state == 'waiting' || state == 'confirm';
    return Scaffold(
      appBar: AppBar(title: const Text('Add contact by NFC')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Choose Receive contact on one phone and Read contact on the other. Keep both apps open and phones unlocked. Hold the NFC areas together while comparing and confirming the code.',
          ),
          TextField(
            controller: name,
            maxLength: 32,
            enabled: !active && !busy,
            decoration: const InputDecoration(
              labelText: 'Your name for this contact',
            ),
          ),
          FilledButton(
            onPressed: busy || active
                ? null
                : () => run(
                    () => widget.repository.startPairing(
                      name.text.trim(),
                      reader: false,
                    ),
                  ),
            child: const Text('Receive contact'),
          ),
          OutlinedButton(
            onPressed: busy || active
                ? null
                : () => run(
                    () => widget.repository.startPairing(
                      name.text.trim(),
                      reader: true,
                    ),
                  ),
            child: const Text('Read contact'),
          ),
          if (state == 'waiting')
            const Text(
              'Ready. Hold the phones together. Pairing expires after 60 seconds.',
            ),
          if (state == 'confirm') ...[
            Text('Contact: ${pairing!['name']}'),
            const Text(
              'Compare this code on both phones. Confirm only if the full code matches.',
            ),
            SelectableText(
              pairing!['code'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            FilledButton(
              onPressed: busy || pairing!['approved'] == true
                  ? null
                  : () => run(widget.repository.approvePairing),
              child: Text(
                pairing!['approved'] == true
                    ? 'Waiting for the other confirmation'
                    : 'Codes match — confirm contact',
              ),
            ),
          ],
          if (state == 'verified')
            const Text(
              'Contact saved and verified on this phone. Check the other phone also shows success before separating them.',
            ),
          if (pairing?['error'] != null) Text(pairing!['error'] as String),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (active)
            TextButton(
              onPressed: busy ? null : () => run(widget.repository.stopPairing),
              child: const Text('Cancel pairing'),
            ),
        ],
      ),
    );
  }
}

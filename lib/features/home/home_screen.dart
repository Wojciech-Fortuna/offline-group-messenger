import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../invitations/scan_invitation_screen.dart';
import '../invitations/nfc_invitation_screen.dart';
import '../../core/messaging/tcp_message_transport.dart';
import '../chat/chat_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.connectivity});
  final OfflineConnectivity connectivity;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  ConnectionCapabilities? _capabilities;
  GroupConnectionState _connection = const GroupConnectionState();
  StreamSubscription<GroupConnectionState>? _subscription;
  bool _loading = true;
  bool _running = false;
  String? _error;
  bool _capabilityError = false;
  GroupInvitation? _invitation;
  int _groupEpoch = 0;
  final _chat = TcpMessageTransport();
  final _displayName = TextEditingController(text: 'Guest');
  String? _chatConnection;

  void _syncChat({bool retry = false}) {
    final address = _connection.hostAddress;
    final connected =
        _connection.status == GroupStatus.connected && address != null;
    final key = connected ? '${_connection.isHost}:$address' : null;
    if (!retry && key == _chatConnection) return;
    _chatConnection = key;
    if (!connected) {
      unawaited(_chat.close());
      return;
    }
    _chat.displayName = _displayName.text;
    if (_connection.isHost) {
      unawaited(
        _chat.startHost(
          port: TcpMessageTransport.defaultPort,
          address: address,
        ),
      );
    } else {
      unawaited(
        _chat.connect(host: address, port: TcpMessageTransport.defaultPort),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _capabilityError = false;
    });
    try {
      final capabilities = await widget.connectivity.getCapabilities();
      if (!mounted) return;
      await _subscription?.cancel();
      if (!mounted) return;
      _capabilities = capabilities;
      if (capabilities.implementationReady &&
          capabilities.wifiDirectSupported) {
        _subscription = widget.connectivity.states.listen(
          (state) {
            if (mounted) {
              setState(() {
                _connection = state;
                if (state.status != GroupStatus.connected || !state.isHost) {
                  _invitation = null;
                  _groupEpoch++;
                }
                _error = state.errorMessage;
              });
              _syncChat();
            }
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _error = 'Connection updates failed. Retry the support check.';
              });
            }
          },
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _capabilityError = true;
          _error = 'Could not check device support.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _running = true;
      _error = null;
    });
    try {
      await action();
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message ?? 'Connection request failed.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Connection request failed. Please retry.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _disconnect() async {
    if (_connection.isHost && _connection.status == GroupStatus.connected) {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('End this group?'),
          content: const Text(
            'Everyone will lose their connection to this host.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Stay'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('End group'),
            ),
          ],
        ),
      );
      if (leave != true || !mounted) return;
    }
    await _run(widget.connectivity.disconnect);
  }

  Future<void> _showInvitation() => _run(() async {
    final epoch = _groupEpoch;
    final invitation = await widget.connectivity.getInvitation();
    if (mounted &&
        epoch == _groupEpoch &&
        _connection.status == GroupStatus.connected &&
        _connection.isHost) {
      setState(() {
        _invitation = invitation;
      });
    }
  });

  Future<void> _scanInvitation() async {
    final invitation = await Navigator.of(context).push<GroupInvitation>(
      MaterialPageRoute(builder: (_) => const ScanInvitationScreen()),
    );
    await _confirmInvitation(invitation);
  }

  Future<void> _nfcInvitation({required bool sharing}) async {
    final invitation = await Navigator.of(context).push<GroupInvitation>(
      MaterialPageRoute(
        builder: (_) => NfcInvitationScreen(
          connectivity: widget.connectivity,
          sharing: sharing,
        ),
      ),
    );
    if (!sharing) await _confirmInvitation(invitation);
  }

  Future<void> _confirmInvitation(GroupInvitation? invitation) async {
    if (invitation == null || !mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join this group?'),
        content: Text(
          'Connect to ${invitation.networkName}? Keep the host nearby with its group open.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await _run(() => widget.connectivity.joinInvitation(invitation));
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _chat.dispose();
    _displayName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready =
        !_loading &&
        !_capabilityError &&
        (_capabilities?.implementationReady ?? false) &&
        (_capabilities?.wifiDirectSupported ?? false);
    final occupied = {
      GroupStatus.connecting,
      GroupStatus.connected,
      GroupStatus.disconnecting,
    }.contains(_connection.status);
    final canStart = ready && !_running && !occupied;
    final statusText = switch (_connection.status) {
      GroupStatus.idle => 'Not connected',
      GroupStatus.discovering => 'Searching for nearby devices',
      GroupStatus.connecting => 'Connecting — accept any system invitation',
      GroupStatus.connected =>
        _connection.isHost
            ? 'Connected · You are the host'
            : 'Connected · Participant',
      GroupStatus.disconnecting => 'Disconnecting',
      GroupStatus.unavailable => 'Wi-Fi Direct unavailable',
    };
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Group Messenger')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Connect your group',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Create a group on one Android phone. Others can scan its QR invitation or find the host nearby.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _displayName,
                  enabled: !occupied && !_running,
                  maxLength: 32,
                  decoration: const InputDecoration(
                    labelText: 'Your chat name',
                  ),
                ),
                if (_connection.status == GroupStatus.connected)
                  ListenableBuilder(
                    listenable: _chat,
                    builder: (context, _) => OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: Text(
                        _chat.status == ChatStatus.ready
                            ? 'Open chat'
                            : 'Open chat / connection status',
                      ),
                      onPressed: () => Navigator.of(context).push<void>(
                        MaterialPageRoute(
                          builder: (_) => ChatScreen(
                            chat: _chat,
                            retry: () => _syncChat(retry: true),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (ready &&
                    _connection.status == GroupStatus.connected &&
                    _connection.isHost) ...[
                  if (_capabilities?.canShareNfc ?? false)
                    OutlinedButton.icon(
                      onPressed: _running
                          ? null
                          : () => _nfcInvitation(sharing: true),
                      icon: const Icon(Icons.nfc),
                      label: const Text('Share via NFC'),
                    ),
                  OutlinedButton.icon(
                    onPressed: _running ? null : _showInvitation,
                    icon: const Icon(Icons.qr_code),
                    label: const Text('Show group QR code'),
                  ),
                  if (_invitation != null) ...[
                    const SizedBox(height: 12),
                    Center(
                      child: Semantics(
                        label: 'Group invitation QR code',
                        child: ExcludeSemantics(
                          child: QrImageView(
                            data: _invitation!.encode(),
                            size: 240,
                            padding: const EdgeInsets.all(16),
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Text(
                      'Only show this code to people joining your group. It contains the Wi-Fi password.',
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _invitation = null;
                      }),
                      child: const Text('Hide QR code'),
                    ),
                  ],
                  const SizedBox(height: 12),
                ],
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          ready ? statusText : 'Device support',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_loading)
                          const Text('Checking device support...')
                        else if (_capabilities != null)
                          Text(_capabilities!.description),
                        if (ready) ...[
                          const SizedBox(height: 8),
                          Text(
                            _connection.wifiEnabled
                                ? 'Wi-Fi enabled'
                                : 'Enable Wi-Fi in system settings.',
                          ),
                          if (!_connection.permissionGranted)
                            const Text(
                              'Your first action will ask for Nearby devices or Location permission.',
                            ),
                          if (_connection.status == GroupStatus.connected &&
                              _connection.hostAddress != null)
                            SelectableText(
                              'Host IP: ${_connection.hostAddress}',
                            ),
                        ],
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _running ? null : _load,
                            child: const Text('Try again'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: canStart
                      ? () => _run(widget.connectivity.createGroup)
                      : null,
                  child: const Text('Create a group'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: canStart
                      ? () => _run(widget.connectivity.discoverPeers)
                      : null,
                  child: const Text('Find nearby devices'),
                ),
                if (ready && (_capabilities?.canJoinQr ?? false))
                  OutlinedButton.icon(
                    onPressed: canStart ? _scanInvitation : null,
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('Scan group QR code'),
                  ),
                if (ready && (_capabilities?.canJoinNfc ?? false))
                  OutlinedButton.icon(
                    onPressed: canStart
                        ? () => _nfcInvitation(sharing: false)
                        : null,
                    icon: const Icon(Icons.nfc),
                    label: const Text('Join via NFC'),
                  ),
                if (ready && !(_capabilities?.canJoinQr ?? false))
                  const Text(
                    'QR joining requires Android 10+. Use nearby-device discovery on this phone.',
                  ),
                if (ready)
                  TextButton(
                    onPressed: _running ? null : _disconnect,
                    child: Text(
                      _connection.status == GroupStatus.connected
                          ? 'Disconnect'
                          : 'Cancel / stop discovery',
                    ),
                  ),
                if (_running)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  ),
                if (ready && !occupied) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Nearby devices',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (_connection.peers.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'No devices listed. Enable Wi-Fi and Location, then search. Keep the host nearby.',
                      ),
                    ),
                  for (final peer in _connection.peers)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        peer.name.isEmpty ? 'Nearby device' : peer.name,
                      ),
                      subtitle: Text(
                        peer.isGroupOwner
                            ? 'Group host'
                            : 'Nearby Wi-Fi Direct device',
                      ),
                      trailing: TextButton(
                        onPressed: canStart
                            ? () => _run(
                                () => widget.connectivity.joinGroup(peer.id),
                              )
                            : null,
                        child: const Text('Join'),
                      ),
                    ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Offline text chat is available after connecting. '
                  'Nearby devices may include phones that are not running this app.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

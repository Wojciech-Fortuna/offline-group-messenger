import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:offline_audio/offline_audio.dart';
import '../contacts/contact_repository.dart';
import '../messaging/tcp_message_transport.dart';

class VerifiedCallPeer {
  VerifiedCallPeer(this.contact, this.peer, this.nonce, this.sequence);
  final String contact;
  final String peer;
  final String nonce;
  int sequence;
}

typedef MediaFactory =
    LocalAudioSession Function(
      Future<void> Function(Map<String, dynamic>),
      void Function(String),
      void Function(String),
    );

/// Foreground call ownership is separate from chat/network ownership.
class CallController extends ChangeNotifier {
  CallController(
    this.transport, {
    this.contacts = const ContactRepository(),
    Future<P2pNetwork> Function()? network,
    MediaFactory? mediaFactory,
  }) : _network = network ?? readP2pNetwork,
       _mediaFactory =
           mediaFactory ??
           ((signal, state, error) => LocalAudioSession(
             onSignal: signal,
             onState: state,
             onError: error,
           )) {
    transport.addListener(_synchronize);
    _subscription = transport.callFrames.listen(_queue);
    unawaited(refreshContacts());
  }
  final TcpMessageTransport transport;
  final ContactRepository contacts;
  final Future<P2pNetwork> Function() _network;
  final MediaFactory _mediaFactory;
  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final _localNonces = <String, String>{};
  final _verified = <String, VerifiedCallPeer>{};
  final _helloReplies = <String, DateTime>{};
  final _retiredNonces = <String, Set<String>>{};
  final _probing = <String>{};
  Timer? _presenceTimer;
  Map<String, SavedContact> saved = {};
  String? identity;
  String? _networkKey;
  int _generation = 0;
  int _sequence = 0;
  int _queued = 0;
  int _sending = 0;
  bool _disposed = false;
  bool _foreground = true;
  Future<void> _incoming = Future.value();
  Future<void> _outgoing = Future.value();
  String? callId;
  String? contactId;
  String? _peer;
  bool _caller = false;
  String state = 'idle';
  String? error;
  DateTime? connectedAt;
  int _endedDuration = 0;
  Timer? _deadline;
  Timer? _clock;
  LocalAudioSession? _media;
  bool get hasCall => callId != null;
  bool get muted => _media?.muted ?? false;
  bool get speaker => _media?.speaker ?? false;
  String get contactName => saved[contactId]?.name ?? 'Contact';
  int get duration => connectedAt == null
      ? 0
      : hasCall
      ? DateTime.now().difference(connectedAt!).inSeconds
      : _endedDuration;
  static String _random() => List.generate(
    32,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refreshContacts() async {
    try {
      final snapshot = await contacts.load();
      if (_disposed) return;
      final next = {
        for (final c in snapshot.contacts)
          if (c.trust == ContactTrust.verified) c.id: c,
      };
      final changed =
          identity != snapshot.identity ||
          !setEquals(saved.keys.toSet(), next.keys.toSet());
      identity = snapshot.identity;
      saved = next;
      if (contactId != null && !saved.containsKey(contactId)) {
        await end('Contact trust removed');
      }
      if (changed) {
        _networkKey = null;
      }
      _synchronize();
      _changed();
    } catch (_) {
      if (!_disposed) {
        saved = {};
        _networkKey = null;
        _synchronize();
        error = 'Contacts are unavailable';
        _changed();
      }
    }
  }

  bool _topology(String peer) => transport.isHost || transport.hostId == peer;
  VerifiedCallPeer? peerFor(String contact) {
    for (final value in _verified.values) {
      if (value.contact == contact && _topology(value.peer)) return value;
    }
    return null;
  }

  String availability(String contact) => peerFor(contact) != null
      ? 'Connected — ready to call'
      : transport.status != ChatStatus.ready
      ? 'Join the same group to call'
      : 'Not verified online, or this call topology is not supported yet';

  void _synchronize() {
    if (_disposed) return;
    final key =
        _foreground &&
            identity != null &&
            saved.isNotEmpty &&
            transport.status == ChatStatus.ready &&
            transport.supportsCalls
        ? '${transport.groupId}/${transport.connectionRevision}'
        : null;
    if (key != _networkKey || (key == null && _localNonces.isNotEmpty)) {
      _generation++;
      _networkKey = key;
      _localNonces.clear();
      _verified.clear();
      _helloReplies.clear();
      _retiredNonces.clear();
      if (hasCall) unawaited(end('Connection changed', signal: false));
    }
    if (key == null) {
      _presenceTimer?.cancel();
      _presenceTimer = null;
      return;
    }
    _presenceTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      if (_foreground) {
        for (final peer in _localNonces.keys.toList()) {
          if (!_verified.containsKey(peer)) {
            unawaited(_probe(peer, _generation));
          }
        }
      }
    });
    final peers = transport.participants
        .where((p) => p.id != transport.selfId && p.canCall)
        .map((p) => p.id)
        .toSet();
    for (final peer in _localNonces.keys.toList()) {
      if (!peers.contains(peer)) {
        _localNonces.remove(peer);
        _verified.remove(peer);
        _retiredNonces.remove(peer);
        if (_peer == peer) {
          unawaited(end('Contact disconnected', signal: false));
        }
      }
    }
    for (final peer in peers) {
      if (_localNonces.containsKey(peer)) continue;
      _localNonces[peer] = _random();
      unawaited(_probe(peer, _generation));
    }
    _changed();
  }

  Future<void> _probe(String peer, int generation) async {
    final probe = '$generation/$peer';
    if (!_probing.add(probe)) return;
    try {
      for (final contact in saved.keys.toList()) {
        if (_generation != generation || !_localNonces.containsKey(peer)) {
          return;
        }
        try {
          await _send(contact, peer, 'hello');
        } catch (_) {
          return;
        }
      }
    } finally {
      _probing.remove(probe);
    }
  }

  Future<void> _send(
    String contact,
    String peer,
    String kind, {
    String? call,
    String? echo,
    Map<String, dynamic> data = const {},
  }) {
    if (_disposed ||
        _networkKey == null ||
        _sending >= 64 ||
        !_localNonces.containsKey(peer)) {
      return Future.error(StateError('Call signaling unavailable'));
    }
    final generation = _generation;
    final nonce = _localNonces[peer];
    final body = <String, dynamic>{
      'to': contact,
      'group': transport.groupId,
      'source': transport.selfId,
      'target': peer,
      'nonce': nonce,
      'echo': echo ?? _verified[peer]?.nonce ?? '',
      'seq': ++_sequence,
      'call': call ?? '',
      'kind': kind,
      'data': data,
    };
    _sending++;
    final work = _outgoing.then((_) async {
      if (generation != _generation ||
          nonce != _localNonces[peer] ||
          _disposed) {
        throw StateError('Connection changed');
      }
      final token = await contacts
          .signCall(body)
          .timeout(const Duration(seconds: 8));
      if (['invite', 'ringing', 'accepted', 'media'].contains(kind) &&
          callId != call) {
        throw StateError('Call ended before signaling completed');
      }
      if (generation != _generation ||
          nonce != _localNonces[peer] ||
          _disposed) {
        throw StateError('Connection changed');
      }
      transport.sendCall(peer, token);
    });
    _outgoing = work.catchError((Object _) {}).whenComplete(() => _sending--);
    return work;
  }

  void _queue(Map<String, dynamic> frame) {
    if (_disposed || !_foreground || _queued >= 64) return;
    _queued++;
    final generation = _generation;
    _incoming = _incoming
        .then((_) async {
          if (generation == _generation && !_disposed) {
            await _receive(frame, generation);
          }
        })
        .catchError((Object _) {
          /* Invalid or unauthenticated frames never ring. */
        })
        .whenComplete(() => _queued--);
  }

  Future<void> _receive(Map<String, dynamic> frame, int generation) async {
    final peer = frame['from'] as String;
    final challenge = _localNonces[peer];
    if (challenge == null) return;
    final body = await contacts
        .verifyCall(frame['token'] as String)
        .timeout(const Duration(seconds: 8));
    if (!_foreground ||
        generation != _generation ||
        _disposed ||
        _localNonces[peer] != challenge) {
      return;
    }
    final contact = body['from'];
    final kind = body['kind'];
    final nonce = body['nonce'];
    final seq = body['seq'];
    if (!saved.containsKey(contact) ||
        body['to'] != identity ||
        body['group'] != transport.groupId ||
        body['source'] != peer ||
        body['target'] != transport.selfId ||
        nonce is! String ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(nonce) ||
        seq is! int ||
        seq < 1 ||
        seq > 9007199254740991) {
      return;
    }
    if (kind == 'hello') {
      if (_retiredNonces[peer]?.contains(nonce) == true) return;
      final rateKey = '$peer/$contact';
      final previous = _helloReplies[rateKey];
      if (previous != null &&
          DateTime.now().difference(previous).inMilliseconds < 500) {
        return;
      }
      _helloReplies[rateKey] = DateTime.now();
      final previousBinding = _verified[peer];
      if (previousBinding != null && previousBinding.nonce != nonce) {
        final retired = _retiredNonces.putIfAbsent(peer, () => <String>{});
        if (retired.length >= 128) return;
        retired.add(previousBinding.nonce);
        _verified.remove(peer);
        _localNonces[peer] = _random();
        if (_peer == peer) {
          await end('Contact restarted call availability', signal: false);
        }
      }
      await _send(contact as String, peer, 'helloAck', echo: nonce);
      return;
    }
    if (body['echo'] != challenge) return;
    final binding = _verified[peer];
    if (binding != null &&
        (binding.contact != contact ||
            binding.nonce != nonce ||
            seq <= binding.sequence)) {
      return;
    }
    if (kind == 'helloAck' || kind == 'ready') {
      _verified[peer] = VerifiedCallPeer(contact as String, peer, nonce, seq);
      if (kind == 'helloAck') await _send(contact, peer, 'ready');
      _changed();
      return;
    }
    if (binding == null) return;
    binding.sequence = seq;
    final call = body['call'];
    if (call is! String || !RegExp(r'^[a-f0-9]{64}$').hasMatch(call)) return;
    final data = Map<String, dynamic>.from(body['data'] as Map);
    if (kind == 'invite') {
      if (!_topology(peer)) {
        await _send(contact as String, peer, 'busy', call: call);
        return;
      }
      if (hasCall) {
        if (_caller &&
            contactId == contact &&
            state == 'outgoing' &&
            identity!.compareTo(contact as String) > 0) {
          await end('Simultaneous call resolved', kind: 'cancel');
        } else {
          await _send(contact as String, peer, 'busy', call: call);
          return;
        }
      }
      _begin(contact as String, peer, call, caller: false);
      await _send(contact, peer, 'ringing', call: call);
      return;
    }
    if (call != callId || peer != _peer || contact != contactId) return;
    switch (kind) {
      case 'ringing':
        if (_caller && state == 'outgoing') {
          state = 'ringing';
          _changed();
        }
      case 'accepted':
        if (_caller && (state == 'outgoing' || state == 'ringing')) {
          state = 'connecting';
          _deadline?.cancel();
          _changed();
          await _startMedia(call, initiator: true);
        }
      case 'media':
        if (_media != null &&
            ['connecting', 'active', 'reconnecting'].contains(state)) {
          try {
            // The call role fixes which side may supply an offer vs answer.
            if (data['kind'] == (_caller ? 'offer' : 'answer')) return;
            await _media!.receive(data);
          } catch (_) {
            if (callId == call) await end('Media setup failed');
          }
        }
      case 'declined':
      case 'busy':
      case 'cancel':
      case 'end':
      case 'timeout':
        await end(switch (kind) {
          'declined' => 'Call declined',
          'busy' => 'Contact is busy',
          'cancel' => 'Call cancelled',
          'timeout' => 'Call timed out',
          _ => 'Call ended',
        }, signal: false);
    }
  }

  void _begin(
    String contact,
    String peer,
    String call, {
    required bool caller,
  }) {
    callId = call;
    contactId = contact;
    _peer = peer;
    _caller = caller;
    state = caller ? 'outgoing' : 'incoming';
    error = null;
    connectedAt = null;
    _endedDuration = 0;
    _deadline?.cancel();
    _deadline = Timer(const Duration(seconds: 40), () {
      if (callId == call) unawaited(end('No answer', kind: 'timeout'));
    });
    _changed();
  }

  Future<void> dial(String contact) async {
    if (hasCall || !_foreground) return;
    final target = peerFor(contact);
    if (target == null) {
      error = 'Contact is not available in this group';
      _changed();
      return;
    }
    final call = _random();
    _begin(contact, target.peer, call, caller: true);
    try {
      await _send(contact, target.peer, 'invite', call: call);
    } catch (_) {
      if (callId == call) {
        await end('Could not send call request', signal: false);
      }
    }
  }

  Future<void> answer() async {
    final call = callId;
    if (call == null || state != 'incoming') return;
    state = 'connecting';
    _deadline?.cancel();
    _changed();
    await _startMedia(call, initiator: false);
    if (callId == call) {
      try {
        await _send(contactId!, _peer!, 'accepted', call: call);
      } catch (_) {
        if (callId == call) await end('Could not accept call', signal: false);
      }
    }
  }

  Future<void> _startMedia(String call, {required bool initiator}) async {
    try {
      final network = await _network().timeout(const Duration(seconds: 8));
      if (callId != call || !_foreground) return;
      final media = _mediaFactory(
        (message) async {
          if (callId != call) throw StateError('Call ended');
          await _send(contactId!, _peer!, 'media', call: call, data: message);
        },
        (next) {
          if (callId != call) return;
          state = next;
          if (next == 'active') {
            connectedAt ??= DateTime.now();
            _clock ??= Timer.periodic(
              const Duration(seconds: 1),
              (_) => _changed(),
            );
          }
          _changed();
        },
        (reason) {
          if (callId == call) unawaited(end(reason));
        },
      );
      _media = media;
      await media.start(network, initiator: initiator);
    } catch (_) {
      if (callId == call) {
        await end(
          'Could not start audio. Check microphone permission and Wi-Fi Direct.',
        );
      }
    }
  }

  Future<void> end(
    String reason, {
    bool signal = true,
    String kind = 'end',
  }) async {
    final call = callId;
    final contact = contactId;
    final peer = _peer;
    _endedDuration = duration;
    callId = null;
    _peer = null;
    _deadline?.cancel();
    _deadline = null;
    _clock?.cancel();
    _clock = null;
    final media = _media;
    _media = null;
    if (call != null) {
      state = 'ended';
      error = reason;
      _changed();
    }
    if (signal && call != null && contact != null && peer != null) {
      final sent = _send(
        contact,
        peer,
        kind,
        call: call,
      ).catchError((Object _) {});
      await Future.wait([
        sent.timeout(const Duration(seconds: 2), onTimeout: () {}),
        if (media != null) media.close(),
      ]);
      return;
    }
    await media?.close();
  }

  void toggleMute() {
    _media?.setMuted(!muted);
    _changed();
  }

  Future<void> toggleSpeaker() async {
    try {
      await _media?.setSpeaker(!speaker);
    } catch (_) {
      error = 'Audio route unavailable';
    }
    _changed();
  }

  void foreground(bool value) {
    _foreground = value;
    if (!value) {
      unawaited(
        end(
          'Call stopped when app left the foreground',
        ).whenComplete(_synchronize),
      );
      return;
    }
    _synchronize();
    if (value) unawaited(refreshContacts());
  }

  @override
  void dispose() {
    _disposed = true;
    _presenceTimer?.cancel();
    _generation++;
    transport.removeListener(_synchronize);
    unawaited(_subscription.cancel());
    unawaited(end('Closed', signal: false));
    super.dispose();
  }
}

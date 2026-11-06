import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

import '../models/chat_message.dart';
import '../models/message_delivery.dart';
import '../models/participant.dart';
import 'tcp_message_transport.dart';

enum DeliveryState { pending, confirmed, failed }

class SessionMessage {
  SessionMessage(this.message, this.delivery, {this.failure});
  final ChatMessage message;
  DeliveryState delivery;
  String? failure;
}

/// Conversation/UI state outlives sockets and navigation. All storage is in memory.
class ChatSessionController extends ChangeNotifier {
  ChatSessionController({TcpMessageTransport? transport})
    : transport = transport ?? TcpMessageTransport() {
    this.transport.addListener(_changed);
    _incoming = this.transport.incoming.listen(_receive);
  }

  final TcpMessageTransport transport;
  late final StreamSubscription<ChatMessage> _incoming;
  final _history = <ChatMessage>[];
  final _outbox = <String, SessionMessage>{};
  GroupConnectionState _connection = const GroupConnectionState();
  String? _connectionKey;
  bool? _sessionRole;
  ChatMessage? _draftRequest;
  bool _left = false;
  bool _roleChanged = false;
  bool _disposed = false;
  int _generation = 0;
  String draft = '';
  String? sendError;
  String? _configurationError;
  GroupInvitation? _joinCandidate;
  GroupInvitation? _rememberedPrivateGroup;
  bool _removingMember = false;

  ChatStatus get status => transport.status;
  String? get selfId => transport.selfId;
  String? get error => _configurationError ?? transport.error;
  String? get historyWarning => transport.historyWarning;
  bool get sessionEnded => _roleChanged || transport.sessionEnded;
  bool get hasConversation => transport.groupId != null || _history.isNotEmpty;
  bool get sending =>
      _outbox.values.any((e) => e.delivery == DeliveryState.pending);
  bool get networkConnected =>
      _connection.status == GroupStatus.connected &&
      _connection.hostAddress != null;
  List<Participant> get participants => transport.participants;
  List<Participant> get members => transport.members;
  bool get canManagePrivateMembers => transport.canManagePrivateMembers;
  bool get removingMember => _removingMember;
  GroupInvitation? get rememberedPrivateGroup => _rememberedPrivateGroup;
  MessageDelivery? deliveryFor(String messageId) =>
      transport.deliveryFor(messageId);
  List<SessionMessage> get messages => [
    for (final message in _history)
      SessionMessage(message, DeliveryState.confirmed),
    ..._outbox.values,
  ];

  void _changed() {
    if (sessionEnded) {
      _rememberedPrivateGroup = null;
      _joinCandidate = null;
    } else if (transport.status == ChatStatus.ready && _joinCandidate != null) {
      _rememberedPrivateGroup = _joinCandidate!.privateGroup
          ? _joinCandidate
          : null;
      _joinCandidate = null;
    }
    if (!_disposed) notifyListeners();
  }

  void _receive(ChatMessage message) {
    if (_disposed || message.groupId != transport.groupId) return;
    _outbox.remove(message.id);
    if (!_history.any((m) => m.id == message.id)) {
      final index = message.sequence == 0
          ? -1
          : _history.indexWhere((m) => m.sequence > message.sequence);
      if (index < 0) {
        _history.add(message);
      } else {
        _history.insert(index, message);
      }
      if (_history.length > TcpMessageTransport.historyLimit) {
        _history.removeAt(0);
      }
    }
    final request = _draftRequest;
    if (request != null && '${request.senderId}:${request.id}' == message.id) {
      if (draft.trim() == request.text) draft = '';
      _draftRequest = null;
      sendError = null;
    }
    _changed();
  }

  /// Native loss suspends clients; the next connected snapshot resumes them.
  void updateConnection(
    GroupConnectionState connection, {
    required String displayName,
  }) {
    _connection = connection;
    transport.displayName = displayName;
    final key = networkConnected
        ? '${connection.isHost}:${connection.hostAddress}'
        : null;
    if (key == _connectionKey) return;
    final previousKey = _connectionKey;
    _connectionKey = key;
    if (key != null && previousKey != null) {
      // Cancel a handshake/socket for an obsolete address before starting another.
      unawaited(transport.close());
    }
    if (key == null) {
      unawaited(transport.close());
    } else if (!sessionEnded && !_left) {
      if (transport.groupId != null && _sessionRole != connection.isHost) {
        // A native role change does not migrate a conversation to a new host.
        _left = true;
        _roleChanged = true;
        unawaited(transport.close());
      } else {
        _sessionRole = connection.isHost;
        retry();
      }
    }
    _changed();
  }

  void retry() {
    if (!networkConnected ||
        _left ||
        sessionEnded ||
        status == ChatStatus.connecting) {
      return;
    }
    if (_connection.isHost) {
      if (_connection.privateGroup && transport.hostAdmissionToken == null) {
        _configurationError =
            'Private group credentials are unavailable. End this group and create it again.';
        _changed();
        return;
      }
      // A host whose listener existed must start a new session explicitly.
      if (transport.groupId != null) return;
      unawaited(
        transport.startHost(
          port: TcpMessageTransport.defaultPort,
          address: _connection.hostAddress!,
        ),
      );
    } else {
      unawaited(
        transport.connect(
          host: _connection.hostAddress!,
          port: TcpMessageTransport.defaultPort,
        ),
      );
    }
  }

  /// Explicit user action; never invoked as a side effect of reconnecting.
  void beginNewSession() {
    _generation++;
    _history.clear();
    _outbox.clear();
    draft = '';
    _draftRequest = null;
    sendError = null;
    _configurationError = null;
    _joinCandidate = null;
    _rememberedPrivateGroup = null;
    _left = false;
    _roleChanged = false;
    _connectionKey = null;
    _sessionRole = null;
    transport.resetSession();
    _changed();
  }

  /// Called before creating the native group. Private admission stays out of discovery.
  String? configureGroup({required bool privateGroup}) {
    beginNewSession();
    transport.hostAdmissionToken = privateGroup ? _newAdmissionToken() : null;
    transport.invitationToken = null;
    return transport.hostAdmissionToken;
  }

  void prepareJoin({GroupInvitation? invitation}) {
    if (sessionEnded) {
      beginNewSession();
    } else {
      resumeJoining();
    }
    transport.invitationToken = invitation?.admissionToken;
    _joinCandidate = invitation;
    transport.hostAdmissionToken = null;
  }

  static String _newAdmissionToken() {
    final random = Random.secure();
    return List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  Future<void> removePrivateMember(
    String participantId, {
    required Future<void> Function(String previous, String next)
    rotateInvitation,
  }) async {
    if (_removingMember || !transport.canRemoveMember(participantId)) {
      throw StateError('This private member cannot be removed now.');
    }
    final generation = _generation;
    final group = transport.groupId;
    final previous = transport.hostAdmissionToken!;
    final next = _newAdmissionToken();
    _removingMember = true;
    _changed();
    try {
      await rotateInvitation(previous, next);
      if (_disposed ||
          generation != _generation ||
          group != transport.groupId ||
          transport.hostAdmissionToken != previous ||
          !transport.canRemoveMember(participantId)) {
        throw StateError('The group changed while removing this member.');
      }
      transport.removePrivateMember(participantId, newAdmissionToken: next);
    } finally {
      _removingMember = false;
      _changed();
    }
  }

  void startNewChat() {
    beginNewSession();
    _sessionRole = _connection.isHost;
    _connectionKey = networkConnected
        ? '${_connection.isHost}:${_connection.hostAddress}'
        : null;
    retry();
  }

  Future<void> leave() async {
    _left = true;
    await transport.close();
    _changed();
  }

  /// User chose to rejoin. Preserve the session; the host validates its identity.
  void resumeJoining() {
    _left = false;
    _connectionKey = null;
    _changed();
  }

  Future<void> sendDraft() async {
    if (draft.trim().isEmpty ||
        sending ||
        status != ChatStatus.ready ||
        sessionEnded) {
      return;
    }
    var request = _draftRequest;
    if (request == null || request.text != draft.trim()) {
      if (_outbox.length >= 50) {
        sendError =
            'Too many unconfirmed messages. Retry existing messages first.';
        _changed();
        return;
      }
      request = transport.createMessage(draft);
      _draftRequest = request;
    }
    final id = '${request.senderId}:${request.id}';
    final entry = _outbox.putIfAbsent(
      id,
      () => SessionMessage(request!, DeliveryState.pending),
    );
    await _attempt(id, entry);
  }

  Future<void> retryMessage(String id) async {
    final entry = _outbox[id];
    if (entry == null ||
        sending ||
        status != ChatStatus.ready ||
        sessionEnded) {
      return;
    }
    await _attempt(id, entry);
  }

  Future<void> _attempt(String id, SessionMessage entry) async {
    final generation = _generation;
    entry.delivery = DeliveryState.pending;
    entry.failure = null;
    sendError = null;
    _changed();
    try {
      await transport.send(entry.message);
      if (_disposed || generation != _generation) return;
      entry.delivery = DeliveryState.confirmed;
    } catch (e) {
      if (_disposed || generation != _generation || !_outbox.containsKey(id)) {
        return;
      }
      entry.delivery = DeliveryState.failed;
      entry.failure = e is StateError
          ? e.message.toString()
          : 'Host confirmation not received. Retry this message after reconnecting.';
      sendError = entry.failure;
    }
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _incoming.cancel();
    transport.removeListener(_changed);
    transport.dispose();
    super.dispose();
  }
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';
import '../models/participant.dart';
import 'message_transport.dart';

enum ChatStatus { offline, connecting, ready }

/// Foreground-only, plaintext prototype. The host is the message authority.
class TcpMessageTransport extends ChangeNotifier implements MessageTransport {
  static const defaultPort = 45871;
  static const maxTextLength = 2000;
  static const maxFrameBytes = 32768;
  final _incoming = StreamController<ChatMessage>.broadcast();
  final _messages = <ChatMessage>[];
  final _participants = <Participant>[];
  final _peers = <Socket, Participant?>{};
  final _pending = <String, Completer<void>>{};
  final _seen = <String>{};
  ServerSocket? _server;
  Socket? _host;
  Timer? _heartbeat;
  int _epoch = 0;
  bool _disposed = false;
  bool _isHost = false;
  String displayName = 'Guest';
  String? selfId;
  String? _groupId;
  String? error;
  ChatStatus status = ChatStatus.offline;
  int? get listeningPort => _server?.port;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  List<Participant> get participants => List.unmodifiable(_participants);
  @override
  Stream<ChatMessage> get incoming => _incoming.stream;

  static String _id() => List.generate(
    16,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _reset() {
    _stop();
    _messages.clear();
    _seen.clear();
    selfId = null;
    _groupId = null;
    error = null;
    status = ChatStatus.connecting;
    _notify();
  }

  @override
  Future<void> startHost({
    required int port,
    String address = '0.0.0.0',
  }) async {
    _reset();
    final epoch = _epoch;
    _isHost = true;
    try {
      final server = await ServerSocket.bind(address, port);
      if (epoch != _epoch) {
        await server.close();
        return;
      }
      _server = server;
      selfId = _id();
      _groupId = _id();
      _participants.add(
        Participant(id: selfId!, displayName: _name(displayName)),
      );
      status = ChatStatus.ready;
      server.listen((socket) {
        if (epoch != _epoch || _peers.length >= 15) {
          socket.destroy();
          return;
        }
        _peers[socket] = null;
        _listen(socket, epoch);
        // A silent socket must not reserve a participant slot indefinitely.
        Future<void>.delayed(const Duration(seconds: 5), () {
          if (epoch == _epoch &&
              _peers.containsKey(socket) &&
              _peers[socket] == null) {
            _lost(socket);
          }
        });
      }, onError: (Object _) => _fail('Chat server stopped. Retry chat.'));
      _startHeartbeat();
      _notify();
    } catch (_) {
      if (epoch == _epoch) _fail('Could not start chat server. Retry chat.');
    }
  }

  @override
  Future<void> connect({required String host, required int port}) async {
    _reset();
    final epoch = _epoch;
    _isHost = false;
    // Wi-Fi can be ready a little before the host has bound its server.
    for (var attempt = 0; attempt < 5 && epoch == _epoch; attempt++) {
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 2),
        );
        if (epoch != _epoch) {
          socket.destroy();
          return;
        }
        _host = socket;
        _listen(socket, epoch);
        _write(socket, {'type': 'hello', 'name': _name(displayName)});
        _startHeartbeat();
        Future<void>.delayed(const Duration(seconds: 5), () {
          if (epoch == _epoch && status == ChatStatus.connecting) {
            _fail('Host did not accept the chat handshake. Retry chat.');
          }
        });
        return;
      } catch (_) {
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      }
    }
    if (epoch == _epoch) {
      _fail('Cannot reach the host chat server. Retry chat.');
    }
  }

  void _startHeartbeat() {
    _heartbeat = Timer.periodic(const Duration(seconds: 10), (_) {
      for (final socket in [..._peers.keys, if (_host != null) _host!]) {
        _write(socket, {'type': 'ping'});
      }
    });
  }

  void _listen(Socket socket, int epoch) {
    final buffer = <int>[];
    socket.done.then<void>(
      (_) {},
      onError: (Object _) {
        if (epoch == _epoch) _lost(socket);
      },
    );
    socket
        .timeout(const Duration(seconds: 35))
        .listen(
          (bytes) {
            if (epoch != _epoch) return;
            try {
              for (final byte in bytes) {
                if (byte == 10) {
                  final frame = jsonDecode(utf8.decode(buffer));
                  buffer.clear();
                  if (frame is! Map<String, dynamic> || frame['v'] != 1) {
                    throw const FormatException('Invalid protocol');
                  }
                  _receive(socket, frame);
                } else {
                  buffer.add(byte);
                  if (buffer.length > maxFrameBytes) {
                    throw const FormatException('Frame too large');
                  }
                }
              }
            } catch (_) {
              _lost(socket);
            }
          },
          onError: (Object _) {
            if (epoch == _epoch) _lost(socket);
          },
          onDone: () {
            if (epoch == _epoch) _lost(socket);
          },
          cancelOnError: true,
        );
  }

  static String _string(Object? value, int max) {
    if (value is! String || value.trim().isEmpty || value.length > max) {
      throw const FormatException('Invalid text field');
    }
    return value;
  }

  static String _name(String value) => value.trim().isEmpty
      ? 'Guest'
      : value.trim().substring(0, min(value.trim().length, 32));

  void _receive(Socket socket, Map<String, dynamic> frame) {
    final type = frame['type'];
    if (type == 'ping') {
      _write(socket, {'type': 'pong'});
      return;
    }
    if (type == 'pong') return;
    if (_isHost) {
      if (!_peers.containsKey(socket)) return;
      final peer = _peers[socket];
      if (type == 'hello' && peer == null) {
        final participant = Participant(
          id: _id(),
          displayName: _string(frame['name'], 32),
        );
        _peers[socket] = participant;
        _participants.add(participant);
        _write(socket, {
          'type': 'welcome',
          'selfId': participant.id,
          'groupId': _groupId,
        });
        _roster('${participant.displayName} joined');
      } else if (type == 'send' && peer != null) {
        _accept(
          peer,
          _string(frame['id'], 64),
          _string(frame['text'], maxTextLength),
        );
      } else {
        throw const FormatException('Unexpected frame');
      }
    } else {
      switch (type) {
        case 'welcome':
          if (selfId != null) throw const FormatException('Duplicate welcome');
          selfId = _string(frame['selfId'], 64);
          _groupId = _string(frame['groupId'], 64);
        case 'roster':
          if (selfId == null) throw const FormatException('Missing welcome');
          final list = frame['participants'];
          if (list is! List || list.length > 16) {
            throw const FormatException('Invalid roster');
          }
          final participants = list
              .map(
                (p) => Participant(
                  id: _string(p['id'], 64),
                  displayName: _string(p['name'], 32),
                ),
              )
              .toList();
          _participants
            ..clear()
            ..addAll(participants);
          status = ChatStatus.ready;
          _notice(_string(frame['notice'], 100));
        case 'message':
          if (status != ChatStatus.ready) {
            throw const FormatException('Not ready');
          }
          final message = ChatMessage(
            id: _string(frame['id'], 130),
            groupId: _groupId!,
            senderId: _string(frame['senderId'], 64),
            senderName: _string(frame['name'], 32),
            text: _string(frame['text'], maxTextLength),
            sentAt: DateTime.parse(_string(frame['time'], 40)),
          );
          _record(message);
          _pending.remove(message.id)?.complete();
        default:
          throw const FormatException('Unknown frame');
      }
    }
  }

  void _accept(Participant sender, String requestId, String text) {
    final id = '${sender.id}:$requestId';
    if (_seen.contains(id)) return;
    final message = ChatMessage(
      id: id,
      groupId: _groupId!,
      senderId: sender.id,
      senderName: sender.displayName,
      text: text,
      sentAt: DateTime.now().toUtc(),
    );
    _record(message);
    _broadcast({
      'type': 'message',
      'id': id,
      'senderId': sender.id,
      'name': sender.displayName,
      'text': text,
      'time': message.sentAt.toIso8601String(),
    });
  }

  void _record(ChatMessage message) {
    if (!_seen.add(message.id)) return;
    if (_seen.length > 1000) _seen.remove(_seen.first);
    _messages.add(message);
    if (_messages.length > 500) _messages.removeAt(0);
    _incoming.add(message);
    _notify();
  }

  void _notice(String text) => _record(
    ChatMessage(
      id: _id(),
      groupId: _groupId ?? '',
      senderId: '',
      senderName: 'Group',
      text: text,
      sentAt: DateTime.now().toUtc(),
    ),
  );

  void _roster(String notice) {
    _broadcast({
      'type': 'roster',
      'participants': [
        for (final p in _participants) {'id': p.id, 'name': p.displayName},
      ],
      'notice': notice,
    });
    _notice(notice);
  }

  void _broadcast(Map<String, Object?> frame) {
    for (final entry in _peers.entries.toList()) {
      if (entry.value != null) _write(entry.key, frame);
    }
  }

  void _write(Socket socket, Map<String, Object?> frame) {
    try {
      socket.add(utf8.encode('${jsonEncode({'v': 1, ...frame})}\n'));
    } catch (_) {
      _lost(socket);
    }
  }

  Future<void> sendText(String text) => send(
    ChatMessage(
      id: _id(),
      groupId: _groupId ?? '',
      senderId: selfId ?? '',
      text: text.trim(),
      sentAt: DateTime.now(),
    ),
  );

  @override
  Future<void> send(ChatMessage message) async {
    if (status != ChatStatus.ready) throw StateError('Chat is disconnected');
    final text = _string(message.text, maxTextLength);
    final requestId = _string(message.id, 64);
    if (_isHost) {
      _accept(_participants.first, requestId, text);
    } else {
      final id = '$selfId:$requestId';
      if (_pending.containsKey(id)) {
        throw StateError('Message is already pending');
      }
      final pending = Completer<void>();
      _pending[id] = pending;
      // Attach the error handler before a synchronous socket failure is possible.
      final acknowledged = pending.future.timeout(const Duration(seconds: 6));
      _write(_host!, {'type': 'send', 'id': requestId, 'text': text});
      try {
        await acknowledged;
      } finally {
        _pending.remove(id);
      }
    }
  }

  void _lost(Socket socket) {
    socket.destroy();
    if (_isHost) {
      final peer = _peers.remove(socket);
      if (peer != null) {
        _participants.removeWhere((p) => p.id == peer.id);
        _roster('${peer.displayName} left');
      }
    } else if (identical(socket, _host)) {
      _fail(
        'Host disconnected or stopped responding. Retry chat or rejoin the group.',
      );
    }
  }

  void _fail(String message) {
    _stop();
    error = message;
    _notify();
  }

  void _stop() {
    _epoch++;
    _heartbeat?.cancel();
    _heartbeat = null;
    _server?.close();
    _server = null;
    _host?.destroy();
    _host = null;
    for (final socket in _peers.keys) {
      socket.destroy();
    }
    _peers.clear();
    _participants.clear();
    for (final pending in _pending.values) {
      pending.completeError(
        StateError('Chat disconnected before host confirmation'),
      );
    }
    _pending.clear();
    status = ChatStatus.offline;
  }

  @override
  Future<void> close() async {
    _stop();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _stop();
    _incoming.close();
    super.dispose();
  }
}

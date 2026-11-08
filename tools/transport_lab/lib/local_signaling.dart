import 'dart:async';
import 'dart:convert';
import 'dart:io';

const maxFrameBytes = 65536;
const labPort = 45872;

/// Bounded framing. Never log SDP, ICE candidates or raw packets.
Stream<Map<String, dynamic>> readFrames(Stream<List<int>> input) async* {
  var pending = <int>[];
  await for (final chunk in input) {
    for (final byte in chunk) {
      if (byte == 10) {
        final value = jsonDecode(utf8.decode(pending));
        pending = [];
        if (value is! Map<String, dynamic> ||
            value['v'] != 1 ||
            value['type'] is! String) {
          throw const FormatException('Invalid lab frame');
        }
        yield value;
      } else {
        if (pending.length >= maxFrameBytes) {
          throw const FormatException('Oversized lab frame');
        }
        pending.add(byte);
      }
    }
  }
  if (pending.isNotEmpty) throw const FormatException('Truncated lab frame');
}

void writeFrame(Socket socket, Map<String, dynamic> value) {
  final bytes = utf8.encode(jsonEncode({'v': 1, ...value}));
  if (bytes.length > maxFrameBytes) {
    throw const FormatException('Oversized lab frame');
  }
  socket.add([...bytes, 10]);
}

/// Local lab relay only. Sender IDs come from sockets, never caller-supplied IDs.
class LabRelay {
  ServerSocket? _server;
  final _clients = <String, Socket>{};
  final _timers = <Socket, Timer>{};
  var _nextId = 0;
  int get port => _server!.port;

  Future<void> start(InternetAddress address, {int port = labPort}) async {
    _server = await ServerSocket.bind(address, port, shared: false);
    _server!.listen(_accept);
  }

  void _accept(Socket socket) {
    if (_clients.length >= 3) {
      socket.destroy();
      return;
    }
    final id = '${++_nextId}';
    _clients[id] = socket;
    writeFrame(socket, {'type': 'welcome', 'id': id});
    _roster();
    void touch() {
      _timers.remove(socket)?.cancel();
      _timers[socket] = Timer(const Duration(seconds: 20), () => _drop(id));
    }

    touch();
    // Bound bursts from a broken peer as well as individual frame sizes.
    var window = DateTime.now();
    var count = 0;
    readFrames(socket).listen(
      (message) {
        try {
          if (DateTime.now().difference(window).inSeconds >= 1) {
            window = DateTime.now();
            count = 0;
          }
          if (++count > 100) throw const FormatException('Too many frames');
          touch();
          if (message['type'] == 'ping') return;
          if (!const {
            'offer',
            'answer',
            'ice',
            'end',
            'ready',
          }.contains(message['type'])) {
            throw const FormatException('Unsupported lab message');
          }
          final target = _clients[message['to']];
          if (target != null && target != socket) {
            writeFrame(target, {...message, 'from': id});
          }
        } catch (_) {
          _drop(id);
        }
      },
      onError: (_) => _drop(id),
      onDone: () => _drop(id),
    );
  }

  void _roster() {
    for (final socket in _clients.values) {
      writeFrame(socket, {'type': 'peers', 'ids': _clients.keys.toList()});
    }
  }

  void _drop(String id) {
    final socket = _clients.remove(id);
    if (socket == null) return;
    _timers.remove(socket)?.cancel();
    socket.destroy();
    _roster();
  }

  Future<void> close() async {
    await _server?.close();
    _server = null;
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    for (final socket in _clients.values) {
      socket.destroy();
    }
    _clients.clear();
  }
}

class LabSignaling {
  Socket? _socket;
  Timer? _heartbeat;
  int _revision = 0;
  final messages = StreamController<Map<String, dynamic>>.broadcast(sync: true);

  Future<void> connect(
    String host,
    String localAddress, {
    int port = labPort,
    Duration handshakeTimeout = const Duration(seconds: 5),
  }) async {
    close();
    final revision = _revision;
    final socket = await Socket.connect(
      host,
      port,
      sourceAddress: InternetAddress(localAddress),
      timeout: const Duration(seconds: 8),
    );
    if (revision != _revision) {
      socket.destroy();
      return;
    }
    _socket = socket;
    final welcome = Completer<void>();
    void lost() {
      if (!welcome.isCompleted) {
        welcome.completeError(StateError('Lab handshake closed'));
      }
      _lost(revision);
    }

    readFrames(socket).listen(
      (value) {
        if (revision != _revision) return;
        if (!welcome.isCompleted) {
          if (value['type'] != 'welcome' || value['id'] is! String) {
            lost();
            return;
          }
          welcome.complete();
        }
        messages.add(value);
      },
      onError: (_) => lost(),
      onDone: lost,
    );
    try {
      await welcome.future.timeout(handshakeTimeout);
    } catch (_) {
      if (revision == _revision) close();
      rethrow;
    }
    if (revision != _revision) return;
    _heartbeat = Timer.periodic(
      const Duration(seconds: 5),
      (_) => send({'type': 'ping'}),
    );
  }

  void _lost(int revision) {
    if (revision != _revision) return;
    close();
    messages.add({'v': 1, 'type': 'closed'});
  }

  void send(Map<String, dynamic> message) {
    final socket = _socket;
    if (socket != null) writeFrame(socket, message);
  }

  void close() {
    _revision++;
    _heartbeat?.cancel();
    _heartbeat = null;
    _socket?.destroy();
    _socket = null;
  }
}

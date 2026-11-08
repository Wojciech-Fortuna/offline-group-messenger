import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'local_signaling.dart';
import 'p2p_candidates.dart';

/// Foreground feasibility adapter, deliberately separate from production chat.
class AudioLab extends ChangeNotifier {
  AudioLab({
    Future<MediaStream> Function()? capture,
    Future<RTCPeerConnection> Function(Map<String, dynamic>)? createPeer,
    LabSignaling? signaling,
  }) : _capture = capture ?? _openMicrophone,
       _createPeer = createPeer ?? createPeerConnection,
       _signal = signaling ?? LabSignaling();
  final Future<MediaStream> Function() _capture;
  final Future<RTCPeerConnection> Function(Map<String, dynamic>) _createPeer;
  static Future<MediaStream> _openMicrophone() =>
      navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': false,
      });
  final LabSignaling _signal;
  LabRelay? _relay;
  StreamSubscription<Map<String, dynamic>>? _subscription;
  Future<void> _incoming = Future.value();
  P2pNetwork? network;
  String? id;
  List<String> peers = [];
  String state = 'Join a Messenger Wi-Fi Direct group first';
  String? error;
  MediaStream? _microphone;
  RTCPeerConnection? _pc;
  String? _peer;
  String? _call;
  final _pendingIce = <RTCIceCandidate>[];
  final _localIce = <RTCIceCandidate>[];
  bool _localDescriptionSent = false;
  bool _remoteReady = false;
  bool _disposed = false;
  bool _capturing = false;
  bool _sampling = false;
  bool muted = false;
  bool speaker = false;
  int _networkRevision = 0;
  int _mediaRevision = 0;
  int _captureRevision = 0;
  Timer? _stats;
  Timer? _deadline;
  DateTime? _connectedAt;
  final samples = <Map<String, dynamic>>[];
  // Sanitized counters survive cleanup; never include SDP, addresses or audio.
  final diagnostics = <String, dynamic>{};
  bool get micEnabled => _microphone != null;
  bool get hasCall => _call != null;
  bool get capturing => _capturing;

  static Future<void> _release(Future<void> Function() action) async {
    try {
      await action().timeout(const Duration(seconds: 3));
    } catch (_) {
      /* Continue releasing the other native resources. */
    }
  }

  static Future<void> _releaseStream(MediaStream stream) async {
    for (final track in stream.getTracks()) {
      await _release(track.stop);
    }
    await _release(stream.dispose);
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect() async {
    await disconnect();
    if (_disposed) return;
    final revision = ++_networkRevision;
    _incoming = Future.value();
    state = 'Reading actual P2P interface';
    error = null;
    _changed();
    try {
      final raw = await const MethodChannel(
        'offline_transport_lab',
      ).invokeMapMethod('p2pNetwork');
      if (revision != _networkRevision) return;
      network = P2pNetwork.fromMap(raw!);
      if (network!.isHost) {
        final relay = LabRelay();
        await relay.start(InternetAddress(network!.local));
        if (revision != _networkRevision) {
          await relay.close();
          return;
        }
        _relay = relay;
      }
      _subscription = _signal.messages.stream.listen((message) {
        _incoming = _incoming
            .then((_) async {
              if (revision == _networkRevision) await _receive(message);
            })
            .catchError((Object e) async {
              if (revision == _networkRevision &&
                  _call == message['call'] &&
                  _call != null) {
                await _failed('Invalid/failed media setup');
              }
            });
      });
      await _signal.connect(network!.host, network!.local);
      if (revision != _networkRevision) return;
      state = 'Local signaling ready; microphone is off';
      _changed();
    } catch (_) {
      if (revision == _networkRevision) {
        await disconnect();
        error =
            'Cannot connect local signaling. Open the host lab first and check the Messenger group.';
        _changed();
      }
    }
  }

  Future<void> enableMicrophone() async {
    if (_disposed || id == null || micEnabled || _capturing) return;
    _capturing = true;
    final revision = ++_captureRevision;
    _changed();
    try {
      final stream = await _capture();
      if (revision != _captureRevision || _disposed) {
        await _releaseStream(stream);
        return;
      }
      _microphone = stream;
      muted = false;
      error = null;
      state = 'Microphone enabled. Ready to send/accept a lab audio test';
    } catch (_) {
      if (revision == _captureRevision) {
        error = 'Microphone unavailable or permission denied';
      }
    } finally {
      if (revision == _captureRevision) {
        _capturing = false;
        _changed();
      }
    }
  }

  void _send(String type, [Map<String, dynamic> fields = const {}]) =>
      _signal.send({'type': type, 'to': _peer, 'call': _call, ...fields});

  void _sendIce(RTCIceCandidate candidate) => _send('ice', {
    'candidate': candidate.candidate,
    'mid': candidate.sdpMid,
    'index': candidate.sdpMLineIndex,
  });

  void _description(String type, String sdp) {
    _send(type, {'sdp': stripCandidates(sdp)});
    _localDescriptionSent = true;
    for (final candidate in _localIce) {
      _sendIce(candidate);
    }
    _localIce.clear();
  }

  Future<RTCPeerConnection> _create(String peer, String call) async {
    if (!micEnabled || hasCall || network == null) {
      throw StateError('Not ready');
    }
    _peer = peer;
    _call = call;
    diagnostics
      ..clear()
      ..addAll({
        'localP2pCandidates': 0,
        'localCandidatesRejected': 0,
        'remoteP2pCandidates': 0,
        'remoteCandidatesRejected': 0,
        'remoteDescriptionSet': false,
        'gathering': 'new',
        'ice': 'new',
        'connection': 'new',
      });
    final revision = ++_mediaRevision;
    _deadline = Timer(const Duration(seconds: 25), () {
      if (revision == _mediaRevision) {
        final detail = diagnostics['localP2pCandidates'] == 0
            ? 'WebRTC found no local Wi-Fi Direct candidate'
            : diagnostics['remoteP2pCandidates'] == 0
            ? 'No Wi-Fi Direct candidate received from the other phone'
            : 'Wi-Fi Direct candidates exchanged but connectivity failed';
        unawaited(_failed('No local media route within 25 seconds. $detail.'));
      }
    });
    final pc = await _native(
      _createPeer({
        'iceServers': <dynamic>[],
        'sdpSemantics': 'unified-plan',
      }).then((created) async {
        if (revision != _mediaRevision) {
          await _release(created.close);
          await _release(created.dispose);
          throw StateError('Cancelled');
        }
        return created;
      }),
    );
    _pc = pc;
    state = 'Negotiating audio on Wi-Fi Direct';
    error = null;
    samples.clear();
    _connectedAt = null;
    pc.onIceCandidate = (candidate) {
      if (revision != _mediaRevision || candidate.candidate == null) return;
      if (network!.acceptsCandidate(
        candidate.candidate!,
        localCandidate: true,
      )) {
        diagnostics['localP2pCandidates']++;
        if (_localDescriptionSent) {
          _sendIce(candidate);
        } else if (_localIce.length < 64) {
          _localIce.add(candidate);
        }
      } else {
        diagnostics['localCandidatesRejected']++;
      }
      _changed();
    };
    pc.onIceGatheringState = (value) {
      if (revision != _mediaRevision) return;
      diagnostics['gathering'] = value.name;
      _changed();
    };
    pc.onIceConnectionState = (value) {
      if (revision != _mediaRevision) return;
      diagnostics['ice'] = value.name;
      _changed();
    };
    pc.onConnectionState = (value) {
      if (revision != _mediaRevision) return;
      diagnostics['connection'] = value.name;
      _changed();
      if (value == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _deadline?.cancel();
        _connectedAt ??= DateTime.now();
        state = 'Audio connected';
        _changed();
      } else if (value == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        unawaited(_failed('Media connection failed; inspect P2P reachability'));
      } else if (value ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        state = 'Audio interrupted';
        _changed();
        _deadline?.cancel();
        _deadline = Timer(const Duration(seconds: 10), () {
          if (revision == _mediaRevision) {
            unawaited(_failed('Media did not recover'));
          }
        });
      }
    };
    for (final track in _microphone!.getAudioTracks()) {
      await _native(pc.addTrack(track, _microphone!));
      if (revision != _mediaRevision) throw StateError('Cancelled');
    }
    _stats = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _sample(pc, revision),
    );
    _changed();
    return pc;
  }

  Future<void> startAudio(String peer) async {
    if (!peers.contains(peer) || !micEnabled || hasCall) return;
    final call = List.generate(
      16,
      (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      final pc = await _create(peer, call);
      final offer = await _native(
        pc.createOffer({
          'offerToReceiveAudio': true,
          'offerToReceiveVideo': false,
        }),
      );
      if (_call != call) return;
      await _native(pc.setLocalDescription(offer));
      if (_call == call) _description('offer', offer.sdp!);
    } catch (_) {
      if (_call == call) await _failed('Could not start local audio');
    }
  }

  static Future<T> _native<T>(Future<T> result) =>
      result.timeout(const Duration(seconds: 8));

  Future<void> _receive(Map<String, dynamic> message) async {
    switch (message['type']) {
      case 'welcome':
        id = message['id'] as String;
        _changed();
        return;
      case 'peers':
        peers = (message['ids'] as List)
            .cast<String>()
            .where((p) => p != id)
            .toList();
        if (_peer != null && !peers.contains(_peer)) await stopAudio();
        _changed();
        return;
      case 'closed':
        await disconnect();
        error = 'Local signaling disconnected';
        _changed();
        return;
    }
    final peer = message['from'];
    final call = message['call'];
    if (peer is! String ||
        !peers.contains(peer) ||
        call is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(call)) {
      return;
    }
    if (message['type'] == 'offer') {
      if (!micEnabled || hasCall) {
        _signal.send({'type': 'end', 'to': peer, 'call': call});
        return;
      }
      final pc = await _create(peer, call);
      await _native(
        pc.setRemoteDescription(
          RTCSessionDescription(
            stripCandidates(message['sdp'] as String),
            'offer',
          ),
        ),
      );
      if (_call != call) return;
      _remoteReady = true;
      diagnostics['remoteDescriptionSet'] = true;
      final answer = await _native(pc.createAnswer());
      if (_call != call) return;
      await _native(pc.setLocalDescription(answer));
      if (_call == call) _description('answer', answer.sdp!);
      return;
    }
    if (peer != _peer || call != _call) return;
    switch (message['type']) {
      case 'answer':
        if (_remoteReady) return;
        final pc = _pc!;
        await _native(
          pc.setRemoteDescription(
            RTCSessionDescription(
              stripCandidates(message['sdp'] as String),
              'answer',
            ),
          ),
        );
        if (_call != call) return;
        _remoteReady = true;
        diagnostics['remoteDescriptionSet'] = true;
        final candidates = List<RTCIceCandidate>.of(_pendingIce);
        _pendingIce.clear();
        for (final candidate in candidates) {
          if (_call != call) return;
          await _native(pc.addCandidate(candidate));
        }
      case 'ice':
        final raw = message['candidate'] as String;
        if (!network!.acceptsCandidate(raw, localCandidate: false)) {
          diagnostics['remoteCandidatesRejected']++;
          _changed();
          return;
        }
        diagnostics['remoteP2pCandidates']++;
        _changed();
        final candidate = RTCIceCandidate(
          raw,
          message['mid'] as String?,
          message['index'] as int?,
        );
        if (_remoteReady) {
          await _native(_pc!.addCandidate(candidate));
        } else if (_pendingIce.length < 64) {
          _pendingIce.add(candidate);
        } else {
          throw const FormatException('Too many candidates');
        }
      case 'end':
        await stopAudio();
        state = 'Other peer ended/not ready for audio';
        _changed();
    }
  }

  Future<void> _sample(RTCPeerConnection pc, int revision) async {
    if (_sampling) return;
    _sampling = true;
    try {
      final stats = await _native(pc.getStats());
      if (revision != _mediaRevision) return;
      final sample = <String, dynamic>{
        ...diagnostics,
        'seconds': _connectedAt == null
            ? 0
            : DateTime.now().difference(_connectedAt!).inSeconds,
      };
      for (final report in stats) {
        final values = report.values;
        if (report.type == 'inbound-rtp' && values['kind'] == 'audio') {
          for (final key in ['bytesReceived', 'packetsLost', 'jitter']) {
            sample[key] = values[key];
          }
        } else if (report.type == 'outbound-rtp' && values['kind'] == 'audio') {
          sample['bytesSent'] = values['bytesSent'];
        } else if (report.type == 'candidate-pair' &&
            values['state'] == 'succeeded' &&
            values['nominated'] == true) {
          sample['roundTripTime'] = values['currentRoundTripTime'];
        }
      }
      samples.add(sample);
      if (samples.length > 180) samples.removeAt(0);
      _changed();
    } catch (_) {
      /* Sampling must not interrupt audio. */
    } finally {
      _sampling = false;
    }
  }

  void toggleMute() {
    muted = !muted;
    for (final track in _microphone?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    _changed();
  }

  Future<void> toggleSpeaker() async {
    try {
      await Helper.setSpeakerphoneOn(!speaker);
      speaker = !speaker;
    } catch (_) {
      error = 'Speaker route unavailable';
    }
    _changed();
  }

  Future<void> _failed(String reason) async {
    await stopAudio();
    error = reason;
    _changed();
  }

  Future<void> stopAudio() async {
    if (_call != null) _send('end');
    _mediaRevision++;
    _captureRevision++;
    _capturing = false;
    _peer = null;
    _call = null;
    _remoteReady = false;
    _pendingIce.clear();
    _localIce.clear();
    _localDescriptionSent = false;
    _stats?.cancel();
    _stats = null;
    _deadline?.cancel();
    _deadline = null;
    final stream = _microphone;
    _microphone = null;
    final pc = _pc;
    _pc = null;
    if (stream != null) await _releaseStream(stream);
    if (pc != null) {
      await _release(pc.close);
      await _release(pc.dispose);
    }
    state = 'Audio stopped; microphone off';
    _changed();
  }

  Future<void> disconnect() async {
    _networkRevision++;
    await _subscription?.cancel();
    _subscription = null;
    await stopAudio();
    _signal.close();
    await _relay?.close();
    _relay = null;
    id = null;
    peers = [];
    network = null;
    state = 'Lab disconnected; Messenger group unchanged';
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(disconnect());
    super.dispose();
  }
}

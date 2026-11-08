import 'dart:async';
import '../offline_audio.dart';

/// One accepted call. The caller owns consent and authenticated signaling.
class LocalAudioSession {
  LocalAudioSession({
    required this.onSignal,
    required this.onState,
    required this.onError,
    Future<MediaStream> Function()? capture,
    Future<RTCPeerConnection> Function()? createPeer,
  }) : _capture = capture ?? openLocalMicrophone,
       _createPeer = createPeer ?? createLocalPeer;
  final Future<void> Function(Map<String, dynamic>) onSignal;
  final void Function(String) onState;
  final void Function(String) onError;
  final Future<MediaStream> Function() _capture;
  final Future<RTCPeerConnection> Function() _createPeer;
  MediaStream? _stream;
  RTCPeerConnection? _pc;
  P2pNetwork? _network;
  bool _closed = false;
  bool _localSent = false;
  bool _remoteSet = false;
  final _localIce = <RTCIceCandidate>[];
  final _remoteIce = <RTCIceCandidate>[];
  Timer? _deadline;
  bool muted = false;
  bool speaker = false;
  void _check() {
    if (_closed) throw StateError('Call ended');
  }

  Future<T> _native<T>(Future<T> action) async {
    final result = await action.timeout(const Duration(seconds: 8));
    _check();
    return result;
  }

  void _fail(String reason) {
    if (!_closed) {
      onError(reason);
      unawaited(close());
    }
  }

  Future<void> start(P2pNetwork network, {required bool initiator}) async {
    _check();
    if (_network != null) throw StateError('Already started');
    _network = network;
    _deadline = Timer(
      const Duration(seconds: 25),
      () => _fail('Audio connection timed out'),
    );
    try {
      _stream = await _native(
        _capture().then((stream) async {
          if (_closed) {
            await releaseLocalMicrophone(stream);
            throw StateError('Call ended');
          }
          return stream;
        }),
      );
      _pc = await _native(
        _createPeer().then((peer) async {
          if (_closed) {
            await releaseMedia(peer.close);
            await releaseMedia(peer.dispose);
            throw StateError('Call ended');
          }
          return peer;
        }),
      );
      final pc = _pc!;
      pc.onConnectionState = (state) {
        if (_closed) return;
        if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
          _deadline?.cancel();
          onState('active');
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
          _fail('Audio connection failed');
        } else if (state ==
            RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
          onState('reconnecting');
          _deadline?.cancel();
          _deadline = Timer(
            const Duration(seconds: 10),
            () => _fail('Audio connection lost'),
          );
        }
      };
      pc.onIceCandidate = (candidate) {
        if (_closed ||
            candidate.candidate == null ||
            !network.acceptsCandidate(
              candidate.candidate!,
              localCandidate: true,
            )) {
          return;
        }
        if (_localSent) {
          unawaited(
            _ice(
              candidate,
            ).catchError((Object _) => _fail('Could not send media setup')),
          );
        } else if (_localIce.length < 64) {
          _localIce.add(candidate);
        }
      };
      for (final track in _stream!.getAudioTracks()) {
        await _native(pc.addTrack(track, _stream!));
      }
      if (initiator) {
        final offer = await _native(
          pc.createOffer({
            'offerToReceiveAudio': true,
            'offerToReceiveVideo': false,
          }),
        );
        await _description(offer);
      }
    } catch (_) {
      await close();
      rethrow;
    }
  }

  Future<void> _ice(RTCIceCandidate c) => onSignal({
    'kind': 'ice',
    'candidate': c.candidate,
    'mid': c.sdpMid,
    'index': c.sdpMLineIndex,
  });
  Future<void> _description(RTCSessionDescription description) async {
    await _native(_pc!.setLocalDescription(description));
    await onSignal({
      'kind': description.type,
      'sdp': stripCandidates(description.sdp!),
    });
    _check();
    _localSent = true;
    for (final candidate in _localIce) {
      _check();
      await _ice(candidate);
    }
    _localIce.clear();
  }

  Future<void> receive(Map<String, dynamic> message) async {
    _check();
    final pc = _pc;
    if (pc == null) throw StateError('Audio not ready');
    final kind = message['kind'];
    if (kind == 'offer' || kind == 'answer') {
      if (_remoteSet) return;
      final sdp = message['sdp'] as String;
      if (sdp.length > 16000) throw const FormatException('SDP too large');
      await _native(
        pc.setRemoteDescription(
          RTCSessionDescription(stripCandidates(sdp), kind as String),
        ),
      );
      _remoteSet = true;
      for (final candidate in _remoteIce) {
        await _native(pc.addCandidate(candidate));
      }
      _remoteIce.clear();
      if (kind == 'offer') {
        await _description(await _native(pc.createAnswer()));
      }
    } else if (kind == 'ice') {
      final raw = message['candidate'] as String;
      if (!_network!.acceptsCandidate(raw, localCandidate: false)) return;
      final candidate = RTCIceCandidate(
        raw,
        message['mid'] as String?,
        message['index'] as int?,
      );
      if (_remoteSet) {
        await _native(pc.addCandidate(candidate));
      } else if (_remoteIce.length < 64) {
        _remoteIce.add(candidate);
      } else {
        throw const FormatException('Too many ICE candidates');
      }
    }
  }

  void setMuted(bool value) {
    if (_closed) return;
    muted = value;
    for (final track in _stream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !value;
    }
  }

  Future<void> setSpeaker(bool value) async {
    _check();
    await Helper.setSpeakerphoneOn(value);
    _check();
    speaker = value;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _deadline?.cancel();
    final stream = _stream;
    _stream = null;
    final pc = _pc;
    _pc = null;
    _localIce.clear();
    _remoteIce.clear();
    if (stream != null) await releaseLocalMicrophone(stream);
    if (pc != null) {
      await releaseMedia(pc.close);
      await releaseMedia(pc.dispose);
    }
  }
}

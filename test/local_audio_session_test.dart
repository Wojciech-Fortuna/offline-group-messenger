import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_audio/offline_audio.dart';

class AudioStreamFake extends Fake implements MediaStream {
  bool disposed = false;
  @override
  List<MediaStreamTrack> getTracks() => [];
  @override
  List<MediaStreamTrack> getAudioTracks() => [];
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class AudioPeerFake extends Fake implements RTCPeerConnection {
  bool disposed = false;
  @override
  Function(RTCIceCandidate)? onIceCandidate;
  @override
  Function(RTCPeerConnectionState)? onConnectionState;
  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => RTCSessionDescription(
    'v=0\r\na=candidate:1 1 udp 1 10.0.0.2 5000 typ host\r\n',
    'offer',
  );
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    onIceCandidate?.call(
      RTCIceCandidate('candidate:1 1 udp 1 192.168.49.2 5000 typ host', '0', 0),
    );
    onIceCandidate?.call(
      RTCIceCandidate('candidate:2 1 udp 1 10.0.0.2 5000 typ host', '0', 0),
    );
  }

  @override
  Future<void> close() async {}
  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  final network = P2pNetwork(
    host: '192.168.49.1',
    local: '192.168.49.2',
    prefix: 24,
    isHost: false,
  );
  testWidgets('cancelled capture is released and never creates a peer', (
    tester,
  ) async {
    final capture = Completer<MediaStream>();
    var peers = 0;
    final session = LocalAudioSession(
      onSignal: (_) async {},
      onState: (_) {},
      onError: (_) {},
      capture: () => capture.future,
      createPeer: () async {
        peers++;
        return AudioPeerFake();
      },
    );
    final start = session.start(network, initiator: true);
    final expectation = expectLater(start, throwsStateError);
    await session.close();
    final stream = AudioStreamFake();
    capture.complete(stream);
    await expectation;
    expect(stream.disposed, isTrue);
    expect(peers, 0);
  });
  testWidgets('SDP precedes P2P-only ICE and close disposes native resources', (
    tester,
  ) async {
    final sent = <Map<String, dynamic>>[];
    final stream = AudioStreamFake();
    final peer = AudioPeerFake();
    final session = LocalAudioSession(
      onSignal: (message) async {
        sent.add(message);
      },
      onState: (_) {},
      onError: (_) {},
      capture: () async => stream,
      createPeer: () async => peer,
    );
    await session.start(network, initiator: true);
    expect(sent.map((m) => m['kind']), ['offer', 'ice']);
    expect(sent.first['sdp'], isNot(contains('candidate:')));
    expect(sent.last['candidate'], contains('192.168.49.2'));
    await session.close();
    expect(stream.disposed, isTrue);
    expect(peer.disposed, isTrue);
    peer.onIceCandidate?.call(
      RTCIceCandidate('candidate:1 1 udp 1 192.168.49.2 5000 typ host', '0', 0),
    );
    expect(sent.length, 2);
  });
}

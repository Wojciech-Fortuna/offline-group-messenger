import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:offline_transport_lab/audio_lab.dart';
import 'package:offline_transport_lab/local_signaling.dart';
import 'package:offline_transport_lab/p2p_candidates.dart';
import 'audio_lifecycle_test.dart' show StreamFake;

class RecordingSignaling extends LabSignaling {
  final sent = <Map<String, dynamic>>[];
  @override
  void send(Map<String, dynamic> message) => sent.add(message);
}

class SenderFake extends Fake implements RTCRtpSender {}

class PeerFake extends Fake implements RTCPeerConnection {
  bool closed = false;
  bool disposed = false;
  Completer<RTCSessionDescription>? delayedOffer;
  @override
  Function(RTCIceCandidate)? onIceCandidate;
  @override
  Function(RTCPeerConnectionState)? onConnectionState;
  @override
  Future<RTCRtpSender> addTrack(
    MediaStreamTrack track, [
    MediaStream? stream,
  ]) async => SenderFake();
  @override
  Future<RTCSessionDescription> createOffer([
    Map<String, dynamic>? constraints,
  ]) async => delayedOffer != null
      ? delayedOffer!.future
      : RTCSessionDescription(
          'v=0\r\na=candidate:1 1 udp 1 10.0.0.1 5000 typ host\r\n',
          'offer',
        );
  @override
  Future<void> setLocalDescription(RTCSessionDescription description) async {
    onIceCandidate?.call(
      RTCIceCandidate('candidate:1 1 udp 1 192.168.88.7 5000 typ host', '0', 0),
    );
    onIceCandidate?.call(
      RTCIceCandidate('candidate:2 1 udp 1 10.0.0.7 5000 typ host', '0', 0),
    );
  }

  @override
  Future<List<StatsReport>> getStats([MediaStreamTrack? track]) async => [];
  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void prepare(AudioLab lab) {
  lab.id = '1';
  lab.peers = ['2'];
  lab.network = P2pNetwork(
    host: '192.168.88.1',
    local: '192.168.88.7',
    prefix: 24,
    isHost: false,
  );
}

void main() {
  testWidgets(
    'sends SDP before early ICE and never sends infrastructure candidates',
    (tester) async {
      final signaling = RecordingSignaling();
      final peer = PeerFake();
      Map<String, dynamic>? configuration;
      final lab = AudioLab(
        capture: () async => StreamFake(),
        signaling: signaling,
        createPeer: (config) async {
          configuration = config;
          return peer;
        },
      );
      prepare(lab);
      await lab.enableMicrophone();
      await lab.startAudio('2');
      expect(configuration!['iceServers'], isEmpty);
      expect(signaling.sent.map((m) => m['type']), ['offer', 'ice']);
      expect(signaling.sent.first['sdp'], isNot(contains('candidate:')));
      expect(signaling.sent.last['candidate'], contains('192.168.88.7'));
      await lab.disconnect();
      expect(peer.closed, isTrue);
      expect(peer.disposed, isTrue);
      lab.dispose();
      await tester.pump();
    },
  );

  testWidgets('hung native creation times out and a late peer is disposed', (
    tester,
  ) async {
    final creation = Completer<RTCPeerConnection>();
    final stream = StreamFake();
    final peer = PeerFake();
    final lab = AudioLab(
      capture: () async => stream,
      createPeer: (_) => creation.future,
    );
    prepare(lab);
    await lab.enableMicrophone();
    final start = lab.startAudio('2');
    await tester.pump();
    await tester.pump(const Duration(seconds: 9));
    await start;
    expect(lab.hasCall, isFalse);
    expect(lab.micEnabled, isFalse);
    expect(stream.disposed, isTrue);
    creation.complete(peer);
    await tester.pump();
    expect(peer.closed, isTrue);
    expect(peer.disposed, isTrue);
    lab.dispose();
    await tester.pump();
  });

  testWidgets(
    'late offer after stop never sends signaling or revives microphone',
    (tester) async {
      final signaling = RecordingSignaling();
      final peer = PeerFake()
        ..delayedOffer = Completer<RTCSessionDescription>();
      final lab = AudioLab(
        capture: () async => StreamFake(),
        createPeer: (_) async => peer,
        signaling: signaling,
      );
      prepare(lab);
      await lab.enableMicrophone();
      final start = lab.startAudio('2');
      await tester.pump();
      await lab.stopAudio();
      peer.delayedOffer!.complete(RTCSessionDescription('v=0\r\n', 'offer'));
      await start;
      expect(
        signaling.sent.where((message) => message['type'] == 'offer'),
        isEmpty,
      );
      expect(lab.micEnabled, isFalse);
      expect(peer.closed, isTrue);
      lab.dispose();
      await tester.pump();
    },
  );
}

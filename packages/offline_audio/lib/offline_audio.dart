import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'src/p2p_candidates.dart';
export 'src/p2p_candidates.dart';
export 'src/local_audio_session.dart';
export 'package:flutter_webrtc/flutter_webrtc.dart';

Future<P2pNetwork> readP2pNetwork() async => P2pNetwork.fromMap(
  (await const MethodChannel(
    'com.offlinegroupmessenger/audio',
  ).invokeMapMethod('p2pNetwork'))!,
);

Future<MediaStream> openLocalMicrophone() =>
    navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

Future<RTCPeerConnection> createLocalPeer([
  Map<String, dynamic> configuration = const {},
]) => createPeerConnection({
  ...configuration,
  'iceServers': <dynamic>[],
  'sdpSemantics': 'unified-plan',
});

Future<void> releaseMedia(Future<void> Function() action) async {
  try {
    await action().timeout(const Duration(seconds: 3));
  } catch (_) {
    /* Continue cleanup. */
  }
}

Future<void> releaseLocalMicrophone(MediaStream stream) async {
  for (final track in stream.getTracks()) {
    await releaseMedia(track.stop);
  }
  await releaseMedia(stream.dispose);
}

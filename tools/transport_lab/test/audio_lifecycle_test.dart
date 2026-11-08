import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:offline_transport_lab/audio_lab.dart';

class Track implements MediaStreamTrack {
  bool stopped = false;
  bool failStop = false;
  @override
  Future<void> stop() async {
    stopped = true;
    if (failStop) throw StateError('Native track already gone');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class StreamFake implements MediaStream {
  final track = Track();
  bool disposed = false;
  @override
  List<MediaStreamTrack> getTracks() => [track];
  @override
  List<MediaStreamTrack> getAudioTracks() => [track];
  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('stream cleanup continues when native track teardown fails', () async {
    final stream = StreamFake();
    stream.track.failStop = true;
    final lab = AudioLab(capture: () async => stream)..id = '1';
    await lab.enableMicrophone();
    await lab.disconnect();
    expect(stream.disposed, isTrue);
    expect(lab.micEnabled, isFalse);
    lab.dispose();
  });
  test(
    'microphone is opt-in and a late capture is stopped after cancellation',
    () async {
      final pending = Completer<MediaStream>();
      var requests = 0;
      final lab = AudioLab(
        capture: () {
          requests++;
          return pending.future;
        },
      );
      await lab.enableMicrophone(); // No local signaling: cannot arm capture.
      expect(requests, 0);
      lab.id = '1';
      expect(requests, 0);
      final enable = lab.enableMicrophone();
      await lab
          .enableMicrophone(); // Repeated button press does not capture twice.
      expect(requests, 1);
      await lab.stopAudio();
      final stream = StreamFake();
      pending.complete(stream);
      await enable;
      expect(stream.track.stopped, isTrue);
      expect(stream.disposed, isTrue);
      expect(lab.micEnabled, isFalse);
      expect(lab.capturing, isFalse);
      lab.dispose();
    },
  );

  test(
    'enabled microphone is released on disconnect and denial can be retried',
    () async {
      final stream = StreamFake();
      var denied = true;
      final lab = AudioLab(
        capture: () async {
          if (denied) throw StateError('denied');
          return stream;
        },
      )..id = '1';
      await lab.enableMicrophone();
      expect(lab.micEnabled, isFalse);
      expect(lab.capturing, isFalse);
      denied = false;
      await lab.enableMicrophone();
      expect(lab.micEnabled, isTrue);
      await lab.disconnect();
      expect(stream.track.stopped, isTrue);
      expect(stream.disposed, isTrue);
      expect(lab.micEnabled, isFalse);
      lab.dispose();
    },
  );
}

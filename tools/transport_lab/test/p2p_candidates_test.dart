import 'package:flutter_test/flutter_test.dart';
import 'package:offline_transport_lab/p2p_candidates.dart';

void main() {
  final network = P2pNetwork(
    host: '192.168.88.1',
    local: '192.168.88.7',
    prefix: 24,
    isHost: false,
  );
  String candidate(
    String ip, [
    String kind = 'host',
    String protocol = 'udp',
  ]) => 'candidate:1 1 $protocol 1234 $ip 50000 typ $kind generation 0';
  test(
    'uses actual P2P interface and rejects other interfaces and external candidates',
    () {
      expect(
        network.acceptsCandidate(
          candidate('192.168.88.7'),
          localCandidate: true,
        ),
        isTrue,
      );
      for (final ip in [
        '192.168.49.1',
        '192.168.1.7',
        '10.0.0.7',
        '127.0.0.1',
        '8.8.8.8',
        'host.local',
        '::1',
      ]) {
        expect(
          network.acceptsCandidate(candidate(ip), localCandidate: true),
          isFalse,
        );
        expect(
          network.acceptsCandidate(candidate(ip), localCandidate: false),
          isFalse,
        );
      }
      expect(
        network.acceptsCandidate(
          candidate('192.168.88.9'),
          localCandidate: false,
        ),
        isTrue,
      );
      expect(
        network.acceptsCandidate(
          candidate('192.168.88.7'),
          localCandidate: false,
        ),
        isFalse,
      );
      expect(
        network.acceptsCandidate(
          candidate('192.168.88.9', 'srflx'),
          localCandidate: false,
        ),
        isFalse,
      );
      expect(
        network.acceptsCandidate(
          candidate('192.168.88.9', 'host', 'tcp'),
          localCandidate: false,
        ),
        isFalse,
      );
    },
  );
  test('rejects inconsistent network snapshot and malformed candidate', () {
    expect(
      () => P2pNetwork(
        host: '10.0.0.1',
        local: '192.168.88.7',
        prefix: 24,
        isHost: false,
      ),
      throwsFormatException,
    );
    expect(
      () => P2pNetwork(
        host: '192.168.88.1',
        local: '192.168.88.7',
        prefix: 0,
        isHost: false,
      ),
      throwsFormatException,
    );
    expect(network.acceptsCandidate('garbage', localCandidate: true), isFalse);
    expect(
      network.acceptsCandidate(
        'candidate:1 1 udp 1 192.168.88.7 99999 typ host',
        localCandidate: true,
      ),
      isFalse,
    );
  });
  test('SDP cannot sneak in unfiltered candidates', () {
    final cleaned = stripCandidates(
      'v=0\r\na=candidate:external\r\na=end-of-candidates\r\na=ice-ufrag:example\r\n',
    );
    expect(cleaned, isNot(contains('candidate')));
    expect(cleaned, contains('a=ice-ufrag:example'));
  });
}

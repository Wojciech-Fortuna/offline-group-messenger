import 'dart:io';

class P2pNetwork {
  P2pNetwork({
    required this.host,
    required this.local,
    required this.prefix,
    required this.isHost,
  }) {
    if (InternetAddress.tryParse(local)?.type != InternetAddressType.IPv4 ||
        InternetAddress.tryParse(host)?.type != InternetAddressType.IPv4 ||
        prefix < 1 ||
        prefix > 32 ||
        !contains(host)) {
      throw const FormatException('No usable local Wi-Fi Direct IPv4 subnet');
    }
  }
  factory P2pNetwork.fromMap(Map<dynamic, dynamic> map) => P2pNetwork(
    host: map['host'] as String,
    local: map['local'] as String,
    prefix: map['prefix'] as int,
    isHost: map['isHost'] as bool,
  );
  final String host;
  final String local;
  final int prefix;
  final bool isHost;

  bool contains(String address) {
    final parsed = InternetAddress.tryParse(address);
    final own = InternetAddress.tryParse(local);
    if (parsed?.type != InternetAddressType.IPv4 ||
        own?.type != InternetAddressType.IPv4) {
      return false;
    }
    int number(InternetAddress ip) =>
        ip.rawAddress.fold(0, (value, b) => (value << 8) | b);
    final mask = (0xffffffff << (32 - prefix)) & 0xffffffff;
    return (number(parsed!) & mask) == (number(own!) & mask);
  }

  bool acceptsCandidate(String line, {required bool localCandidate}) {
    final parts = line.trim().split(RegExp(r'\s+'));
    if (parts.length < 8 ||
        !parts[0].startsWith('candidate:') ||
        parts[2].toLowerCase() != 'udp' ||
        parts[6] != 'typ' ||
        parts[7] != 'host') {
      return false;
    }
    final port = int.tryParse(parts[5]);
    if (port == null || port < 1 || port > 65535) return false;
    return localCandidate
        ? parts[4] == local
        : contains(parts[4]) && parts[4] != local;
  }
}

/// Only separately validated, trickled candidates may establish a media route.
String stripCandidates(String sdp) => sdp
    .split(RegExp(r'\r?\n'))
    .where(
      (line) =>
          !line.startsWith('a=candidate:') && line != 'a=end-of-candidates',
    )
    .join('\r\n');

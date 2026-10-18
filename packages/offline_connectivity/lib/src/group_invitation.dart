import 'dart:convert';

/// Contains network credentials. Do not log or persist invitations.
class GroupInvitation {
  const GroupInvitation._(this.networkName, this.passphrase);
  final String networkName;
  final String passphrase;

  factory GroupInvitation.fromMap(Map<String, dynamic> map) {
    final name = map['networkName'];
    final password = map['passphrase'];
    if (map['app'] != 'offline-group-messenger' ||
        map['version'] != 1 ||
        map['transport'] != 'wifi-direct' ||
        name is! String ||
        !RegExp(r'^DIRECT-[a-zA-Z0-9]{2}').hasMatch(name) ||
        utf8.encode(name).length > 32 ||
        name.contains(RegExp(r'[\x00-\x1f\x7f]')) ||
        password is! String ||
        password.length < 8 ||
        password.length > 63 ||
        password.codeUnits.any((c) => c < 32 || c > 126)) {
      throw const FormatException('This is not a supported group invitation.');
    }
    return GroupInvitation._(name, password);
  }

  factory GroupInvitation.parse(String raw) {
    if (raw.length > 2048) {
      throw const FormatException('Invitation is too large.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('This is not a group invitation.');
    }
    return GroupInvitation.fromMap(decoded);
  }

  Map<String, dynamic> toMap() => {
    'app': 'offline-group-messenger',
    'version': 1,
    'transport': 'wifi-direct',
    'networkName': networkName,
    'passphrase': passphrase,
  };
  String encode() => jsonEncode(toMap());
}

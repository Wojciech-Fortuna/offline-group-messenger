import 'dart:convert';

/// Contains network credentials. Do not log or persist invitations.
class GroupInvitation {
  const GroupInvitation._(
    this.networkName,
    this.passphrase,
    this.privateGroup,
    this.admissionToken,
  );
  final String networkName;
  final String passphrase;
  final bool privateGroup;
  final String? admissionToken;

  factory GroupInvitation.fromMap(Map<String, dynamic> map) {
    final name = map['networkName'];
    final password = map['passphrase'];
    final version = map['version'];
    final privateGroup = map['privateGroup'] == true;
    final token = map['admissionToken'];
    if (map['app'] != 'offline-group-messenger' ||
        version != (privateGroup ? 2 : 1) ||
        (map['privateGroup'] != null && map['privateGroup'] is! bool) ||
        (privateGroup &&
            (version != 2 ||
                token is! String ||
                !RegExp(r'^[0-9a-f]{64}$').hasMatch(token))) ||
        (!privateGroup && token != null) ||
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
    return GroupInvitation._(name, password, privateGroup, token as String?);
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
    'version': privateGroup ? 2 : 1,
    'transport': 'wifi-direct',
    'networkName': networkName,
    'passphrase': passphrase,
    if (privateGroup) 'privateGroup': true,
    if (privateGroup) 'admissionToken': admissionToken,
  };
  String encode() => jsonEncode(toMap());
}

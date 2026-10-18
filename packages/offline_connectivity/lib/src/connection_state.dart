enum GroupStatus {
  idle,
  discovering,
  connecting,
  connected,
  disconnecting,
  unavailable,
}

class NearbyPeer {
  const NearbyPeer({
    required this.id,
    required this.name,
    required this.isGroupOwner,
  });
  final String id;
  final String name;
  final bool isGroupOwner;
  factory NearbyPeer.fromMap(Map<String, dynamic> map) {
    if (map['id'] is! String ||
        map['name'] is! String ||
        map['isGroupOwner'] is! bool) {
      throw const FormatException('Invalid peer.');
    }
    return NearbyPeer(
      id: map['id'] as String,
      name: map['name'] as String,
      isGroupOwner: map['isGroupOwner'] as bool,
    );
  }
}

class GroupConnectionState {
  const GroupConnectionState({
    this.status = GroupStatus.idle,
    this.wifiEnabled = false,
    this.permissionGranted = false,
    this.isHost = false,
    this.hostAddress,
    this.peers = const [],
    this.errorCode,
    this.errorMessage,
  });
  final GroupStatus status;
  final bool wifiEnabled;
  final bool permissionGranted;
  final bool isHost;
  final String? hostAddress;
  final List<NearbyPeer> peers;
  final String? errorCode;
  final String? errorMessage;
  factory GroupConnectionState.fromMap(Map<String, dynamic> map) {
    final statuses = GroupStatus.values.where((s) => s.name == map['status']);
    if (statuses.isEmpty ||
        map['wifiEnabled'] is! bool ||
        map['permissionGranted'] is! bool ||
        map['isHost'] is! bool ||
        map['peers'] is! List ||
        (map['hostAddress'] != null && map['hostAddress'] is! String) ||
        (map['errorCode'] != null && map['errorCode'] is! String) ||
        (map['errorMessage'] != null && map['errorMessage'] is! String)) {
      throw const FormatException('Invalid connection state.');
    }
    final status = statuses.single;
    final address = map['hostAddress'] as String?;
    if (status == GroupStatus.connected &&
        (address == null || address.isEmpty)) {
      throw const FormatException('Connected state requires a host address.');
    }
    return GroupConnectionState(
      status: status,
      wifiEnabled: map['wifiEnabled'] as bool,
      permissionGranted: map['permissionGranted'] as bool,
      isHost: map['isHost'] as bool,
      hostAddress: address,
      peers: List.unmodifiable(
        (map['peers'] as List).map(
          (peer) => NearbyPeer.fromMap(Map<String, dynamic>.from(peer as Map)),
        ),
      ),
      errorCode: map['errorCode'] as String?,
      errorMessage: map['errorMessage'] as String?,
    );
  }
}

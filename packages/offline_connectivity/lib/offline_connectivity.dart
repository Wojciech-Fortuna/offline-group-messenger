import 'package:flutter/services.dart';
import 'src/connection_state.dart';
import 'src/group_invitation.dart';
export 'src/connection_state.dart';
export 'src/group_invitation.dart';

/// Small, typed boundary between the shared GUI and native connection setup.
class OfflineConnectivity {
  const OfflineConnectivity();

  static const channelName = 'com.offlinegroupmessenger/connectivity';
  static const _channel = MethodChannel(channelName);
  static const eventChannelName = '$channelName/events';
  static final _states = const EventChannel(eventChannelName)
      .receiveBroadcastStream()
      .map(
        (event) => GroupConnectionState.fromMap(
          Map<String, dynamic>.from(event as Map),
        ),
      );

  /// Snapshot on subscribe, then updates until the subscription is cancelled.
  Stream<GroupConnectionState> get states => _states;

  /// Completion means accepted by Android, not an established connection.
  Future<void> createGroup() => _channel.invokeMethod<void>('createGroup');
  Future<void> discoverPeers() => _channel.invokeMethod<void>('discoverPeers');
  Future<void> joinGroup(String peerId) =>
      _channel.invokeMethod<void>('joinGroup', {'peerId': peerId});
  Future<void> disconnect() => _channel.invokeMethod<void>('disconnect');
  Future<GroupInvitation> getInvitation() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getInvitation',
    );
    if (result == null) {
      throw const FormatException('Missing group invitation.');
    }
    return GroupInvitation.fromMap(result);
  }

  Future<void> joinInvitation(GroupInvitation invitation) =>
      _channel.invokeMethod<void>('joinInvitation', invitation.toMap());
  Future<GroupConnectionState> getState() async {
    final result = await _channel.invokeMapMethod<String, dynamic>('getState');
    if (result == null) {
      throw const FormatException('Missing connection state.');
    }
    return GroupConnectionState.fromMap(result);
  }

  Future<ConnectionCapabilities> getCapabilities() async {
    final result = await _channel.invokeMapMethod<String, dynamic>(
      'getCapabilities',
    );
    if (result == null) {
      throw const FormatException('Missing native capability response.');
    }
    return ConnectionCapabilities.fromMap(result);
  }
}

class ConnectionCapabilities {
  const ConnectionCapabilities({
    required this.platform,
    required this.wifiDirectSupported,
    required this.implementationReady,
    required this.description,
    this.canJoinQr = false,
  });

  factory ConnectionCapabilities.fromMap(Map<String, dynamic> map) {
    final platform = map['platform'];
    final wifiDirectSupported = map['wifiDirectSupported'];
    final implementationReady = map['implementationReady'];
    final description = map['description'];
    if (platform is! String ||
        wifiDirectSupported is! bool ||
        implementationReady is! bool ||
        description is! String) {
      throw const FormatException('Invalid native capability response.');
    }
    return ConnectionCapabilities(
      platform: platform,
      wifiDirectSupported: wifiDirectSupported,
      implementationReady: implementationReady,
      description: description,
      canJoinQr: map['canJoinQr'] == true,
    );
  }

  final String platform;
  final bool wifiDirectSupported;
  final bool implementationReady;
  final String description;
  final bool canJoinQr;
}

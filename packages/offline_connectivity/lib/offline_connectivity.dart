import 'package:flutter/services.dart';

/// Small, typed boundary between the shared GUI and native connection setup.
class OfflineConnectivity {
  const OfflineConnectivity();

  static const channelName = 'com.offlinegroupmessenger/connectivity';
  static const _channel = MethodChannel(channelName);

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
    );
  }

  final String platform;
  final bool wifiDirectSupported;
  final bool implementationReady;
  final String description;
}

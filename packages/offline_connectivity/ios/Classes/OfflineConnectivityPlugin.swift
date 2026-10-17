import Flutter
import UIKit

public class OfflineConnectivityPlugin: NSObject, FlutterPlugin {
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(
            name: "com.offlinegroupmessenger/connectivity",
            binaryMessenger: registrar.messenger()
        )
        registrar.addMethodCallDelegate(OfflineConnectivityPlugin(), channel: channel)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "getCapabilities":
            result([
                "platform": "ios",
                "wifiDirectSupported": false,
                "implementationReady": false,
                "description": "The iPhone interface is shared. The iOS connection adapter is not implemented yet."
            ])
        default:
            result(FlutterMethodNotImplemented)
        }
    }
}

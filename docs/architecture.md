# Architecture

## Stack and boundaries

Flutter / Dart owns screens, themes, navigation, chat state, message models and
the future TCP messaging layer. Kotlin owns Android Wi-Fi Direct integration.
Swift owns future iOS connection integration. There is no cloud backend.

The app depends on a local Flutter plugin, packages/offline_connectivity.
Flutter registers its Kotlin and Swift implementations automatically. Native code
does not belong in widgets, and shared chat logic does not belong in Kotlin.

The connectivity bridge follows Flutter's platform-channel architecture:
https://docs.flutter.dev/platform-integration/platform-channels

## Current implementation

- Standard Flutter Android and iOS application hosts.
- Shared Material 3 home screen with light and dark themes.
- Local plugin with a working getCapabilities method on both platforms.
- Android checks whether Wi-Fi Direct hardware is advertised by the device.
- Swift explicitly reports that the iOS connection adapter is not implemented.
- Both platforms report implementationReady=false. This is a scaffold, not a
  working messenger. No request claims to create or join a real group.
- Shared message and participant models and a message transport interface.

## Next implementation steps

1. Kotlin: runtime permissions, WifiP2pManager lifecycle, create/discover/join,
   connection state and disconnect cleanup. Use ActivityAware in the plugin when
   permission requests need an Activity. Keep blocking work off the UI thread.
2. Expose connection events through a documented EventChannel. Return the actual
   group-owner IP; never hardcode an address or infer readiness from hardware.
3. Dart: implement TCP framing, bounded versioned JSON messages, validation,
   deduplication, acknowledgements and host fan-out. Transport should be injectable.
4. Add lobby and chat screens with loading, denied permission, empty discovery,
   disconnected, reconnecting and delivery-failed states.
5. Design authenticated encrypted messaging before claiming privacy. A wireless
   password is not a complete participant-authentication or end-to-end design.
6. Add persistence, QR invitations and NFC experiments after the connection works.

The Android host leaving ends the group in the first prototype. Host migration,
multi-hop forwarding and background operation are separate milestones.

## Future iPhone support

The Flutter GUI is already shared. Implement the Swift side of the same plugin
when adding iOS networking; no Swift rewrite of the screens is needed.
An iPhone may join an Android-hosted group as an ordinary Wi-Fi client. Test that
on actual devices early; iOS does not expose Android's Wi-Fi Direct APIs.

Shared Dart TCP code can then exchange the same messages with the Android host.
The native connection method may differ, and user interaction may be necessary.
Adding Swift does not itself guarantee interoperability.

Build and test iOS on macOS with Xcode. Windows can edit the shared UI and Swift
source, but cannot compile or validate the iOS application.

## Toolchain

Flutter 3.35.7 is the pinned baseline for this scaffold (Dart 3.9).
Use the generated Flutter Android toolchain rather than independent Compose/KMP
Gradle configuration. The downloaded .tools/flutter SDK is ignored by Git.

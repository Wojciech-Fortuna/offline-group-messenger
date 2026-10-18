# Architecture

## Stack and boundaries

Flutter / Dart owns screens, themes, navigation, chat state, message models and
the TCP messaging layer. Kotlin owns Android Wi-Fi Direct integration.
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
- Android implements create/discover/join/disconnect and reports
  implementationReady=true. iOS remains false and rejects connection methods
  with unsupported. This flag means the adapter is implemented, not that a
  connection is established or that messaging exists.
- ActivityAware handles runtime permission requests. The engine owns the receiver
  and P2P channel; activity resume refreshes system connection state. Detaching
  releases listeners and attempts group cleanup. Explicit disconnect is preferred.
- An EventChannel carries snapshots. The actual group-owner address comes from
  WifiP2pInfo, not an assumed subnet. Action success only acknowledges acceptance;
  connected state requires groupFormed and a non-null group-owner address.
- Requests have a 15-second callback timeout. Connecting is rechecked for about
  60 seconds to catch missing broadcasts and rejected invitations. It can also
  be cancelled from the UI. Callback revisions discard obsolete operation results.
- Shared message and participant models and a message transport interface.
- TcpMessageTransport starts automatically on a connected native snapshot, using
  the actual host address and TCP port 45871. Duplicate snapshots do not restart
  chat. Network loss closes sockets; a new session or explicit retry starts fresh.
  A shared chat screen observes transport state and retains drafts on send failure.
  See chat-protocol.md for framing, bounds, host confirmation and limitations.
- Host QR invitations use group network credentials fetched on explicit request.
  Android 10+ joins with WifiP2pConfig.Builder SSID/passphrase; discovery remains
  available on older versions. mobile_scanner uses bundled ML Kit so first scan
  does not require Internet. qr_flutter renders a black-on-white QR in either theme.

## Next implementation steps

1. Run the hardware checks in wifi-direct-testing.md on two or three phones.
2. Add app-specific service discovery before treating all discovered peers as
   compatible messenger instances. Current discovery lists generic Wi-Fi peers.
3. Validate TCP messaging on two and three phones, including range loss.
4. Add durable delivery receipts, history synchronization and session resumption.
5. Design authenticated encrypted messaging before claiming privacy. A wireless
   password is not a complete participant-authentication or end-to-end design.
6. Add persistence and NFC experiments after messaging works.

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

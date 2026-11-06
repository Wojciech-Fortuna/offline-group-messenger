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
- ChatSessionController owns conversation history, drafts, outgoing message states
  and native connection coordination outside HomeScreen. TcpMessageTransport owns
  sockets, the resume handshake, host replay/acceptance caches and ordering cursors.
  The controller starts chat on a connected native snapshot using the actual host
  address and TCP port 45871. Duplicate snapshots do not restart chat.
- Client network loss suspends sockets without clearing session state. A restored
  connected snapshot resumes automatically; TCP-only loss offers Retry chat.
  Retry message preserves its request ID. Replay reconciles uncertain sends with
  host-accepted messages. No automatic resend of uncertain sends is performed.
- Host departure or a changed host session ends the conversation. Explicit new
  chat clears local history/draft/outbox; rejoining never silently sends them to
  a different group. Everything remains in memory, scoped to this app process.
  See chat-protocol.md for protocol v3, bounded replay and retry limitations.
- Public host QR invitations use group network credentials fetched on explicit request.
  Android 10+ joins with WifiP2pConfig.Builder SSID/passphrase; discovery remains
  available on older versions. mobile_scanner uses bundled ML Kit so first scan
  does not require Internet. qr_flutter renders a black-on-white QR in either theme.
- Optional Android NFC uses a non-payment HostApduService and reader mode, not
  Android Beam. A separate NfcInvitationController handles activity lifecycle,
  timeouts and cancellation. InvitationApdu is a pure Kotlin protocol with JVM
  tests. Both QR and NFC return the same validated GroupInvitation and require
  the same confirmation before joinInvitation. No NFC chat transport is added.
- Private creation generates a 256-bit admission secret in Dart and passes it to
  native group creation for NFC sharing. Private invitation schema v2 carries it;
  public invitations retain schema v1. The native QR method and Dart scanner both
  reject private invitations. The TCP host checks admission before sending any
  welcome/roster/history to a first-time participant. Resume tokens still work.
- PublicGroupDiscovery registers a DNS-SD service for public hosts only and filters
  discovery responses to this app's public service records. Generic Wi-Fi devices
  are excluded. Advertisement callbacks and scans have generation/lifecycle checks;
  service records contain no credentials. Nearby entries expire after 60 seconds.

## Next implementation steps

The canonical sequence is in [roadmap.md](roadmap.md). Session recovery is
implemented with automated coverage. Host acceptance remains distinct from
recipient delivery or read receipts. Protocol v3 adds identity-bound client
acknowledgements and bounded delivery snapshots sent only to the message sender.
See delivery-receipts.md for three-stage checks and resume behavior. State uses memory only.

Run the two/three-phone Wi-Fi Direct, chat and NFC checks and record device/OS
versions and outcomes. No completed hardware-validation results are recorded yet.
Automated recovery tests can be implemented here; they do not satisfy that gate.

Authenticated encryption, durable storage and background operation follow.
App-specific public discovery and NFC-only private admission are implemented;
see group-modes.md for their limits and hardware acceptance checks.

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

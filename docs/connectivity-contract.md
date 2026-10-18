# Native connectivity contract

Method channel: com.offlinegroupmessenger/connectivity
Event channel: com.offlinegroupmessenger/connectivity/events
Codec: Flutter StandardMethodCodec.

## Methods

| Method | Arguments | Result |
| --- | --- | --- |
| getCapabilities | none | platform, wifiDirectSupported, implementationReady, description |
| getState | none | Cached snapshot; also schedules a system refresh emitted as events |
| createGroup | none | null when Android accepts group creation |
| discoverPeers | none | null when Android accepts discovery |
| joinGroup | {peerId: string} | null when Android accepts connection to a discovered peer |
| disconnect | none | null after discovery/negotiation cleanup and group removal |
| getInvitation | none | Versioned invitation for the current connected host group |
| joinInvitation | invitation map | null when Android accepts credential-based joining (API 29+) |

Android requests the appropriate runtime permission automatically before a
connection command. Requests are serialized; concurrent commands fail with busy.
getCapabilities does not request permission. Swift supports getCapabilities and
returns unsupported for other methods; clients must check capabilities first.
Unknown methods return notImplemented.

Capabilities include canJoinQr (true only on supported Android 10+ devices).
getInvitation requires the caller to already be the connected Group Owner; it
queries WifiP2pGroup on demand. Credentials are never added to state snapshots.
joinInvitation uses WifiP2pConfig.Builder with the SSID and password, avoiding
reliance on the host's own MAC address, which Android can redact.

The QR contains a UTF-8 JSON object with app="offline-group-messenger", version=1,
transport="wifi-direct", networkName and passphrase. Reject unrelated payloads,
unsupported versions, malformed SSIDs/passwords and codes over 2048 characters.
SSID must follow DIRECT-xy naming and fit 32 UTF-8 bytes; the passphrase is
8–63 printable ASCII characters. Both Dart and native Android validate inputs.
Additional errors are not_host and invalid_invitation.
There is no expiry or one-time-use guarantee: this shares network credentials,
not a cryptographically authenticated messaging invitation.

A successful create/join call does NOT mean the connection is established.
Wait for status=connected in the event stream before using hostAddress.
There is no messaging socket or port in this API yet.

## State snapshots

A new native event subscription receives the latest snapshot, followed by system
updates. Use a single app-owned subscription. Cancelling it detaches the event
sink, not the Wi-Fi group; use disconnect to leave.

| Field | Type | Meaning |
| --- | --- | --- |
| status | string | idle, discovering, connecting, connected, disconnecting, unavailable |
| wifiEnabled | bool | Current Wi-Fi/P2P availability |
| permissionGranted | bool | Required runtime permission is granted |
| isHost | bool | Android reports this device as group owner |
| hostAddress | string or null | Actual WifiP2pInfo.groupOwnerAddress; cleared on disconnect |
| peers | list | Each item has id, name (strings) and isGroupOwner (bool) |
| errorCode | string or null | Last failure identifier |
| errorMessage | string or null | Recovery message suitable for display |

Connected state requires a host address. Discovery may end with no results.
Peer IDs are Android-provided addresses for this discovery session; do not persist
them as participant identities. Peer names do not authenticate an app or user.

## Errors and cleanup

PlatformException codes include unsupported, busy, permission_denied,
wifi_disabled, location_disabled, invalid_peer, no_activity, activity_detached,
unavailable, channel_lost, connection_failed, timeout and detached.
Asynchronous connection expiry emits connection_timeout in a snapshot.
A 15-second operation timeout bounds Android callbacks after permission approval;
group formation has a separate roughly 60-second window. Permissions are never
treated as granted merely because time elapsed.

The plugin refreshes connection info on resume and connection broadcasts, drops
callbacks from obsolete commands, and unregisters receivers/listeners on engine
detach. Engine teardown attempts cleanup; explicit disconnect is required for a
reliable user-visible result. Killing the process may leave a system-owned group.

Android Wi-Fi Direct reference:
https://developer.android.com/develop/connectivity/wifi/wifi-direct

Do not log credentials, chat messages or peer addresses.

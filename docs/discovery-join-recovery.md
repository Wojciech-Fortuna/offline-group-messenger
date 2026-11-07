# Discovery-to-connection handoff

## Evidence

After the offline setup update, both guests reported Android error 0 when joining
a public host found through DNS-SD. Huawei logs show `InactiveState sending
connect`, followed immediately by `Dropping connect requeset` and `joinGroup
failed: 0`. Android 9's Wi-Fi P2P service emits this when the peer configuration
is invalid, including when the selected device is absent from its peer table.

The previous update awaited `stopPeerDiscovery()` before MAC-address joining.
Android's inactive-state STOP_DISCOVERY handler flushes supplicant peer state.
Our DNS-SD result cache can still display the host after that flush, making the
handoff invalid. Periodic search restarts and normal expiration can also make
the displayed result older than Android's current peer table.

Source: [Android 9 WifiP2pServiceImpl](https://android.googlesource.com/platform/prebuilts/fullsdk/sources/android-28/+/refs/heads/androidx-activity-release/com/android/server/wifi/p2p/WifiP2pServiceImpl.java).

## Planned correction

- For public joining, invalidate app discovery callbacks and remove the service
  request without calling native STOP_DISCOVERY. Android's connect operation
  stops discovery itself while preserving the peer needed for negotiation.
- Check the selected host against Android's peer table immediately before
  connecting. If missing, run a bounded peer refresh and connect only to that
  same selected public host. Do not expose generic/private peers in the UI.
- If the target remains absent, report a specific rediscovery error. Do not
  blindly loop on Android error 0, change the host, or leave Connecting forever.
- Keep explicit stop behavior for cancellation, teardown and other operations.
- Test present/missing hosts, target-only selection, deadlines, cancellation and
  late callbacks. Build/install, then verify discovery joining on USB devices.

All discovery and connection traffic stays local. Public DNS-SD still contains
no network password or private admission token; initial private admission is NFC.

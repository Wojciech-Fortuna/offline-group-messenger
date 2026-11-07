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

## Implemented correction

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

## Validation and historical hardware issue

All 18 native unit tests pass, including eight peer-gate tests for present and
missing hosts, unrelated devices, deadlines, missing callbacks, obsolete commands
and native discovery failures. The debug APK builds and was installed on Huawei.

USB Huawei retry against the discovered OPPO Reno6 Pro 5G: the selected peer was
present, `joinGroup accepted` replaced the prior immediate error 0, and Android
entered ProvisionDiscoveryState then GroupNegotiationState. This verifies the
handoff correction on the device that previously rejected connect.

The same attempt subsequently ended with P2P-GROUP-FORMATION-FAILURE. OPPO and
Xiaomi were absent from ADB for that test. This records the historical failed
attempt, not the latest outcome.

User follow-up reported on 2026-11-07: Huawei successfully joined the OPPO group
on the latest attempt. The exact test time, build and radio conditions were not
recorded. Treat Huawei-to-OPPO joining as user-confirmed working; the earlier
failure is not an established current blocker. The broader host-rotation,
router-free, rejection, timeout and retry matrix is not yet fully recorded.

## C0 follow-up: bounded setup and stale callbacks

ConnectionSetup now separates accepted native requests from formed groups with
a usable host address. Native action callbacks have a 15-second deadline, and
group formation has a separate 75-second overall deadline starting with the setup
request (including discovery shutdown/peer refresh). Accepting the request
releases the method-channel request but leaves Connecting until authoritative
group information arrives. A confirmed group also releases the request when the
action callback is missing.

Duplicate/contradictory action callbacks are ignored once the action has answered.
Successfully formed, failed, cancelled and replaced attempts ignore late setup
callbacks. Failure invalidates the operation revision, including queued polling
and peer-refresh callbacks. Polling cannot extend either deadline. Timeout
cancels negotiation without removing an unrelated group.

Validation: Flutter analysis, 59 application tests, 16 connectivity-package tests,
25 native tests and the Android debug APK build pass. Seven new native tests cover acceptance without
formation, missing callbacks, authoritative success before the action response,
duplicate responses, rejection, timeout and cancellation/retry isolation.
Physical host/client rotation, offline joining, rejection and retry remain open.

For a fresh failure, capture app logs on both host and client while reproducing:

```powershell
& "$env:LOCALAPPDATA\Android\sdk\platform-tools\adb.exe" -s '<USB serial>' logcat -v time -s OfflineConnection:D OfflineDiscovery:D '*:S'
```

Record which phone hosted, Android versions, the system invitation decision and
whether logs show only `accepted` or an actual `P2P state=connected`. Use USB for
the router-free run. Do not publish unfiltered Wi-Fi/P2P dumps, which can contain
network credentials.

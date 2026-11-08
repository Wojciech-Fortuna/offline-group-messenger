# C1 transport feasibility lab

Implemented software: a separate Android application under `tools/transport_lab`,
installed alongside Messenger. C0 hardening and the reported Huawei-to-OPPO join
are already recorded. The complete C0 device matrix remains open; isolated C1
experiments can proceed without claiming that gate is complete.

Commit C1a: foreground BLE advertising, filtered discovery and a bounded GATT
challenge/echo probe. Advertisements carry only a lab service UUID; a successful
probe demonstrates bidirectional bytes, not trusted contact identity or pairing.
Stop all radio work on pause, cancellation and timeout. No private credentials.

Commit C1b: local TCP signaling and WebRTC/Opus audio on an existing Wi-Fi Direct
group. The lab only observes that group; it must not create/remove it. Signaling
uses a different port from chat and is a lab-only, unauthenticated protocol.
Only explicit microphone enablement starts capture. Test host/client first, then
two clients through the signaling host. Audio uses P2P-interface host candidates,
with no external ICE servers. Close media when the lab is backgrounded.

The lab has its own package, permissions and dependencies. No contact schema,
production calling UI, public Messenger discovery advertisement, QR pairing or
background calling is introduced. Production authentication remains C2 work.

Acceptance: automated framing/cancellation checks and debug build, then physical
BLE roles in both directions, Wi-Fi coexistence, ten-minute full-duplex audio,
client-client reachability, stats and measured latency. Record actual outcomes;
unit tests, an echo or a successful build do not prove audio quality/background
reachability. RTT/jitter stats are not a one-way acoustic latency measurement.

C1a software validation: isolated lab analysis and its explicit-selection/lifecycle
widget test pass; Android debug APK builds. Package ID:
`com.offlinegroupmessenger.offline_transport_lab`. BLE hardware acceptance is
recorded separately from this build result.

## C1b implementation and validation

Local signaling (TCP 45872) supports one host and two clients with socket-bound
temporary IDs, directed messages, bounded frames, an initial handshake deadline,
heartbeats and idle cleanup. It is unauthenticated lab signaling, not C2 identity.
The host forwards signaling only; client-client media still needs physical proof.

The audio adapter pins flutter_webrtc 1.6.3, uses no ICE servers, strips inline SDP
candidates and exchanges only UDP host candidates on the actual P2P IPv4 interface
and subnet. Microphone capture is explicit; late capture after cancellation is
disposed. Setup timeout, hang-up, peer loss and backgrounding close audio. Mute,
speaker routing and sanitized counter/jitter/RTT samples support manual testing.
P2P observation never creates/removes the Messenger group.

Automated lab checks cover framing, a three-peer local signaling relay and sender
ID substitution, silent-server timeout, candidate/subnet filtering, inline SDP
candidate removal, microphone cancellation/denial/cleanup and BLE UI lifecycle.
Native WebRTC setup calls have eight-second deadlines inside an overall 25-second
media setup deadline. Additional tests verify that late peer creation is disposed,
cancelled offers are never transmitted and SDP precedes early trickle candidates.
See [running the lab](../tools/transport_lab/README.md) for physical steps.

Hardware status: Huawei (Android 9) accepted the BLE lab installation and launched;
the first combined BLE/audio APK also installed successfully on 2026-11-07.
MI 9 (Android 11) rejected installation with INSTALL_FAILED_USER_RESTRICTED.
OPPO was not connected to ADB. Bluetooth was not fully enabled on the two available
phones at inspection. No successful two-phone GATT echo or audio session has been
measured in this milestone. The ten-minute audio, client-client media, BLE/Wi-Fi
coexistence, latency and C0 host-rotation acceptance gates remain open. Do not
advance the production contact/call feature based only on successful compilation.

2026-11-08: no phones connected to ADB during the final software review. All 13 lab
tests, repository analysis and the debug APK build pass. Latest cleanup/deadline
changes still require installing the new build
on the phones. The software milestone does not close the physical acceptance gate.

## Xiaomi / OPPO media setup investigation (2026-11-08)

The latest C1b APK subsequently installed on both MI 9 and OPPO CPH2247. The user
reported zero media bytes and the 25-second route timeout. ADB inspection found
an active P2P group on both phones (OPPO owner, Xiaomi client). Xiaomi's WebRTC
log reported zero monitored networks and gathered only loopback candidates.
These are correctly rejected by the lab's P2P-only filter. This is a media network
enumeration failure, not evidence of insufficient Wi-Fi Direct bandwidth.

Next repair: enable Android WebRTC's `NetworkMonitorAutoDetect.setIncludeWifiDirect`
before any peer factory/network monitor is created. The upstream
[network detector](https://webrtc.googlesource.com/src/+/3e64739a76ca6130088817c6da189d53308a8e40/sdk/android/api/org/webrtc/NetworkMonitorAutoDetect.java)
gates P2P observation behind this opt-in. Keep the actual-interface candidate
filter and empty ICE server list. Add sanitized local/remote candidate counts and
ICE state to distinguish missing local candidates, missing remote candidates and
failed connectivity. Preserve the failed attempt's diagnostics after cleanup.

Validate analysis, regression tests and Android build, then reinstall on both
phones and retry. A successful route and increasing bidirectional media counters
are required before claiming this fixes physical audio. Ten-minute listening,
fully offline operation and the remaining C1 hardware matrix remain open.

Repair software validation: the P2P monitor opt-in is now applied before Flutter
plugin registration, using the same native WebRTC 150.7871.04 artifact as the
pinned plugin. Route counters/states survive teardown and appear in the screen,
samples and sanitized export. All 14 lab tests, repository analysis and Android
debug build pass, including timeout diagnostic retention and stale-callback
rejection. Physical retry results must be recorded separately below.

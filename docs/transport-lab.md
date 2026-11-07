# C1 transport feasibility lab

Implementation scope: a separate Android application under `tools/transport_lab`,
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

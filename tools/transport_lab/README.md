# Transport Lab

Separate Android package `com.offlinegroupmessenger.offline_transport_lab`.
See [scope and acceptance](../../docs/transport-lab.md). Does not replace Messenger.

From this directory:

```powershell
..\..\.tools\flutter\bin\flutter.bat pub get
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
..\..\.tools\flutter\bin\flutter.bat build apk --debug
```

BLE: enable Bluetooth, open the lab on both phones. On one choose **Advertise
GATT probe**, on the other **Find lab probes**, then **Test echo** on a result.
Expect a successful random 16-byte write/read echo on both screens. Reverse roles.
Repeat while a Wi-Fi Direct chat group exists. Advertisements end after 60 seconds;
scanning after 30, a connect/echo attempt after 15. Backgrounding stops the probe.
Pre-Android 12 scanning also needs Location permission and system Location on.

No contact identity, secrets, group credentials or chat text are carried by BLE.
Success proves a transport exchange only; it does not establish authentication.

## Audio on an existing Wi-Fi Direct group

1. Connect the phones in Messenger first, then open Transport Lab on each. The
   lab observes the actual group interface and never creates/removes that group.
2. On the group host, press **Connect local signaling**, then do the same on the
   clients. TCP port 45872 is reserved for this lab, separate from chat's 45871.
3. On the two phones under test, explicitly **Enable microphone for test**.
   This arms capture/acceptance of lab audio; there is no production ringing UX.
4. Select the intended peer and press **Start audio test** on just one phone.
   Both phones can speak simultaneously. Use mute, speaker/earpiece and stop.
5. Run for ten minutes; copy sanitized stats on both phones. Record audible
   quality, interruptions and the latency measurement method separately. Stats
   report counters/jitter/RTT, not acoustic one-way latency. No audio is recorded.
6. Test two clients with a third phone hosting signaling and its microphone OFF.
   This tests direct client-client media reachability. No local media relay is
   implemented; failure means that topology's feasibility gate remains open.
7. Repeat without a router/mobile data, using USB ADB, and with a BLE probe active.
   Repeat hang-up, permission denial, screen lock and network loss. Foreground-only:
   backgrounding the lab closes signaling, audio and BLE; it does not end the group.

The WebRTC adapter is pinned to flutter_webrtc 1.6.3. ICE servers are empty; only
UDP host candidates on the actual P2P IPv4 interface/subnet are exchanged. Inline
SDP candidates are stripped so they cannot bypass filtering. Test on other subnet
ranges as well. Exported stats omit addresses, SDP, credentials and recorded audio.
Signaling identities are temporary socket IDs and unauthenticated: this is a
feasibility tool, not private contact calling. NFC pairing is a later milestone.

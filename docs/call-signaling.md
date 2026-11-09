# C3 foreground calls inside an existing group

Control is a capability-negotiated extension of chat v3, not audio in the chat
queue. Updated peers advertise `calls: 1` in hello, welcome and roster. Only send
call frames if both the host and destination advertise support. An old build
continues chatting; it never receives an unknown call frame. Hosts overwrite the
outer sender from the socket identity and direct frames only to the selected peer.
Bound frames and per-sender rates; never add signaling to chat history/replay.

Endpoints exchange compact JWS authenticated by the NFC-pinned identity. Native
code signs only for verified/unblocked contacts and verifies only with saved keys.
The signed body binds scope `ogm-call-v1`, sender/recipient fingerprints, group ID,
sender/recipient participant IDs, sender's fresh connection nonce, recipient's
challenge, sequence, call ID, message kind and contents. Sign all SDP/ICE, including
DTLS fingerprints. The routing host is not an identity authority and cannot change
media negotiation. Signaling metadata is not encrypted in this milestone; media
uses WebRTC DTLS-SRTP. Existing chat remains plaintext.

At each transport connection, generate a fresh random nonce. Exchange signed
hello/challenge replies for known contacts with capable group peers; a matching
fresh challenge response is required for presence/call acceptance. Old hello
messages cannot ring. Other control messages require the established nonce pair
and strictly increasing per-peer sequence. Refresh presence after contacts change;
discard it on socket loss, group change, backgrounding and identity reset.

One active call per device. Caller sends invite without opening the microphone;
recipient shows the verified saved name and acknowledges ringing. Answer accepts
the call; only then do the two endpoints open microphones and negotiate media.
Decline, cancel, busy, timeout and hang-up are distinct outcomes. A late answer or
SDP cannot revive a cancelled/expired call. Resolve simultaneous invites by a
deterministic identity ordering; no duplicate calls. Bounded ringing and media
setup deadlines. No background ringing guarantee: pausing closes only call media.

The first enabled topology is host/client (the physically demonstrated path).
Client/client stays capability-gated until the three-phone test passes. C3 does
not create a P2P group, disconnect chat, admit a new private member or advertise BLE.
Call UI stays accessible from chat and contacts. Call end leaves the group intact.

Validate real loopback routing with multiple peers, legacy capability behavior,
sender substitution, signature/replay rejection, cancellation/late-answer races,
mutual calls, microphone consent and chat surviving hang-up. Physical NFC trust
establishment and audio in the integrated app remain separate acceptance checks.

C3b implemented: capability negotiation and directed frames, native pinned-contact
JWS sign/verify, connection challenge/sequence checks, verified presence, call state
controller and media consent/cancellation. All 70 app tests and 34 native tests
pass, including live loopback routing, legacy-host chat, forged/replayed tokens,
delayed answer cancellation, simultaneous calls and chat after hang-up. The screen
integration follows separately; no physical integrated-call result is claimed.

## C3c integration and acceptance (2026-11-09)

Messenger now owns the call controller for the app foreground lifetime. Contacts
is available from home and chat; eligible contacts expose Call. Incoming calls
open Answer/Decline; controls show connection status, duration, mute, earpiece/
speaker and hang-up. Returning to chat preserves media; backgrounding stops it.
Foreground return renews both sides' authenticated presence with fresh challenges,
retired-nonce rejection and bounded foreground retries for incomplete handshakes.

All 72 app tests, 34 native tests, analysis and the debug APK build pass in the
integration checks. The shared lab's 14 tests and debug build passed after adapter
extraction. These are software results. No ADB devices were connected for the
integrated NFC/audio acceptance; the earlier audible success was in Transport Lab.

Install `build/app/outputs/flutter-apk/app-debug.apk` on both phones. Follow the
Contacts and calls steps in README, verify both NFC roles and restart persistence,
then host/client calls in both directions. Check decline, simultaneous calls,
microphone denial, cancellation, chat during a call, hang-up and background/return.
Repeat ten minutes without a router/mobile data. Keep client-client disabled until
the separate three-phone media check passes. C4 BLE invitations and C5 background
calling are not part of this foreground integration.

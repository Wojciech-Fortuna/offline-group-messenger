# NFC contacts and offline voice calls

Status: C0 recovery hardening implemented; physical connection acceptance remains
open. C1 software is implemented as an isolated [transport lab](transport-lab.md),
split into BLE/GATT (C1a) and local audio (C1b) commits. Contacts and production
calling are not implemented. C1 physical radio/audio acceptance remains open. Android first.
Each milestone gets its own commit without a co-author trailer. The acceptance
gates below distinguish implemented software from demonstrated phone behavior.

## Product decisions

- Add a person by an explicit NFC contact exchange, with both apps open and
  phones unlocked. No QR alternative for private contacts or private admission.
- Save the contact across app restarts. Calling does not require another tap.
- One-to-one calls are full duplex: both people can speak at once. Group voice
  is a later push-to-talk feature with one active speaker.
- Everything works locally: no account server, Internet, cloud push, public
  STUN/TURN service, SIM or router requirement.
- A saved contact identifies a person/device; it does not guarantee proximity,
  availability, network membership or permission to activate a microphone.

## Recommended transports

| Purpose | Transport | Why |
| --- | --- | --- |
| Establish a trusted contact | NFC, new mutual exchange | Intentional in-person pairing independent of a Wi-Fi group |
| Ring someone in the same group | Authenticated messages over the existing local connection | No network change or extra discovery |
| Find/ring a disconnected contact | BLE advertisements plus authenticated GATT exchange | Small request can arrive before creating Wi-Fi Direct |
| Carry live audio | WebRTC/Opus over Wi-Fi Direct | Real-time audio processing and encrypted media |

Wi-Fi Direct alone is sufficient once both people share a connection. Without
one, it requires discovery and network formation before application signaling
can arrive. A native Wi-Fi connection prompt is not a contact-authenticated
incoming-call screen. BLE is the recommended additional invitation channel for
the requested answer-before-connecting experience; it is not required for calls
inside an existing group. Its hardware/background behavior is a feasibility gate.

NFC is used only during the tap. Wi-Fi Direct addresses, SSIDs and IPs can change;
they are connection hints, never persistent contact identities. See [Android
MAC randomization](https://source.android.com/docs/core/connect/wifi-direct).

## Contact identity, persistence and trust

Each installation owns a long-lived cryptographic identity. A contact record
contains its public identity/fingerprint, local display name, capabilities,
verification state and per-contact discovery material. Private keys and pairing
secrets need protected storage; use platform-backed protection and an established
cryptographic library/protocol. Select the exact protocol in the security design
milestone, rather than inventing a key exchange or trusting display names.

The current NFC APDU protocol reads a reusable group invitation in one direction.
It must not be relabeled as contact pairing. Add a separate, versioned contact
protocol that exchanges both identities, fresh handshake data, proof of key
possession and completion acknowledgements over NFC. Both users confirm the
person/contact; persist recoverable pending state until mutual completion is
established. Interrupted taps, duplicate taps and lost acknowledgements must be
safe to retry without silently activating an unverified or duplicate contact.
Physical proximity is useful but does not make NFC immune to relay attacks.

Pairing grants permission to request calls, not automatic answer, Wi-Fi membership
or access to a private group's history. Contact trust, group membership and the
current session's participant/resume IDs remain separate concepts.

Removing/blocking a contact removes their ability to ring this device and retires
their discovery material. Group removal still follows the group's separate
membership/revocation rules. App reinstall/key loss requires re-pairing; a matching
display name must never silently replace the old identity. Define deletion,
backup exclusion and key-loss behavior before committing the storage schema.

## Calling flows and ownership

### Both contacts already share a group

Send an authenticated, private call offer addressed to the contact through the
existing connection. On acceptance, establish a separate encrypted audio session.
Keep the existing Wi-Fi owner and chat group. The caller need not be the host.
Ending the call closes its media/signaling resources, not the existing group.

Do not put audio into the chat TCP message queue. Bind media setup to the verified
contact and call ID, including authenticated WebRTC fingerprints/negotiation.
Even if the group host forwards signaling or media, a one-to-one call's plaintext
audio must remain available only to its two endpoints. WebRTC encryption alone
does not authenticate an untrusted signaling peer.

First prove host-to-client audio, then client-to-client audio on a three-phone
group. Do not assume OEMs permit client-to-client UDP. If a local relay is needed,
it must be compatible with the selected media stack and forward encrypted media
without decoding it. This needs a feasibility spike; the existing TCP broadcast
host is not already a WebRTC media relay. Do not substitute a cloud relay.

### Contacts are disconnected and both radios are free

1. The recipient enables availability; both phones have Bluetooth and Wi-Fi on.
2. Caller selects the NFC-paired contact and presses Call.
3. BLE finds a candidate; an authenticated GATT handshake verifies the contact.
   Send a fresh, bounded call offer. Caller shows Finding/Calling, and only shows
   Ringing after the recipient acknowledges delivery of the incoming-call alert.
4. Recipient sees the verified contact name and Answer/Decline. No microphone
   capture or Wi-Fi group admission occurs before acceptance.
5. On Answer, negotiate transport roles. Default: recipient creates a temporary,
   non-public Wi-Fi Direct group; caller joins. Roles are implementation details
   and may reverse if capability negotiation requires it before setup begins.
6. Share fresh group credentials over the authenticated encrypted BLE channel,
   bound to this call and expiring with it. Never broadcast them in advertisements.
   Android may still show a connection approval prompt; do not promise silent join.
7. Verify the same identities on the new network; exchange authenticated media
   setup, establish audio, then show Connected/start the duration timer.
8. Hang-up, rejection, cancellation or expiry stops call resources. Remove only
   a temporary group owned by this call; never tear down an unrelated group.

Answer means accepting this call and its temporary connection, not admitting a
person to a pre-existing private chat. There will be a Connecting stage between
Answer and audio on a newly formed network; measure it rather than promising
instant carrier-call setup.

### A phone is already in another group

Assume one active Wi-Fi Direct group per device; do not depend on concurrent P2P
groups. If the two contacts do not share that group, the first standalone-call
release reports Busy in another group. The user may leave explicitly and retry.
In particular, a hosting phone must not end everyone's chat or disclose private
group credentials merely because a contact calls. Membership changes, host
migration and seamless switching are later features, not implicit call consent.

## Private presence and availability

Use rotating opaque contact-recognizable BLE tokens, not names, public identity
keys, group names or static tracking identifiers. Define a reviewed derivation,
rotation/revocation scheme with clock-skew tolerance and test advertisement-size
limits, multiple contacts and discovery latency on real hardware. Authenticate
the GATT peer before revealing identity, ringing or sending network credentials.
Advertisements are hints, never proof of identity. Unknown/blocked/replayed offers
must not ring, and repeated requests need bounded rate limits.

This keeps private groups out of public app discovery; it does not hide the
existence of Bluetooth/Wi-Fi transmissions or all radio metadata. The existing
public group discovery remains a separate feature.

Show availability conservatively: Connected, Nearby (recently authenticated),
Unavailable/Not recently seen, or Busy. Retain the contact when it is unreachable.
BLE and Wi-Fi ranges differ: a detected contact is not proof that an audio link
will form. No offline call can reach a device outside all available radio paths.

Start with both apps in the foreground. Later add an explicit Available for calls
mode and Android call notifications/Core-Telecom integration. Background BLE
scanning/advertising, screen lock, Doze, process death and OEM battery management
need physical tests. No cloud push fallback, periodic polling-job workaround or
promise of waking a force-stopped app. A foreground service alone does not
guarantee reachability. See [Android background BLE guidance](https://developer.android.com/develop/connectivity/bluetooth/ble/background)
and [Core-Telecom](https://developer.android.com/develop/connectivity/telecom/voip-app/telecom).

## State, media and compatibility

Use call IDs, version negotiation and bounded deadlines for Finding, Offering,
Ringing, Accepted/Connecting, Active, Reconnecting and Ended/Failed. Authenticate
all state-changing messages; late accept after cancel/expiry cannot create a group
or turn on audio. Simultaneous calls between the same contacts resolve to one
session by a deterministic rule. One active call per device in the first release.
Decline, Busy, unreachable, permission denial, network failure and normal hang-up
must be distinct outcomes. Do not record call audio by default.

Use a maintained WebRTC integration compatible with the pinned Flutter/Android
toolchain. Verify local ICE candidates on the actual P2P interface with no external
STUN/TURN/DNS dependency. Negotiate Opus, echo cancellation and jitter buffering;
handle mute, speaker/earpiece and audio focus. Bluetooth headset routing follows
after basic audio works. See [WebRTC connection setup](https://webrtc.org/getting-started/peer-connections).

Planning budget: approximately 50-100 kbit/s per direction including normal IP
transport overhead; measure actual rate, loss, latency and battery use. It is not
a guaranteed airtime requirement or performance measurement. Initial acceptance
target: a 10-minute full-duplex call, no accumulating delay, and measured one-way
audio latency under 200 ms on a good nearby link. Report measurement method and
exceptions; test both speakers talking to expose echo/capture problems.

Initial standalone credential-based setup targets Android 10+. NFC contact
exchange itself need not have that restriction, unlike the existing invitation
joining flow. Huawei's older Android can test NFC contacts and calls in an already
joined group; standalone support needs a separately proven legacy WPS/approval
path. Capability-gate unsupported flows instead of offering a broken Call action.
iOS calling/networking remains a separate feasibility track.

## Code ownership

| Area | Planned responsibility |
| --- | --- |
| `lib/core/identity/`, `lib/core/contacts/` | Identity/contact models, repository and pairing state |
| `lib/features/contacts/` | List, Add by NFC, verification, block/delete and availability |
| `lib/core/calling/`, `lib/features/calling/` | Call state machine, authenticated signaling and call screens |
| `packages/offline_connectivity/` | NFC contact exchange, BLE control transport, P2P setup and capabilities |
| Separate media adapter | Selected WebRTC integration; no audio frames through the current method channel or chat transport |
| Android call service/adapter | Telecom, notifications, audio routing and background lifecycle |

Reuse the existing TCP transport only as a carrier for a versioned signaling
extension; isolate call state from ChatSessionController. Preserve current chat
and invitation behavior. Background components must have a service-owned lifecycle,
not rely solely on the current Flutter-engine/activity-scoped plugin state.

## Milestones and acceptance gates

| Milestone / separate commit | Scope | Exit criteria |
| --- | --- | --- |
| C0: stabilize connections | Finish current discovery/negotiation issue, including OPPO host logs | Same-build MI 9/OPPO/Huawei matrix: host rotation, offline join, rejection, timeout and retry; distinguish accepted request from formed group |
| C1: transport feasibility | Small foreground BLE/GATT and local WebRTC experiments; no production contact/call UX claim | Validate BLE roles and Wi-Fi coexistence on three phones; prove 10-minute host-client audio and test client-client path; document legacy Android limits and local relay decision |
| C2: identity and NFC contacts | Reviewed authentication/key lifecycle, protected persistent contact store, mutual NFC protocol, contact screens | Contacts survive restart; both peers prove identity; interrupted/duplicate taps recover; impostor/key replacement rejected; block/delete work; existing private NFC invitations unchanged |
| C3: normal calls within a group | Authenticated call offer/accept/decline, full-duplex media, mute/speaker/hang-up | Both talk at once; no microphone before answer; group/chat survive call end; nonparticipants cannot decrypt media; cancellation, busy, loss and late events tested |
| C4: call a disconnected contact | Private BLE presence/offers, accepted-call temporary P2P setup, capability/busy rules | Tap once then restart and call without another tap or router; reject creates no network; roles work both directions; no private group admission; resources clean up on every failure |
| C5: background calling | Android Telecom/notifications, explicit availability mode, foreground-service lifecycle, audio routes | Lock-screen answer, screen-off call, interruptions, headset routes, Doze and OEM battery tests; accurately report unsupported/unreachable states |
| C6: group walkie-talkie | Host-managed speaking lease and group-authorized encrypted audio distribution | One speaker at a time, deterministic contention, lease expiry on disconnect, correct membership/revocation, measured three-phone audio and bandwidth |

C2 is the first user-facing feature after the radio/media gates; do not implement
the contact list around MAC addresses while postponing identity design. Durable
contacts are required here even though durable chat-history storage is a separate
existing roadmap item. Background incoming calls must not be claimed at C3/C4.
After each milestone: focused automated checks, applicable physical acceptance,
updated docs and its own commit. Keep unsuccessful hardware outcomes recorded.

## Implementation review and current gate (2026-11-07)

The order above remains necessary. C1 must establish local media reachability
before selecting a production media/relay adapter. C2 must settle the reviewed
mutual authentication protocol, recovery and key lifecycle before committing a
durable contact schema. Existing NFC invitations, MAC addresses and chat
participant IDs cannot satisfy C2's identity requirements.

C0 software progress: connection setup now separates native action acceptance
from authoritative usable-group confirmation. A 15-second action deadline and
75-second overall formation deadline cover missing callbacks. A group confirmed
before the action callback completes the request; late/duplicate action callbacks
cannot turn that success into failure. Failure invalidates the operation revision
so queued callbacks cannot operate on a later retry.

User follow-up reported on 2026-11-07 confirms that Huawei successfully joined
the OPPO group on the latest attempt. This supersedes the earlier failed attempt
as the latest outcome for that direction; the historical failure is not an
established current blocker. The exact successful build and radio conditions
were not recorded. The complete C0 host-rotation/offline/rejection/timeout/retry
matrix remains to be recorded. C1 BLE/media lab software is now implemented; its
physical feasibility checks and results are tracked in transport-lab.md.
Do not infer that contacts or calling are implemented from successful group joining.

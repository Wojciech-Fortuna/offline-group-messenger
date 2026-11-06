# Chat protocol and recovery

## Usage and hardware checks

Hardware validation remains outstanding. Record phone model, Android version,
build/commit, joining method and outcome for each run.

1. Install the same current build on two Android phones. Enter different names,
   create a group and join using QR, NFC or discovery. Keep the app foregrounded.
2. Open chat and send both ways, including Unicode, emoji and multiline text.
   Verify participants and sent checkmarks (accepted by host, not read receipts).
   No Internet/mobile data is needed.
3. Add a third phone. New messages appear once on all phones with the right sender.
   A first-time participant does not receive history from before joining.
4. Keep a draft, leave the chat screen and return. The draft/history must remain.
5. Move a client out of range, or deliberately Disconnect and rejoin later.
   Other phones continue sending. Native loss or the 35-second heartbeat timeout
   disables sending. Draft editing remains available.
6. Return within range. If Wi-Fi Direct does not reconnect itself, rejoin the same
   host using discovery/QR/NFC. A restored connected snapshot resumes chat; if only
   the TCP connection failed while Wi-Fi stayed connected, use Retry chat.
7. Verify the returning participant keeps its identity, retains previous messages,
   receives missed messages in order, and can send again. There must be no duplicate
   participant or message. Repeating Retry chat must not erase conversation state.
8. Interrupt connectivity around a send. The outgoing entry becomes failed or
   unconfirmed and its draft remains. After reconnecting, replay may confirm it;
   otherwise Retry message must reuse the same request rather than duplicate it.
   A host confirmation is not a recipient delivery/read receipt.
9. With a client absent, send over 500 messages. Upon return it gets the retained
   messages and an explicit warning that some missed history is unavailable.
10. End the host group. Connected clients should show Chat session ended if the
    ending frame arrives. Force-stopping/range loss can only show disconnected
    until a reconnect establishes whether the old session still exists. A restarted
    host rejects the old resume attempt; Start new chat requires confirmation and
    clears old local history/draft/outbox without sending them to the new group.
11. Repeat with mobile data enabled to check physical-device Wi-Fi Direct routing.

Automated tests use real loopback sockets, three-party broadcasts and a proxy that
cuts a connection after host acceptance but before the sender sees confirmation.
They also check replay gaps, retry expiry, changed sessions, malformed input,
native-state transitions, navigation and stale-operation cancellation. They do
not emulate radio behavior, OEM dialogs or background scheduling.

## Wire format v2

TCP port **45871**. The host binds only to the actual group-owner IP supplied by
Android. Frames are UTF-8 JSON objects followed by LF, with `v: 2`. Embedded
newlines are JSON-escaped. Frames above 32 KiB and malformed/unsupported frames
close the offending socket. Split/coalesced reads are supported. Protocol v1 peers
must be updated; there is no silent downgrade. QR/NFC invitation schema stays v1.

Connection setup:

- Client `hello`: `name` (1–32 UTF-16 units), `after` (last received host sequence).
  First join uses zero and no credentials. Resume includes `groupId` and `token`
  issued in the previous welcome; display name is not a resume identity.
- Host `welcome`: `selfId`, `groupId`, `token`, `baseline`, `gap`. A valid resume
  preserves the participant ID and name. Unknown credentials or another session
  get `ended` with a reason; the host never falls back to a fresh identity silently.
- Host `roster`: `participants` (`id`, `name`) and a join/rejoin/leave `notice`.
- On resume, the host streams retained `message` frames after the baseline, then
  `synced` with `through` equal to the current host sequence. Sending is enabled
  only after welcome, roster and complete synchronization. Each subsequent live
  message must advance the cursor by exactly one.
- A new participant's baseline is the current host sequence and it receives no
  old messages. A returning participant's baseline is its cursor or the oldest
  retained sequence minus one, whichever is larger. `gap: true` means expired
  messages could not be recovered and produces a persistent warning for this chat.

Message exchange:

- Client `send`: `id` (positive decimal request counter, increasing within this
  participant session) and `text` (nonempty, at most 2000 UTF-16 units).
- Host `message`: canonical `id` (`senderId:requestId`), `senderId`, `name`, `text`,
  UTC ISO-8601 `time` and increasing `sequence`. Sender identity comes from the
  socket. The broadcast echo confirms host acceptance to the sender.
- Retrying an accepted request with identical text returns `ack` with the original
  canonical message to that sender only. It does not broadcast another message.
  Changing the text under an existing request ID gets `rejected` (`id`, `reason`).
- The host retains the last 1000 accepted requests. It also retains each identity's
  highest accepted request counter. If an older request is no longer cached, it
  returns `rejected` rather than risk creating a duplicate. This may also reject
  an unaccepted older request after a newer one was accepted. The UI leaves it
  failed/unconfirmed; this is deliberately not an exactly-once delivery guarantee.
- Either side `ping` / `pong`: heartbeat every 10 seconds, socket timeout after
  35 seconds without incoming bytes. Host `ended` explains deliberate session
  termination or rejected resumption. Unexpected abrupt loss remains retryable.

## Limits and lifecycle

- At most 15 client sockets plus the host; silent handshakes expire in 5 seconds.
- At most 128 issued resume identities per host session, including disconnected
  participants. At capacity, new joins require the host to start a new session.
- 500 host text messages available for replay; 1000 accepted requests cached.
- Each phone retains 500 messages/notices for display and up to 50 unconfirmed
  outgoing entries. Drafts, counters, credentials and caches are in memory only.
- Initial TCP connection retries up to five times (2-second timeout, 500 ms delay).
  Synchronization has a 5-second timeout; host confirmation has a 6-second timeout.
- Native client network restoration attempts resumption. TCP-only failure offers
  Retry chat. Uncertain outgoing sends require explicit retry and keep the original
  ID/text/session. Replay reconciles those already accepted by the host.
- Client Disconnect pauses reconnect attempts but retains history, draft and resume
  credentials. Explicitly rejoining the same running group resumes it, just like
  temporary network loss. Creating a group or explicitly starting a new chat clears
  old conversation state. Host loss ends the host session; changing roles does not
  migrate it. Process restart still loses all in-memory state.
- Join/leave notices reflect locally observed rosters and are not replayed events.

## Security and platform limits

Plaintext trusted-participant prototype: no TLS, authenticated identity, end-to-end
encryption, disk storage, or general abuse/rate protection. Resume tokens are random
in-memory bearer secrets sent over plaintext TCP. They distinguish reconnects but
do not establish a secure identity; do not log/persist them or treat Wi-Fi passwords
as application authentication. See roadmap.md for the encryption milestone.

The app must remain foregrounded. No Android foreground service, background
guarantee, automatic host migration, multi-hop or iOS networking adapter is included.
The shared session and Dart TCP layer can be reused with a validated iOS adapter.

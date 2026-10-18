# Chat prototype

## Usage and hardware checks

1. Install the updated app on two Android phones. Enter different chat names.
2. Create a group on one phone and join from the other using QR or discovery.
3. Open chat on both. Verify the participant count is two, send both ways, and
   check Unicode, emoji and multiline text. No Internet or cellular data is needed.
4. Add a third phone. Verify each new message from any phone appears once on all
   three, with the correct sender. Newly joined phones do not receive old history.
5. Disconnect one client from the connection screen. Remaining phones should see
   its leave notice and an updated participant list and still exchange messages.
6. End the host group. Clients should show disconnected and disable sending.
   Recreate/rejoin the group and confirm a fresh chat works.
7. Move a client out of range or force-stop the host. Disconnect should be detected
   by native updates or the TCP heartbeat timeout (about 35 seconds). Keep an
   unsent draft and verify it is retained. Retry chat after network recovery.
8. Repeat with mobile data enabled to check real-device Wi-Fi Direct routing.

Automated loopback tests cover three-party broadcasts, identities, Unicode,
framing, malformed/oversized input, duplicate requests, leave/host loss, restart
and cancellation. They do not replace physical Wi-Fi Direct tests.

## Wire format v1

TCP port **45871**. The host binds only to the group-owner IP supplied by Android.
Frames are UTF-8 JSON objects followed by LF, with `v: 1`. Embedded newlines in
text are JSON-escaped. The decoder handles split/coalesced TCP reads and rejects
frames above 32 KiB before decoding them. Unsupported/malformed frames close only
the offending connection.

- Client `hello`: `name` (1–32 characters).
- Host `welcome`: assigned `selfId` and random `groupId`.
- Host `roster`: `participants` (`id`, `name`) and a join/leave `notice`.
- Client `send`: random request `id` and nonempty `text` (at most 2000 UTF-16 units).
- Host `message`: canonical `id` (`senderId:requestId`), `senderId`, `name`, `text`
  and UTC ISO-8601 `time`. Sender identity comes from the socket, never client input.
- Either side `ping` / `pong`: heartbeat every 10 seconds; 35 seconds without
  incoming bytes closes the connection.

The client becomes ready after welcome and roster. Initial connection attempts
retry up to five times (2-second connection timeout, 500 ms delay). Handshake
timeout is five seconds. Host message echo confirms acceptance within six seconds;
it is not a recipient delivery/read receipt. An ambiguous timeout keeps the draft
and warns the user to check the conversation before resending.

The host supports 15 client sockets plus itself. The last 1000 message IDs are
deduplicated and the last 500 messages/notices retained locally. Retrying starts
a new session, clearing history; no offline queue or history replay is provided.

## Security and lifecycle limits

Plaintext, trusted-participant prototype: no app-level authentication, TLS,
end-to-end encryption, persistent identity, or abuse/rate protection. Names are
not unique or verified. The Wi-Fi password is not an application security model.
Do not use this prototype for sensitive conversations.

The app must remain in the foreground. No Android foreground service, background
guarantees, automatic host migration, multi-hop, or iOS network adapter is included.
The Flutter screen and Dart sockets can be reused when an iOS-compatible network
adapter is implemented and validated. Dart socket API reference:
https://api.dart.dev/dart-io/Socket-class.html

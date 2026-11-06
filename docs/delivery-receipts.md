# Message delivery checks

Implemented milestone: application-level receipt acknowledgements, not read receipts.

- One check: the host accepted the message.
- Two checks: at least one other client received it from the host.
- Three checks: every intended client received it. Completion takes precedence
  over two checks, so one recipient can move directly from one to three.
- The host snapshots connected clients at acceptance, excluding the sender.
  Leaving does not reduce that set; later joins do not expand it. The host itself
  is covered by the first check. No intended clients means one check only.
- Tap checks for recipient names and received/awaiting-confirmation status.
  Pending and failed host acceptance keep their existing sending/retry UI.
- A receipt means the recipient app validated and recorded the message in memory,
  not that someone opened/read it or that it was stored durably.

## Protocol v3

All phones must update. Discovery advertises chat protocol 3; invitation schemas
remain public v1/private v2. Older chat versions are rejected without downgrade.

Clients send `received` with canonical message `id` and `sequence` after recording
each `message`, including replay. The host binds each receipt to the socket's
resumed participant identity; a client cannot acknowledge for another identity.
Unknown/expired receipts and receipts from non-targets are ignored. Wrong sequence
numbers and duplicate receipts never advance delivery.

After synchronization, clients resend receipts for retained incoming messages,
including those already covered by the replay cursor. This recovers a receipt
lost after the app recorded its message. Duplicate receipts are harmless.

The host sends `delivery` only to the message's sender, containing `id`, `sequence`,
and `recipients` (`id`, `name`, boolean `received`). Targets are fixed at acceptance.
The host sender reads the same state locally. Sender resumption resends retained
delivery snapshots independently of the message replay cursor, so receipts received
while the sender was away can still update old messages. Duplicate send retries
return the original acceptance and current delivery state without changing targets.

Delivery state is bounded to the last 1000 accepted messages at the host and 1000
snapshots at a client. Session reset clears it. No receipt is inferred from a TCP
write, roster departure or time passing. Missing/expired confirmations remain
unconfirmed; replay beyond 500 retained texts cannot guarantee delivery recovery.
Receipts share the existing plaintext/trusted-host limitations; they are not
cryptographic proof of delivery.

## Acceptance

Automated: delayed receipts, partial/all delivery, duplicate/wrong/forged receipts,
fixed targets across leave/join, recipient replay, sender resumption, duplicate
send retry, empty recipient set, host/client sends, reset and bounded retention.
Widget checks cover all three levels and accessible delivery details.
Hardware: install the same build on at least three phones, send both ways, interrupt
one recipient, rejoin, and check delivery details against messages on each phone.
Radio/lifecycle interoperability remains a separate physical-device check.

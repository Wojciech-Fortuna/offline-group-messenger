# C2 identity, NFC enrollment and storage design

Implementation baseline, 2026-11-08. This is an application protocol using standard
cryptographic formats, not an independently audited security claim. C2 adds trusted
contacts; it does not encrypt existing chat or grant group membership.

## Cryptography and identity

Use Android Keystore P-256 signing keys, generated once per installation and never
exported to Dart or disk. Identify a device by SHA-256 of its DER SubjectPublicKeyInfo.
Use Nimbus JOSE + JWT 10.10 for compact JWS ES256 signing/verification, including
ECDSA signature encoding; do not implement elliptic-curve arithmetic or a key exchange.
Only ES256 and our exact protected header/type are accepted; no remote key URLs,
algorithm negotiation, unsigned tokens or caller-supplied private keys.

References: [JWS RFC 7515](https://www.rfc-editor.org/rfc/rfc7515.html),
[Nimbus](https://connect2id.com/products/nimbus-jose-jwt/download),
[Android Keystore](https://developer.android.com/privacy-and-security/keystore).
Hardware backing depends on the device; do not promise StrongBox on all phones.

## Mutual NFC enrollment

Use a distinct HCE application ID, F04F46464C494E4502, and bounded ISO-DEP chunks.
One user chooses Receive contact, the other Read contact. Both apps stay foreground,
unlocked, in the explicitly enabled pairing screen. No QR, BLE or public discovery
substitute. Existing group invitations keep their original AID and behavior.

Exchange public keys, chosen names and fresh 256-bit nonces. Both endpoints sign
the same role-ordered transcript, including protocol/version, both identities,
names and nonces. Verify both possession proofs before creating a pending contact.
Display a shared 128-bit transcript comparison code on both screens; both people
must compare it and explicitly confirm. NFC proximity alone is not authentication
against relay/substitution. Never verify merely because a key arrived over NFC.

Confirmation receipts are signed and bound to the exact transcript. A contact
becomes verified only after local confirmation and receipt of the peer's signed
confirmation. Keep the phones together for confirmations; interrupted attempts
remain pending and are safe to repeat. A new attempt uses fresh nonces and requires
confirmation again. A verified contact is deduplicated by fingerprint, never name;
a changed key is a different, unverified identity. Re-pairing cannot unblock a
blocked contact. Cancellation cannot silently approve or replace an identity.

Bound each NFC attempt to 60 seconds, one peer and at most 8 KiB per exchange.
Reject invalid versions, keys, signatures, roles, lengths and transcript bindings.
Stop on backgrounding, lock, cancellation and expiry. Persist pending state before
displaying confirmation and confirmed state before acknowledging completion.
Lost final replies may leave one side pending; repeating pairing repairs this
without duplicates or automatically trusting a new key.

## Storage and lifecycle

Store identity metadata, contact public keys, names, pending transcript/approval
state, verified state and block state in a versioned AES-256-GCM encrypted file.
The encryption key is a separate non-exportable Android Keystore key. Fresh IV per
write, authenticated schema context, AtomicFile replacement and an application-wide
lock prevent torn/concurrent updates. Keep the file in noBackupFilesDir and disable
application backup/transfer of identity state. Never log keys, receipts or payloads.

Only create keys for an empty installation. Missing/inaccessible keys, corrupted
data or an unsupported schema fail closed and surface an actionable error; never
silently generate a replacement identity for existing contacts. An explicit reset
deletes contacts and keys and requires NFC pairing again. Uninstall/key loss has
the same trust consequence. Local deletion removes trust; blocking preserves a
tombstone and prevents incoming calls/re-pairing until explicit unblock. Neither
operation removes somebody from a chat group. Bound the store to 256 contacts.

## Binding to C3 calls

Use these signing identities to authenticate versioned directed call-control JWS
messages, including both identity fingerprints, group/session, call ID, fresh
session challenges, sequence numbers and the complete SDP/ICE contents. Verify
against the saved contact, never a key supplied by a signaling host. Signed SDP
binds the WebRTC DTLS fingerprint; WebRTC DTLS-SRTP supplies the media key exchange
and encryption. The host may route signaling but cannot substitute an endpoint.
No microphone before acceptance; no unverified/blocked contact may ring. Future
BLE discovery secrets/encrypted invitations need their own C4 design before use.

## Validation

Automate wrong-key/tampered signatures, algorithm/type rejection, replay/transcript
mixing, self-pairing, duplicates, pending/confirmed recovery, block/delete, malformed
and oversized APDUs, and cancellation. Check encrypted file round trips, corruption
and key-loss behavior on Android. On two phones verify both NFC roles, interrupted
taps and process restart, and regress existing private group invitations. Software
checks alone do not close NFC or C1 physical acceptance.

## C2b implementation status

Implemented: Nimbus ES256 identity adapter, native Android Keystore signing and
AES-GCM storage keys, atomic encrypted no-backup contact store, serialized native
bridge and typed Dart repository. Pending/approval state survives serialization;
verified contacts are deduplicated and blocked contacts cannot be paired again.
All native unit tests and Flutter analysis pass, including new signature tampering,
wrong-key, restart, transcript, block/delete and failed-write tests. Device-backed
Keystore/file corruption and NFC acceptance still require physical validation.
No contact UI or production call feature is included in this storage milestone.

## C2c implementation and manual check

Implemented next: a distinct chunked NFC contact service, mutual transcript proofs,
comparison/confirmation UI and signed approval receipts. Contacts is accessible
from the home toolbar. Rename, block, delete and explicit identity reset are present.
Pairing is foreground-only and expires after 60 seconds. Switching to invitation
NFC cancels contact NFC and vice versa. Private invitation behavior stays separate.

Native unit tests pass for mutual approval, fresh-session replay rejection,
interrupted/repeated enrollment and APDU bounds. All 61 app tests and analysis pass,
including explicit confirmation UI, cleanup and existing group invitation checks.

Device procedure: open Contacts > Add contact by NFC on both phones, enter names,
choose Receive on one and Read on the other. Hold NFC areas together, compare the
entire code, then confirm on both while keeping the link. Both must show saved and
verified. Restart both apps and inspect the saved contacts. Repeat with an interrupted
tap, duplicate pairing and a blocked contact; regress private group invitations.
No phones were connected during this software check, so hardware NFC/Keystore
acceptance remains pending. Calls are not exposed by this milestone.

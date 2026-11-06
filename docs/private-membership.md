# Private group membership and rejoining

This milestone keeps one current conversation in memory; it does not add durable
storage or multiple independently saved conversations.

- First admission to Private still requires NFC. No QR or public advertisement.
- After a successful chat handshake, retain the NFC network invitation locally.
  Find nearby groups shows public discoveries and a separately labelled remembered
  private group. A remembered entry is not evidence that the host is in range;
  Rejoin checks availability by connecting using its saved network credentials.
- Deliberate participant disconnect preserves the conversation, identity, draft
  and remembered invitation. Rejoin uses the same resume token, not a new admission.
- The host can remove current or offline private members from Participants.
  Removal requires confirmation and is enforced by the host: revoke the resume
  identity, close its chat socket, and rotate the shared initial-admission secret.
  Rotate the native NFC payload first and stop any active NFC sharing. If native
  rotation fails, report failure and leave membership unchanged.
- Existing non-removed members resume with their own tokens after rotation.
  Unused/copied older NFC invitations stop admitting new identities. Fresh NFC
  invitation from the host is required to admit again, including a removed person.
- A removed online client receives an ended/revoked frame; an offline client learns
  removal on its next resume attempt. Clear its remembered entry then; retain its
  local history. It cannot receive new chat messages through the revoked identity.
- Starting a new conversation or terminating the process clears the remembered
  entry. Ending/restarting the host ends the old session. No host migration.

This is application membership, not Wi-Fi eviction or encryption. A removed device
may still know the Wi-Fi password and observe plaintext traffic. An offline phone
cannot know it was removed until it contacts the host. Do not claim radio invisibility
or cryptographic revocation; authenticated encryption remains a separate milestone.

## Discovery recovery

MI 9 inspection showed service requests still registered with discovery stopped.
Retry service discovery for a bounded foreground search, first with the specific
TXT request and then all DNS-SD records for device interoperability. Always filter
responses by this app's public markers and current protocol. Never expose generic
Wi-Fi peers or private hosts. Log only operation/result counters, not credentials,
raw records or device identities. Physical testing in both host/client directions
is required; retries cannot guarantee every OEM radio combination works.

## Acceptance

- Leave/rejoin a private group without a new NFC tap, preserving history/identity.
- An outsider never gains a remembered private entry simply from scanning.
- Remove online/offline member; old resume and fresh admission with old invitation
  both fail. Other established members still resume. Fresh NFC can invite again.
- Native rotation failure does not pretend removal succeeded; reset/end races
  cannot remove members of a replacement session.
- Public search retries are bounded and cancelled on join/disconnect/detach.
  Private stays hidden, and nearby public results survive a completed search until
  their normal expiration/next explicit search.

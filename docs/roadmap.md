# Implementation roadmap

This is the canonical milestone order. Keep README, architecture, protocol and UI
notes consistent with implemented behavior. Commit each milestone separately.

## 1. Align documentation (complete)

Record the existing Android Wi-Fi Direct, QR/NFC invitation and TCP chat features;
remove obsolete claims that chat is missing. iOS remains a capability stub.

## 2. Reliable session recovery (implemented; hardware validation outstanding)

Goal: a temporary client interruption must not erase conversation history or
duplicate a message whose host confirmation was lost.

- Extract a session controller from HomeScreen. Keep history, draft and outgoing
  message state independent of chat-screen and socket lifetimes.
- Distinguish reconnecting to an existing group from explicitly starting/joining
  a new conversation. Keep stable participant identity within a resumed session.
- Retain message request IDs on retry. The host must acknowledge previously
  accepted requests again without broadcasting a second message.
- Add a versioned resume handshake, ordered bounded replay of missed messages,
  and an explicit warning when retained history cannot fill the entire gap.
- Show pending, host-confirmed and failed states. Keep uncertain sends available
  for explicit retry; do not silently send them into a different group.
- Host departure ends the session. No host migration, disk persistence,
  background guarantee or recipient delivery/read receipts in this milestone.

Automated acceptance: three-party chat, interrupted client, messages while absent,
resume with the same identity, ordered replay without duplicates, lost confirmation
and retry, bounded-history overflow, changed/ended host session, cancellation and
draft preservation across navigation. Existing invitation/connection tests pass.

Implemented in ChatSessionController and chat protocol v2. Automated tests include
a TCP proxy that cuts the sender's connection after host acceptance, bounded
replay/acceptance expiry, native snapshot recovery and stale-operation cancellation.
Recovery is automatic on a restored native connection; TCP-only failures use
Retry chat. Uncertain message sends require explicit Retry message.

Hardware acceptance (outstanding): run wifi-direct-testing.md, chat-protocol.md and
nfc-testing.md on two/three phones. Include range loss and return, mobile data
enabled, and host departure. Record phone models, Android versions and outcomes.
Automated loopback tests do not establish physical-radio interoperability.

## 3. Authenticated encryption

Preceding usability/admission milestone (implemented): deliberate participant
leave/rejoin now retains history; successful sends use a small checkmark instead
of repeated Host confirmed text. Public groups advertise through app-specific
DNS-SD; private groups use NFC-only admission with no QR fallback or public
advertisement. See group-modes.md. These changes do not implement encryption.

Define participant admission, host trust, invitation authentication and key
lifecycle before selecting/implementing a reviewed protocol. Wi-Fi passwords,
display names and resume tokens alone do not provide authenticated encryption.

## 4. Durable storage

Persist identity, history and outgoing state with an explicit retention/deletion
policy and storage-security design. Verify process restart and crash recovery.

## 5. Background operation

Implement and validate Android lifecycle/notification behavior. Public service
discovery is implemented; verify it across physical phone models and refine
recovery based on observed OEM behavior.

## Later / feasibility tracks

Validate Android-to-iPhone networking on physical devices with macOS/Xcode before
promising iOS support; bring this check forward if cross-platform use is required.
Host migration and multi-hop are separate protocol milestones after single-host
reliability. Localization and additional UI polish follow demonstrated needs.

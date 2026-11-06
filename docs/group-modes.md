# Public and private groups

Choose a mode before creating a group. On phones supporting NFC sharing, Private
is the default. Phones without NFC sharing can host public groups. Changing mode
requires ending the current group and creating another one.

## Private: NFC invitations only

- Host: create a Private group, open Share via NFC, and tap each joining phone
  while it has Join via NFC open. Joining still requires confirmation.
- There is no host QR button. The native QR invitation method rejects private
  groups; the scanner rejects private payloads copied into a QR code.
- Private hosts do not publish this app's DNS-SD service record. They do not appear
  in this app's public-group discovery list. Android's underlying Wi-Fi Direct
  device/network can still be detected: this is not radio invisibility.
- The NFC invitation includes network credentials and a random 256-bit admission
  secret. New TCP participants must supply that secret before receiving an identity,
  roster or chat messages. Knowing only the network password is insufficient for
  ordinary chat admission. Resuming participants use their existing resume token.
- Share NFC only during an intentional tap. Sharing ends after 60 seconds, when
  backgrounded, on leaving its screen or when host connectivity is lost.

NFC is a way to exchange invitations, not the ongoing message transport. Messages
continue over Wi-Fi Direct/TCP; the phones must remain within the host's range.

## Public: discovery, QR or NFC

Public hosts advertise the `_ogm._tcp` Wi-Fi Direct DNS-SD service with app, protocol
and public-mode markers. Find nearby groups lists matching public service responses;
generic Wi-Fi devices and private hosts are excluded. Advertisements never contain
Wi-Fi passwords or admission/resume tokens. Entries expire after 60 seconds without
a fresh response, so a recently ended public group can briefly remain listed.

QR and NFC are available as alternatives to discovery. Public chat admits devices
that reach its host. Discovery records and device names are not authenticated.
Both phones need the updated app for public service discovery; older versions
using generic peer lists can still detect a private Wi-Fi device at the radio level.

## History and limits

Leaving as a participant pauses reconnect attempts without clearing history or
drafts. Choose Rejoin on the remembered private entry under Find nearby groups
to resume the same chat identity and receive retained missed messages. Admission
does not have to be repeated for a TCP-only reconnect with a valid resume token.
Ending the host group ends that chat session; starting a new conversation is
explicit. History, invitations and session credentials are not persisted to disk.

The remembered entry appears only after successful private admission and does not
claim the host is currently nearby. Hosts can remove online/offline members;
revoked identities cannot resume and old admission invitations expire. Other
established members still resume. See private-membership.md for rotation and limits.

Private currently means NFC-invited membership and no in-app public advertisement.
It does NOT mean encrypted, anonymous, or invisible. Admission/resume tokens are
reusable bearer secrets and TCP is plaintext. An invited participant can copy its
credentials, and someone able to observe the TCP stream could steal tokens. NFC
does not prove a person's identity. Authenticated encryption remains the next
security milestone; this mode must not be presented as protection for sensitive
conversations.

## Acceptance checks

1. Create Private on an NFC/HCE-capable host. Confirm there is no QR sharing action.
2. Search from another updated app. The private host must not be listed. Repeat
   using a nearby Public host and confirm it is listed and can be joined.
3. Join Private through NFC and send both ways. A phone on the Wi-Fi network without
   the admission secret must receive no roster or messages from the chat server.
4. Disconnect a participant, send while it is absent, tap/rejoin, and check history,
   identity and missed messages. Retry chat without another NFC tap after TCP loss.
5. Stop sharing, background, end/recreate groups, and switch Public to Private.
   Check old callbacks cannot revive advertisements or old NFC sharing payloads.
6. Repeat on different Android/OEM pairs. DNS-SD discoverability and NFC reliability
   require hardware checks; automated tests cover filters, contracts, admission,
   resume and UI behavior, not radio interoperability.

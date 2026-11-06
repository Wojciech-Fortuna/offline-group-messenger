# Design direction

Use Flutter's Material 3 widgets with a teal seed color, neutral surfaces,
system light/dark mode, readable type and an 8 px spacing rhythm.
Use Figma optionally for collaborative screen sketches; Flutter implements the UI.

The same widgets serve Android and iOS. Use adaptive widgets for controls where
platform conventions matter, and test safe areas, keyboard insets, text scaling,
touch targets and accessibility labels on both platforms.

## Current flow

Home (name, Create group, discovery or QR/NFC join, connection status) ->
Chat (messages, composer and participants). Leave group is on the home screen;
the host confirms ending the group. A separate lobby is not implemented.

Discovery appears on the home screen with searching, empty, denied and error
states. Use text alongside color to explain connection status. Chat shows pending,
host-accepted (one check), received by at least one other client (two checks),
received by all targeted recipients including the host (three checks), and failed/unconfirmed states.
Tap checks for live per-recipient details. These are not read receipts. Targets
are fixed at host acceptance. Two-phone conversations reach three checks in both
directions; a host sending alone stays at one. Render three distinct, closely
overlapping ticks while preserving the 48-pixel delivery-details touch target.
See [delivery-receipts.md](delivery-receipts.md) and [roadmap.md](roadmap.md).

## Connection prototype

The home screen offers Private/Public selection, Create a group and Find public groups. Discovered public hosts
have Join actions; connected sessions show the device role and actual host IP.
Users can cancel discovery/connection or disconnect; hosts confirm ending the
group. Permission failures and disabled Wi-Fi/Location have recovery messages.
Users enter a display name before connecting. The host starts its TCP chat server
automatically, and Open chat shows messages, participants and join/leave notices.
The session controller retains drafts across navigation and keeps history on retry.
Leaving as a participant retains the conversation; choosing to rejoin resumes the
same live host session. Ending the host group still ends the session for everyone.
Failed/unconfirmed sends have Retry message actions and retain their request IDs;
the composer also reuses the ID when retrying the unchanged failed draft. A changed
draft creates a separate message. Drafts can be edited while disconnected, but
sending requires a ready connection. Missing replay history has a visible warning.
An ended session shows Start new chat when a network is connected, with confirmation
before discarding the previous local history, draft and outbox.
Connected public hosts can show/hide a group QR invitation. Android 10+ clients can scan,
review the group name and confirm joining. Invalid codes stay on the scanner
screen with guidance; camera denial explains how to enable access. The QR uses
a white background and black modules for readability in either theme. NFC sharing
and reading use dedicated screens and the same join confirmation.
Private is the default on NFC-sharing-capable phones; otherwise Public is selected.
Private hosts have no QR action, and their NFC error guidance never suggests QR.
The mode description explains that private groups are absent from app discovery,
but their Wi-Fi signal is detectable and chat is not yet encrypted.

Move UI strings into Flutter localization resources when adding more screens or
a second language. Keep session state and connection coordination in the existing
session controller rather than adding networking logic to widgets.

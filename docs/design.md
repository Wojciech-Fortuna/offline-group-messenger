# Design direction

Use Flutter's Material 3 widgets with a teal seed color, neutral surfaces,
system light/dark mode, readable type and an 8 px spacing rhythm.
Use Figma optionally for collaborative screen sketches; Flutter implements the UI.

The same widgets serve Android and iOS. Use adaptive widgets for controls where
platform conventions matter, and test safe areas, keyboard insets, text scaling,
touch targets and accessibility labels on both platforms.

## Current flow and next milestone

Home (name, Create group, discovery or QR/NFC join, connection status) ->
Chat (messages, composer and participants). Leave group is on the home screen;
the host confirms ending the group. A separate lobby is not implemented.

Discovery appears on the home screen with searching, empty, denied and error
states. Use text alongside color to explain connection status. The next milestone
adds pending, host-confirmed and failed message states. Host confirmation must
not be labelled recipient delivery or a read receipt. See [roadmap.md](roadmap.md).

## Connection prototype

The home screen offers Create a group and Find nearby devices. Discovered peers
have Join actions; connected sessions show the device role and actual host IP.
Users can cancel discovery/connection or disconnect; hosts confirm ending the
group. Permission failures and disabled Wi-Fi/Location have recovery messages.
Users enter a display name before connecting. The host starts its TCP chat server
automatically, and Open chat shows messages, participants and join/leave notices.
The current prototype retains drafts on send failure within the chat screen;
session recovery will preserve them across navigation and keep history on retry.
Connected hosts can show/hide a group QR invitation. Android 10+ clients can scan,
review the group name and confirm joining. Invalid codes stay on the scanner
screen with guidance; camera denial explains how to enable access. The QR uses
a white background and black modules for readability in either theme. NFC sharing
and reading use dedicated screens and the same join confirmation.

Move UI strings into Flutter localization resources when adding more screens or
a second language. Extract a session controller during the recovery milestone;
it will own conversation state and connection coordination outside the widgets.

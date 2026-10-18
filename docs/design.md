# Design direction

Use Flutter's Material 3 widgets with a teal seed color, neutral surfaces,
system light/dark mode, readable type and an 8 px spacing rhythm.
Use Figma optionally for collaborative screen sketches; Flutter implements the UI.

The same widgets serve Android and iOS. Use adaptive widgets for controls where
platform conventions matter, and test safe areas, keyboard insets, text scaling,
touch targets and accessibility labels on both platforms.

## Planned flow

Home (name, Create group, Join group) -> Lobby (participants and status) ->
Chat (messages, composer, participants and Leave group).

Joining adds a discovery screen with searching, empty, denied and error states.
Use text alongside color to explain connection status. Distinguish sent,
delivered and failed messages; do not show delivery before acknowledgement.

## Connection prototype

The home screen offers Create a group and Find nearby devices. Discovered peers
have Join actions; connected sessions show the device role and actual host IP.
Users can cancel discovery/connection or disconnect; hosts confirm ending the
group. Permission failures and disabled Wi-Fi/Location have recovery messages.
The unused name field was removed until participant identity/messaging exists.
The screen explicitly states that text messaging is not implemented.
Connected hosts can show/hide a group QR invitation. Android 10+ clients can scan,
review the group name and confirm joining. Invalid codes stay on the scanner
screen with guidance; camera denial explains how to enable access. The QR uses
a white background and black modules for readability in either theme.

Move UI strings into Flutter localization resources when adding more screens or
a second language. Add screen controllers / state management when real session
state exists; avoid adding a large framework solely for a static starter screen.

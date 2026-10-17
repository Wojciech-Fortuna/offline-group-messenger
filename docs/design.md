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

## Scaffold

The home screen displays real bridge capability information, a name field and
disabled group actions. It explicitly labels networking as unimplemented.
The name is not yet stored or used to start a group.

Move UI strings into Flutter localization resources when adding more screens or
a second language. Add screen controllers / state management when real session
state exists; avoid adding a large framework solely for a static starter screen.

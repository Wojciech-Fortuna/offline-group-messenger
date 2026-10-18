# Android Wi-Fi Direct hardware checks

Fully stop and rerun the app after updating Kotlin or manifest permissions.
Flutter hot reload alone does not rebuild the native plugin.

## Two-phone smoke test

1. Install the new debug build on two physical Android phones. Enable Wi-Fi and
   Location on both. Internet/mobile data are not required.
2. On phone A, select Create a group. Grant Nearby devices on Android 13+, or
   precise Location on older Android. Wait for Connected / You are the host.
3. On phone B, select Find nearby devices and grant permissions. Select Join
   beside phone A. Accept Android's system invitation on either phone if shown.
4. Wait for Connected / Participant on B. Both phones must report the same host
   IP. Record the actual value; do not assume a particular address.
5. Disconnect B. B must clear its host IP and permit joining again; A should keep
   its group. Join again, then end the group on A and confirm B loses connection.
6. Repeat with host/client roles reversed, then add a third phone if available.

The current list contains generic Wi-Fi Direct peers, not only this app.
The host may appear under its Android device name. There are no text messages yet.

## QR invitations

1. Create a group on phone A and wait until it reports that it is the host.
2. Tap Show group QR code.
3. On phone B (Android 10+), tap Scan group QR code and allow camera access.
4. Scan A's code, confirm the displayed group name, and grant Nearby devices /
   Location permission if requested. Keep Wi-Fi enabled on both phones.
5. Wait for Connected and verify the same host IP on both phones. Scanning or
   accepting a request alone must not be shown as a successful connection.
6. Test denying camera access, scanning an unrelated QR, cancelling confirmation,
   scanning while offline, hiding the host QR and ending the group.
7. Try an old code with the host unavailable: joining should time out cleanly.

The QR contains the Wi-Fi network name and password. It is not a one-time token
or a messaging identity. Anyone holding a copy can attempt to join while those
credentials remain valid; hiding the image does not revoke them. The app does not
save the invitation or include credentials in connection events/logs.
The on-screen QR clears when the host disconnects. Actual credential-based joining
and camera performance still require verification on physical devices.

## Failure and lifecycle checks

- Deny permission and retry; also test permanently denied permission through
  Android app settings. Approximate location is insufficient on older Android.
- Turn Wi-Fi off; requests should fail with a recovery message. Turn it back on
  and retry without restarting the app.
- Turn Location off while discovering; enable it again and retry.
- Cancel discovery and an unaccepted invitation, then immediately create/join.
- Reject or ignore an invitation: it must not show connected or an invented IP;
  cancellation remains available and the connecting timeout eventually reports failure.
- Rotate or background/foreground the app during discovery and while connected.
  Check current state is restored, with no duplicate event subscriptions.
- Revoke permission in settings, return, then retry with permission granted.
- Stop/relaunch the app and inspect any surviving system group. Explicitly
  disconnect before leaving; process death cannot guarantee cleanup callbacks.

## Automated checks

flutter analyze
flutter test
cd packages/offline_connectivity && flutter test
flutter build apk --debug (from the repository root)

Dart tests validate the bridge and GUI; they do not emulate Android radio behavior,
OEM system dialogs, or permission lifecycle callbacks. Native compilation is
checked separately. Record device/Android versions when reporting hardware results.

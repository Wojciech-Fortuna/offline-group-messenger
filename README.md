# Offline Group Messenger

Flutter GUI shared between Android and iPhone, with **Kotlin for Android
connectivity** and a **Swift stub for future iOS connectivity**.

## Status

This is a project scaffold, not a working messenger. It includes a shared Material
3 home screen, light/dark themes, native device-capability reporting, message
models and a transport interface. Creating/joining groups and sending messages
are not implemented; their UI actions are disabled.

## Structure

```text
lib/
  app/                         App entry and shared theme
  features/home/               Shared home screen
  core/models/                 Message and participant models
  core/messaging/              Future shared TCP transport contract
android/                       Android app host (Kotlin)
ios/                           iPhone app host (Swift / Xcode project)
packages/offline_connectivity/
  lib/                         Typed Dart API for the native bridge
  android/src/main/kotlin/     Kotlin capability check; Wi-Fi Direct goes here
  ios/Classes/                 Swift capability stub; iOS adapter goes here
  test/                        Bridge contract checks
test/                          App widget checks
docs/                          Architecture, UI direction and bridge contract
```

There is no cloud backend. The intended first transport is an Android-hosted
Wi-Fi Direct group, with Dart TCP code forwarding messages to participants.
iPhone connectivity still needs validation on real devices; Swift does not add
Wi-Fi Direct support to iOS.

## Setup

Use Flutter **3.35.7** (Dart 3.9), Android Studio and an Android SDK. Flutter uses
the generated Android build configuration. Run `flutter doctor` to check tools.
A development SDK downloaded during setup is in `.tools/flutter` and is not
tracked; on this Windows workspace, you can use
`.\.tools\flutter\bin\flutter.bat` in place of `flutter`.

```sh
flutter pub get
flutter analyze
flutter test
cd packages/offline_connectivity
flutter pub get
flutter test
cd ../..
flutter run
```

Use a physical Android device when implementing/testing Wi-Fi Direct.
The initial dependency downloads require Internet access; the eventual chat
session will not.

For iPhone, use **macOS with Xcode** and the iOS tooling reported by
`flutter doctor`. Run `flutter run` with an iOS simulator or device selected.
For signing/configuration, open `ios/Runner.xcworkspace`. Native iOS compilation
cannot be checked on Windows.

## Validation in this workspace

- Flutter static analysis passed.
- Two app widget tests and three connectivity contract tests passed.
- Android APK compilation was attempted, but the Gradle distribution download
  stalled before compilation. The stalled build was stopped; native Android
  compilation remains unverified.
- iOS compilation requires macOS and Xcode and has not been run.

## Design and implementation plan

Use Flutter Material 3 for a shared, accessible UI; Figma is optional for sketches.
See [design](docs/design.md), [architecture](docs/architecture.md) and the
[native bridge contract](docs/connectivity-contract.md).

Next: implement Kotlin Wi-Fi Direct lifecycle and permissions, then the shared
Dart message transport and chat screens. NFC, multi-hop and host migration are
later milestones.

## Original project concept

The project aims to create an **offline group messaging app** that enables communication between multiple phones without Internet access or cellular coverage. Its main use case could be communication among a group of people on a plane, on a train, or in another location without network coverage.

**NFC** would be used to let users join a group quickly and securely. The person creating the group would tap their phone against another person's phone to transfer the group identifier and the information needed to establish a connection. This would eliminate the need to enter codes manually or search for the correct group.

After pairing, communication would take place over **Wi-Fi Direct**, which allows phones to create a local network without a router or an Internet connection. One phone would act as the **Group Owner**, serving as the group's local host. The other phones would connect to it and send messages, which would then be forwarded to all participants in the conversation.

The basic version of the app would support text messages, a participant list, and notifications when someone joins or leaves the group. Messages could also be **encrypted** to keep communication private despite the use of a shared wireless connection.

The main limitation would be the **range of Wi-Fi Direct**: all devices would need to remain within range of the phone acting as the Group Owner. Communication between all devices therefore could not be guaranteed on a large plane or over longer distances. A more advanced extension could introduce a **relay/multi-hop** mechanism, in which phones forward messages to devices beyond the sender's direct range. This would allow the app to form a simple decentralized communication network consisting entirely of users' phones.

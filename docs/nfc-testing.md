# NFC tap invitations (Android prototype)

## Requirements and steps

- Two NFC-capable Android phones with NFC enabled in system settings.
- Host: Wi-Fi Direct and Host Card Emulation (HCE) support.
- Joining phone: Wi-Fi Direct, NFC reader support and Android 10+.
- Install/rebuild the updated APK on both phones; hot reload alone cannot install
  the new native service/manifest. Keep both phones unlocked and the app foregrounded.

1. Create a Wi-Fi Direct group on the host, then open **Share via NFC**.
2. On the other phone open **Join via NFC**.
3. Hold the phones' NFC antennas together, generally near the backs/top edges.
   Antenna placement varies; remove thick/metal cases if necessary. Keep them
   together until the invitation is read, rather than tapping and immediately moving away.
4. The joining phone must show **Join this group?** with the expected network name.
   Cancel first and verify no connection is made. Repeat, confirm **Join**, and
   accept any Android connection prompts.
5. Once connected, open chat on both and exchange messages. NFC carries only the
   invitation; ongoing communication remains Wi-Fi Direct/TCP.

## Recovery and privacy checks on hardware

- Turn NFC off: starting a session should explain how to enable it; QR still works.
- Interrupt a tap: expect a read error or timeout, then use Retry NFC.
- Touch an unrelated NFC tag: it must not join any group.
- Press Back during a read: a late result must not open a confirmation or join.
- Exit the host sharing screen, lock/background the host, end its Wi-Fi group,
  or wait 60 seconds: new reads must not return credentials. Re-enable explicitly.
- Background the joining phone: reading stops and requires Retry NFC on return.
- Wait 30 seconds without tapping: reader timeout, no automatic join.
- Try several phone pairs and antenna alignments. OEM behavior, screen-lock
  settings and HCE routing cannot be validated with Dart mocks or JVM tests alone.

Sharing is not one-time and does not authenticate the reader. Any nearby reader
that knows the application protocol can request the Wi-Fi password during the
explicit sharing window. Expiry stops future reads; it does not invalidate a
password already copied. Do not describe this as secure or encrypted pairing.

## Implementation / protocol

The plugin uses Android reader mode (NFC-A, skip NDEF check) and a non-payment
HostApduService protected by BIND_NFC_SERVICE. No Beam, physical NFC sticker,
Internet access, NFC runtime-permission dialog or new Flutter dependency is needed.

Prototype proprietary AID: `F04F46464C494E4501` (keep XML and Kotlin synchronized).
Review/register an appropriate AID before production distribution to avoid collisions.
This is a custom ISO-DEP protocol, not an NDEF tag or a system-level tap-to-open link.

- SELECT: `00 A4 04 00 09 F0 4F 46 46 4C 49 4E 45 01`.
- Successful SELECT returns a two-byte big-endian payload length followed by `90 00`.
- Read: `00 B0 offsetHi offsetLo length`; 1–200 bytes per response, followed by `90 00`.
- Maximum payload: 2048 bytes of UTF-8 invitation JSON (same schema as QR).
- Unknown commands, out-of-range reads and missing/expired/revoked sharing return
  error status words. Readers reject short replies, inconsistent lengths and errors.
- Revoking or replacing the active payload invalidates an already-selected session.
- HCE replies use only in-memory data; Wi-Fi queries happen before enabling sharing.
  Reader I/O runs on a worker, with per-transceive timeout and generation checks
  to suppress results after cancellation.

## Automated checks

From the repo root: `flutter analyze`, `flutter test`, `flutter build apk --debug`.
From `packages/offline_connectivity`: `flutter test`.
From `android`, using Android Studio's JDK:
`gradlew.bat :offline_connectivity:testDebugUnitTest`.

JVM tests cover chunking, Unicode, revocation, reselection, invalid commands,
malformed/oversized responses and cancellation between chunks. Flutter tests cover
the typed bridge, capability defaults, join confirmation, Back cancellation,
sharing expiry, host loss, background cleanup and disabled-NFC recovery.

iOS remains unsupported; Core NFC reader interoperability and a compatible Wi-Fi
join adapter are separate milestones. No iPhone tap support is claimed here.

References:
- https://developer.android.com/develop/connectivity/nfc/hce
- https://developer.android.com/reference/android/nfc/NfcAdapter
- https://developer.android.com/reference/android/nfc/tech/IsoDep

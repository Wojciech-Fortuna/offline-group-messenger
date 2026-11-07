# Transport Lab

Separate Android package `com.offlinegroupmessenger.offline_transport_lab`.
See [scope and acceptance](../../docs/transport-lab.md). Does not replace Messenger.

From this directory:

```powershell
..\..\.tools\flutter\bin\flutter.bat pub get
..\..\.tools\flutter\bin\flutter.bat analyze
..\..\.tools\flutter\bin\flutter.bat test
..\..\.tools\flutter\bin\flutter.bat build apk --debug
```

BLE: enable Bluetooth, open the lab on both phones. On one choose **Advertise
GATT probe**, on the other **Find lab probes**, then **Test echo** on a result.
Expect a successful random 16-byte write/read echo on both screens. Reverse roles.
Repeat while a Wi-Fi Direct chat group exists. Advertisements end after 60 seconds;
scanning after 30, a connect/echo attempt after 15. Backgrounding stops the probe.
Pre-Android 12 scanning also needs Location permission and system Location on.

No contact identity, secrets, group credentials or chat text are carried by BLE.
Success proves a transport exchange only; it does not establish authentication.

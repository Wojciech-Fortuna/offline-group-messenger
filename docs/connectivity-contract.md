# Native connectivity contract

Channel: com.offlinegroupmessenger/connectivity
Codec: Flutter StandardMethodCodec

## getCapabilities

No arguments. Returns a map:

| Key | Type | Meaning |
| --- | --- | --- |
| platform | string | android or ios |
| wifiDirectSupported | bool | Hardware support; false on the iOS stub |
| implementationReady | bool | false until real connection operations exist |
| description | string | Human-readable capability / implementation status |

This operation does not request permissions or access the network.
Unknown method names return Flutter's notImplemented result.

## Planned methods (not exposed yet)

- createGroup: create an Android-hosted group.
- discoverPeers: start nearby-device discovery.
- joinGroup: connect using a discovered peer identifier.
- disconnect: release the active session.
- Connection events: discovery results, host endpoint, role and failures.

Define and test these payloads before implementing the native adapters.
Keep network discovery separate from TCP chat messages. No credentials, keys,
chat messages or device identifiers should be written to diagnostic logs.

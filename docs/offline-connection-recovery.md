# Offline creation and connection recovery

The product requires no Internet, router association, mobile data, server or DNS
lookup. Wi-Fi radio must remain enabled, with Android's required Nearby devices /
Location permissions and Location mode. Android's INTERNET permission authorizes
local sockets as well; it does not imply an Internet requirement.

Observed hardware report: MI 9 discovers OPPO but remains Connecting; host creation
appears to work only while associated with Internet Wi-Fi. The hardware cause is
not yet established; wireless ADB cannot verify standalone operation after its
infrastructure network is disconnected.

Code changes implemented; physical acceptance remains pending:

- Action timeout previously restored Connecting after invalidating the callback/
  watch token, leaving a state that could no longer progress or time out. It now
  returns a recoverable state and cancels pending negotiation. A group already
  confirmed connected is preserved if the action callback alone is missing.
- Discovery shutdown now completes before connect/create is issued. Queued
  discovery callbacks are invalidated before starting the next Wi-Fi Direct action.
- Group setup must use authoritative P2P state and the actual group interface;
  never an infrastructure Wi-Fi IP or an Internet-connectivity check. If a formed
  host group temporarily omits its IP, query its group interface for a local IPv4.

On Android 10+, create a fresh non-persistent group with locally generated SSID/
password and request the 2.4 GHz band for interoperability. Older Android retains
the supported default createGroup API. Do not log credentials or publish them in
discovery. Continue fetching invitations from the actual created group.

## Hardware acceptance (USB ADB, not wireless ADB)

1. Install the same build on MI 9, OPPO and Huawei. Start the app independently.
2. Disconnect infrastructure Wi-Fi without disabling the Wi-Fi radio. Turn off
   mobile data; keep Location enabled. Confirm no router or Internet is used.
3. Create Public on each phone in turn. Verify a real host group and local host IP.
4. Discover/join in both MI 9/OPPO directions, accept any Android invitation and
   exchange messages. Repeat private NFC admission and remembered private rejoin.
5. Reject/ignore a system invitation and interrupt a setup attempt. After timeout,
   retry/cancel must remain available; no permanent Connecting state.
6. Capture OfflineConnection/OfflineDiscovery logs and P2P state around any failure.
   Do not include group passwords, admission secrets or raw invitations in logs.

Wireless ADB normally relies on the infrastructure network used by the development
computer. Losing that debugging connection is not itself proof that offline chat
failed. Full physical offline acceptance remains pending until checked over USB.

## Validation of the implementation

Flutter analysis, all 59 application tests and all 10 Android unit tests passed;
the debug APK built successfully and was installed on MI 9, OPPO and Huawei.
These checks do not replace the physical offline matrix above.

USB check on Huawei ANE-LX1: Wi-Fi enabled, infrastructure Wi-Fi DISCONNECTED,
both SIM slots ABSENT. Creating a public group succeeded: Android reported
GroupCreatedState with groupFormed=true/isGroupOwner=true and the app exposed
Open chat. Infrastructure Wi-Fi remained disconnected after creation. This
verifies standalone hosting on this older Android device; Android 10+ standalone
hosting and MI 9/OPPO joining are still pending physical acceptance.

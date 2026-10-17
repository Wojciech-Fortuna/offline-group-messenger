# Offline Group Messenger

The project aims to create an **offline group messaging app** that enables communication between multiple phones without Internet access or cellular coverage. Its main use case could be communication among a group of people on a plane, on a train, or in another location without network coverage.

**NFC** would be used to let users join a group quickly and securely. The person creating the group would tap their phone against another person's phone to transfer the group identifier and the information needed to establish a connection. This would eliminate the need to enter codes manually or search for the correct group.

After pairing, communication would take place over **Wi-Fi Direct**, which allows phones to create a local network without a router or an Internet connection. One phone would act as the **Group Owner**, serving as the group's local host. The other phones would connect to it and send messages, which would then be forwarded to all participants in the conversation.

The basic version of the app would support text messages, a participant list, and notifications when someone joins or leaves the group. Messages could also be **encrypted** to keep communication private despite the use of a shared wireless connection.

The main limitation would be the **range of Wi-Fi Direct**: all devices would need to remain within range of the phone acting as the Group Owner. Communication between all devices therefore could not be guaranteed on a large plane or over longer distances. A more advanced extension could introduce a **relay/multi-hop** mechanism, in which phones forward messages to devices beyond the sender's direct range. This would allow the app to form a simple decentralized communication network consisting entirely of users' phones.

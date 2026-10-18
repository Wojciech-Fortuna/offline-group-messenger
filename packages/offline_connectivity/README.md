# Offline Connectivity

Private Flutter plugin used by the app in this repository. Kotlin implements
Wi-Fi Direct permissions, create/discover/join/disconnect, state events, and
foreground NFC invitation sharing (HCE) / reading (ISO-DEP). NFC is optional;
devices without it can still use QR or nearby discovery.
Swift supplies an unsupported stub for future iOS connectivity. Messaging is
implemented separately in the app's shared Dart TCP layer.

See ../../docs/connectivity-contract.md for the shared channel contract.

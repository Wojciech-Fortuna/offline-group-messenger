import 'package:flutter/material.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

import '../features/home/home_screen.dart';
import 'theme.dart';

class MessengerApp extends StatelessWidget {
  const MessengerApp({
    super.key,
    this.connectivity = const OfflineConnectivity(),
  });

  final OfflineConnectivity connectivity;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Offline Group Messenger',
      debugShowCheckedModeBanner: false,
      theme: messengerTheme(Brightness.light),
      darkTheme: messengerTheme(Brightness.dark),
      home: HomeScreen(connectivity: connectivity),
    );
  }
}

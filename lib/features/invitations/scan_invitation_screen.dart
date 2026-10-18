import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

class ScanInvitationScreen extends StatefulWidget {
  const ScanInvitationScreen({super.key});
  @override
  State<ScanInvitationScreen> createState() => _ScanInvitationScreenState();
}

class _ScanInvitationScreenState extends State<ScanInvitationScreen> {
  bool _handled = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_handled || !mounted) return;
    for (final barcode in capture.barcodes) {
      if (barcode.format != BarcodeFormat.qrCode || barcode.rawValue == null) {
        continue;
      }
      try {
        final invitation = GroupInvitation.parse(barcode.rawValue!);
        _handled = true;
        Navigator.of(context).pop(invitation);
        return;
      } on FormatException {
        setState(() {
          _error =
              'Not a supported group invitation. Scan the QR shown by the host app.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan group invitation')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              // The widget owns its controller and handles pause/resume/disposal.
              onDetect: _onDetect,
              onDetectError: (error, stack) {
                if (mounted) {
                  setState(() {
                    _error =
                        'Could not read the code. Adjust the camera and try again.';
                  });
                }
              },
              errorBuilder: (context, error) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Camera unavailable. Allow camera access in app settings, then reopen the scanner.',
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ??
                  'Point the camera at the group QR code on the host phone.',
            ),
          ),
        ],
      ),
    ),
  );
}

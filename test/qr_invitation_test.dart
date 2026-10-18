import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/app/app.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'connection_flow_test.dart' show FakeConnection;

final invitation = GroupInvitation.fromMap({
  'app': 'offline-group-messenger',
  'version': 1,
  'transport': 'wifi-direct',
  'networkName': 'DIRECT-ab-Test',
  'passphrase': 'test-password-123',
});

class QrConnection extends FakeConnection {
  int qrJoins = 0;
  Completer<GroupInvitation>? delayed;
  @override
  Future<ConnectionCapabilities> getCapabilities() async =>
      const ConnectionCapabilities(
        platform: 'android',
        wifiDirectSupported: true,
        implementationReady: true,
        canJoinQr: true,
        description: 'Android ready',
      );
  @override
  Future<GroupInvitation> getInvitation() async =>
      delayed == null ? invitation : delayed!.future;
  @override
  Future<void> joinInvitation(GroupInvitation value) async {
    expect(value.toMap(), invitation.toMap());
    qrJoins++;
  }
}

class FakeCamera extends MobileScannerPlatform {
  bool denied = false;
  int disposals = 0;
  @override
  Stream<BarcodeCapture?> get barcodesStream => const Stream.empty();
  @override
  Stream<TorchState> get torchStateStream => const Stream.empty();
  @override
  Stream<double> get zoomScaleStateStream => const Stream.empty();
  @override
  Widget buildCameraView() => const SizedBox.expand();
  @override
  Future<MobileScannerViewAttributes> start(StartOptions options) async {
    if (denied) {
      throw const MobileScannerException(
        errorCode: MobileScannerErrorCode.permissionDenied,
      );
    }
    return const MobileScannerViewAttributes(
      cameraDirection: CameraFacing.back,
      currentTorchMode: TorchState.off,
      size: Size(640, 480),
    );
  }

  @override
  Future<void> updateScanWindow(Rect? window) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> pause() async {}
  @override
  Future<void> dispose() async {
    disposals++;
  }
}

void main() {
  const host = GroupConnectionState(
    status: GroupStatus.connected,
    isHost: true,
    hostAddress: '192.168.88.7',
    wifiEnabled: true,
    permissionGranted: true,
  );

  testWidgets('host QR contains invitation and disappears when group ends', (
    tester,
  ) async {
    final connection = QrConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    connection.updates.add(host);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show group QR code'));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text(invitation.passphrase), findsNothing);
    connection.updates.add(const GroupConnectionState());
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('late invitation cannot resurrect QR after disconnect', (
    tester,
  ) async {
    final connection = QrConnection()..delayed = Completer<GroupInvitation>();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    connection.updates.add(host);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Show group QR code'));
    await tester.pump();
    connection.updates.add(const GroupConnectionState());
    await tester.pump();
    connection.delayed!.complete(invitation);
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets(
    'scanner rejects unrelated QR and joins once after confirmation',
    (tester) async {
      final previous = MobileScannerPlatform.instance;
      final camera = FakeCamera();
      MobileScannerPlatform.instance = camera;
      addTearDown(() {
        MobileScannerPlatform.instance = previous;
      });
      final connection = QrConnection();
      addTearDown(connection.updates.close);
      await tester.pumpWidget(MessengerApp(connectivity: connection));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Scan group QR code'));
      await tester.tap(find.text('Scan group QR code'));
      await tester.pumpAndSettle();
      final detect = tester
          .widget<MobileScanner>(find.byType(MobileScanner))
          .onDetect!;
      detect(
        BarcodeCapture(
          barcodes: [
            const Barcode(
              format: BarcodeFormat.qrCode,
              rawValue: 'https://example.com',
            ),
          ],
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('Not a supported group invitation'),
        findsOneWidget,
      );
      final capture = BarcodeCapture(
        barcodes: [
          Barcode(format: BarcodeFormat.qrCode, rawValue: invitation.encode()),
        ],
      );
      detect(capture);
      detect(capture);
      await tester.pumpAndSettle();
      expect(find.text('Join this group?'), findsOneWidget);
      expect(connection.qrJoins, 0);
      await tester.tap(find.text('Join'));
      await tester.pumpAndSettle();
      expect(connection.qrJoins, 1);
      expect(find.byType(MobileScanner), findsNothing);
    },
  );

  testWidgets('camera denial offers recovery without joining', (tester) async {
    final previous = MobileScannerPlatform.instance;
    MobileScannerPlatform.instance = FakeCamera()..denied = true;
    addTearDown(() {
      MobileScannerPlatform.instance = previous;
    });
    final connection = QrConnection();
    addTearDown(connection.updates.close);
    await tester.pumpWidget(MessengerApp(connectivity: connection));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Scan group QR code'));
    await tester.tap(find.text('Scan group QR code'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Camera unavailable.'), findsOneWidget);
    expect(connection.qrJoins, 0);
    await tester.pageBack();
    await tester.pumpAndSettle();
  });
}

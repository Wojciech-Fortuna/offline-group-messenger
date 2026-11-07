import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_transport_lab/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('probe requires selection and backgrounding stops radio', (
    tester,
  ) async {
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(labChannel, (
      call,
    ) async {
      calls.add(call);
      if (call.method == 'bleState') {
        return {
          'state': 'Scanning',
          'peers': ['Probe 1'],
          'successes': 0,
        };
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        labChannel,
        null,
      ),
    );
    await tester.pumpWidget(const MaterialApp(home: TransportLab()));
    await tester.pumpAndSettle();
    expect(calls.where((c) => c.method == 'bleProbe'), isEmpty);
    await tester.tap(find.text('Test echo'));
    await tester.pumpAndSettle();
    expect(calls.singleWhere((c) => c.method == 'bleProbe').arguments, {
      'id': 'Probe 1',
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(calls.any((c) => c.method == 'bleStop'), isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox());
  });
}

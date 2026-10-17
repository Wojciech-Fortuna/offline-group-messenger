import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:offline_connectivity/offline_connectivity.dart';
import 'package:offline_group_messenger/app/app.dart';

void main() {
  const channel = MethodChannel(OfflineConnectivity.channelName);

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets(
    'shared UI reports iOS status without enabling unfinished actions',
    (tester) async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            channel,
            (_) async => {
              'platform': 'ios',
              'wifiDirectSupported': false,
              'implementationReady': false,
              'description': 'iOS adapter pending.',
            },
          );
      await tester.pumpWidget(const MessengerApp());
      await tester.pumpAndSettle();

      expect(find.text('iOS adapter pending.'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byType(FilledButton),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      await tester.scrollUntilVisible(
        find.byType(OutlinedButton),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
      );
    },
  );

  testWidgets('failed support check can be retried', (tester) async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
          calls++;
          if (calls == 1) throw PlatformException(code: 'unavailable');
          return {
            'platform': 'android',
            'wifiDirectSupported': true,
            'implementationReady': false,
            'description': 'Android adapter pending.',
          };
        });
    await tester.pumpWidget(const MessengerApp());
    await tester.pumpAndSettle();
    expect(find.text('Could not check device support.'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Android adapter pending.'), findsOneWidget);
  });
}

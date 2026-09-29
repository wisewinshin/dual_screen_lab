import 'package:dual_screen_lab/main.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dual_screen_lab/window_area');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'available');
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  testWidgets('starts as a clock and switches to mood light', (tester) async {
    await tester.pumpWidget(const MoodClockApp());
    await tester.pump();

    expect(find.text('내부 화면 · 시계'), findsOneWidget);
    expect(find.text('무드등 모드'), findsOneWidget);
    expect(find.text('듀얼 스크린 시작'), findsOneWidget);

    await tester.tap(find.text('무드등 모드'));
    await tester.pump();

    expect(find.text('내부 화면 · 무드 라이트'), findsOneWidget);
    expect(find.text('시계 모드'), findsOneWidget);
  });
}

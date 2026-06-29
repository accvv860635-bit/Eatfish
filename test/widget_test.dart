import 'package:big_fish_survival/main.dart';
import 'package:big_fish_survival/models/fish_spec.dart';
import 'package:big_fish_survival/screens/game_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('home screen renders start button', (tester) async {
    await tester.pumpWidget(const BigFishApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('大魚吃小魚'), findsOneWidget);
    expect(find.text('開始遊戲'), findsOneWidget);
    expect(find.text('排行榜'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('fish specs support 18 strictly growing levels', () {
    expect(FishSpecs.maxLevel, 18);
    expect(FishSpecs.all, hasLength(18));

    for (var i = 1; i < FishSpecs.all.length; i++) {
      expect(FishSpecs.all[i].length, greaterThan(FishSpecs.all[i - 1].length));
      expect(
        FishSpecs.all[i].length * .94,
        greaterThan(FishSpecs.all[i - 1].length * 1.04),
      );
    }

    expect(FishSpecs.byLevel(16).name, '巨口鯊');
    expect(FishSpecs.byLevel(17).name, '鄧氏魚');
    expect(FishSpecs.byLevel(18).name, '滄龍');
    expect(FishSpecs.byLevel(18).boss, isTrue);
  });

  testWidgets('game screen builds without crashing', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: GameScreen(fishCount: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Widget builds without exception
    expect(tester.takeException(), isNull);
  });

  testWidgets('game screen tap sets target', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: GameScreen(fishCount: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    // Start a pan gesture (simulates touch-and-drag)
    final gesture = await tester.startGesture(const Offset(200, 400));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.moveBy(const Offset(30, -20));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('pause menu toggles control mode without crashing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: GameScreen(fishCount: 40)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pump();

    expect(find.text('暫停'), findsOneWidget);
    expect(find.text('操控模式'), findsOneWidget);
    expect(find.text('按鈕模式'), findsOneWidget);
    expect(find.text('繼續遊戲'), findsOneWidget);
    expect(find.text('回首頁'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(Switch));
    await tester.pump();

    expect(find.text('搖桿模式'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('繼續遊戲'));
    await tester.pump();

    expect(find.text('暫停'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('restart returns game over state to a playable game', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(fishCount: 40, debugStartAtGameOver: true),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();

    expect(find.text('Game Over'), findsOneWidget);
    expect(find.text('再來一局'), findsOneWidget);

    await tester.tap(find.text('再來一局'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Game Over'), findsNothing);
    expect(find.textContaining('Lv.'), findsOneWidget);
    expect(find.textContaining('Score'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

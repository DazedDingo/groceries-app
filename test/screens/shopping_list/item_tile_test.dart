import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/models/item.dart';
import 'package:groceries_app/screens/shopping_list/cart_action.dart';
import 'package:groceries_app/screens/shopping_list/widgets/item_tile.dart';

ShoppingItem _sampleItem() => ShoppingItem(
      id: 'i1',
      name: 'milk',
      quantity: 1,
      unit: null,
      note: null,
      categoryId: 'dairy',
      preferredStores: const [],
      pantryItemId: null,
      recipeSource: null,
      isRecurring: false,
      addedBy: const AddedBy(
        uid: 'u1',
        displayName: 'Alice',
        source: ItemSource.app,
      ),
      addedAt: DateTime(2026, 4, 17, 10),
    );

Widget _host({
  required ShoppingItem item,
  required Future<CartReceipt> Function() onCheckOff,
  Future<CartReceipt> Function()? onDelete,
}) =>
    MaterialApp(
      home: Scaffold(
        body: ItemTile(
          item: item,
          onCheckOff: onCheckOff,
          onDelete: onDelete ?? () async => CartReceipt(originalItem: item),
          onUndo: (_) async {},
          onTap: () {},
          onLongPress: () {},
        ),
      ),
    );

void _captureHaptics(List<String> into) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') {
      into.add(call.arguments as String);
    }
    return null;
  });
}

void _restoreHaptics() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null);
}

void main() {
  group('ItemTile check-off animation', () {
    testWidgets('tile is wrapped in AnimatedScale + AnimatedOpacity', (tester) async {
      await tester.pumpWidget(_host(
        item: _sampleItem(),
        onCheckOff: () async => CartReceipt(originalItem: _sampleItem()),
      ));

      expect(find.byType(AnimatedScale), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsOneWidget);
    });

    testWidgets('scale and opacity start at 1.0 when idle', (tester) async {
      await tester.pumpWidget(_host(
        item: _sampleItem(),
        onCheckOff: () async => CartReceipt(originalItem: _sampleItem()),
      ));
      expect(
        tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
        1.0,
      );
      expect(
        tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
        1.0,
      );
    });

    testWidgets('AnimatedScale uses the 180ms polish duration', (tester) async {
      await tester.pumpWidget(_host(
        item: _sampleItem(),
        onCheckOff: () async => CartReceipt(originalItem: _sampleItem()),
      ));
      final scale = tester.widget<AnimatedScale>(find.byType(AnimatedScale));
      expect(scale.duration, const Duration(milliseconds: 180));
      final opacity =
          tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
      expect(opacity.duration, const Duration(milliseconds: 180));
    });

    testWidgets('secondary selectionClick haptic fires on successful check-off',
        (tester) async {
      final haptics = <String>[];
      _captureHaptics(haptics);
      addTearDown(_restoreHaptics);

      await tester.pumpWidget(_host(
        item: _sampleItem(),
        onCheckOff: () async => CartReceipt(originalItem: _sampleItem()),
      ));

      await tester.fling(find.byType(ItemTile), const Offset(500, 0), 1500);
      await tester.pumpAndSettle();

      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(haptics, contains('HapticFeedbackType.selectionClick'));
    });

    testWidgets('selectionClick does NOT fire on delete swipe', (tester) async {
      final haptics = <String>[];
      _captureHaptics(haptics);
      addTearDown(_restoreHaptics);

      await tester.pumpWidget(_host(
        item: _sampleItem(),
        onCheckOff: () async => CartReceipt(originalItem: _sampleItem()),
      ));

      // Right-to-left fling = delete direction.
      await tester.fling(find.byType(ItemTile), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();

      expect(haptics, contains('HapticFeedbackType.mediumImpact'));
      expect(haptics, isNot(contains('HapticFeedbackType.selectionClick')));
    });
  });
}

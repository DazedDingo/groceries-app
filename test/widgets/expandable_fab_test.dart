import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/widgets/expandable_fab.dart';

Widget _host({required List<FabAction> actions}) => MaterialApp(
      home: Scaffold(
        body: const SizedBox.expand(child: ColoredBox(color: Colors.white)),
        floatingActionButton: ExpandableFab(actions: actions),
      ),
    );

void main() {
  group('ExpandableFab', () {
    testWidgets('tapping a fan action invokes its callback', (tester) async {
      var manualTapped = 0;
      var voiceTapped = 0;
      await tester.pumpWidget(_host(actions: [
        FabAction(
          heroTag: 'a',
          icon: Icons.edit,
          label: 'Type an item',
          onPressed: () => manualTapped++,
        ),
        FabAction(
          heroTag: 'b',
          icon: Icons.mic,
          label: 'Quick voice',
          onPressed: () => voiceTapped++,
        ),
      ]));

      // Open the fan.
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      // Tap the first child (icon FAB).
      await tester.tap(find.byTooltip('Type an item'));
      await tester.pumpAndSettle();

      expect(manualTapped, 1);
      expect(voiceTapped, 0);
    });

    testWidgets('tapping the label text also fires the action', (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(actions: [
        FabAction(
          heroTag: 'a',
          icon: Icons.edit,
          label: 'Type an item',
          onPressed: () => tapped++,
        ),
      ]));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Type an item'));
      await tester.pumpAndSettle();

      expect(tapped, 1);
    });

    testWidgets('tapping the scrim closes the fan without firing actions',
        (tester) async {
      var tapped = 0;
      await tester.pumpWidget(_host(actions: [
        FabAction(
          heroTag: 'a',
          icon: Icons.edit,
          label: 'Type an item',
          onPressed: () => tapped++,
        ),
      ]));

      await tester.tap(find.byType(FloatingActionButton));
      await tester.pumpAndSettle();
      // Children visible.
      expect(find.text('Type an item'), findsOneWidget);

      // Tap top-left corner of the screen — should hit the scrim.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(tapped, 0);
      expect(find.text('Type an item'), findsNothing);
    });
  });
}

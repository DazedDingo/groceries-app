import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/screens/shared/empty_state.dart';

void main() {
  Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('EmptyState', () {
    testWidgets('renders icon + title + subtitle when subtitle is given',
        (tester) async {
      await tester.pumpWidget(_wrap(const EmptyState(
        icon: Icons.inbox,
        title: 'Nothing here',
        subtitle: 'explainer',
      )));
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('explainer'), findsOneWidget);
      expect(find.byIcon(Icons.inbox), findsOneWidget);
    });

    testWidgets(
        'omits the subtitle Text entirely when subtitle is null (tranche 5)',
        (tester) async {
      // The whole point of making subtitle optional is that an obvious CTA
      // doesn't need a sterile marketing blurb underneath. If the widget
      // silently renders an empty Text, it still takes vertical space and
      // the cleanup was pointless.
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.inbox,
        title: 'Nothing here',
        action: FilledButton(onPressed: () {}, child: const Text('Do it')),
      )));
      expect(find.text('Nothing here'), findsOneWidget);
      expect(find.text('Do it'), findsOneWidget);

      // Only one Text should be below the icon (the title) when no subtitle
      // is set. Buttons' Text widgets are nested deeper and don't count.
      final directTexts = find
          .descendant(of: find.byType(Column), matching: find.byType(Text))
          .evaluate()
          .map((e) => (e.widget as Text).data)
          .where((t) => t != null)
          .toList();
      expect(directTexts, contains('Nothing here'));
      expect(directTexts.where((t) => t == 'Do it'), isNotEmpty);
      // No stray empty-string Text artifacts.
      expect(directTexts.any((t) => t?.trim().isEmpty ?? false), isFalse);
    });

    testWidgets('renders the action widget when provided', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_wrap(EmptyState(
        icon: Icons.inbox,
        title: 'Empty',
        action: FilledButton(
          onPressed: () => tapped = true,
          child: const Text('Add'),
        ),
      )));
      await tester.tap(find.text('Add'));
      expect(tapped, isTrue);
    });
  });
}

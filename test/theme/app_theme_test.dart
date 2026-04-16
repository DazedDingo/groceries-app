import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Let the notifier's async _load() settle. SharedPreferences.getInstance()
/// hops through multiple microtasks + a platform-channel response, so we
/// drain the event queue a few times rather than a fixed delay.
Future<void> _waitForLoad(ProviderContainer container) async {
  // Force the provider to instantiate so _load() actually starts.
  container.read(themeVariantProvider);
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThemeVariantNotifier', () {
    test('defaults to classic when no pref is stored', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForLoad(container);
      expect(container.read(themeVariantProvider), ThemeVariant.classic);
    });

    test('loads refined from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'themeVariant': 'refined'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForLoad(container);
      expect(container.read(themeVariantProvider), ThemeVariant.refined);
    });

    test('loads classic from SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'themeVariant': 'classic'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForLoad(container);
      expect(container.read(themeVariantProvider), ThemeVariant.classic);
    });

    test('ignores unknown values and stays classic', () async {
      SharedPreferences.setMockInitialValues({'themeVariant': 'neon'});
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await _waitForLoad(container);
      expect(container.read(themeVariantProvider), ThemeVariant.classic);
    });

    test('set(refined) updates state and persists', () async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForLoad(container);

      await container.read(themeVariantProvider.notifier).set(ThemeVariant.refined);
      expect(container.read(themeVariantProvider), ThemeVariant.refined);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeVariant'), 'refined');
    });

    test('set(classic) persists classic marker', () async {
      SharedPreferences.setMockInitialValues({'themeVariant': 'refined'});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await _waitForLoad(container);

      await container.read(themeVariantProvider.notifier).set(ThemeVariant.classic);
      expect(container.read(themeVariantProvider), ThemeVariant.classic);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('themeVariant'), 'classic');
    });
  });

  group('theme data', () {
    test('classic and refined themes use Material 3', () {
      expect(appTheme.useMaterial3, isTrue);
      expect(appDarkTheme.useMaterial3, isTrue);
      expect(appRefinedTheme.useMaterial3, isTrue);
      expect(appRefinedDarkTheme.useMaterial3, isTrue);
    });

    test('classic and refined have distinct primary colors', () {
      expect(
        appTheme.colorScheme.primary,
        isNot(equals(appRefinedTheme.colorScheme.primary)),
      );
    });

    test('brightness is preserved per variant', () {
      expect(appTheme.brightness, Brightness.light);
      expect(appDarkTheme.brightness, Brightness.dark);
      expect(appRefinedTheme.brightness, Brightness.light);
      expect(appRefinedDarkTheme.brightness, Brightness.dark);
    });

    test('refined theme customises key component themes', () {
      // These are the refinements a user would actually notice. If any of
      // these regress to defaults, the "refined" variant is indistinguishable
      // from classic and the toggle is pointless.
      expect(appRefinedTheme.cardTheme.shape, isA<RoundedRectangleBorder>());
      expect(appRefinedTheme.appBarTheme.elevation, 0);
      expect(appRefinedTheme.snackBarTheme.behavior, SnackBarBehavior.floating);
      expect(appRefinedTheme.inputDecorationTheme.filled, isTrue);
    });
  });

  group('render smoke', () {
    // A real user sees the variant through Cards, Buttons, NavigationBar,
    // TextFields, SnackBars, ListTiles. If the refined theme throws during
    // layout/paint on any of these, users would hit a red screen. Render a
    // screen that exercises them all and verify it builds + paints clean.
    Widget kitchenSink() {
      return Scaffold(
        appBar: AppBar(title: const Text('Sink')),
        body: ListView(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.kitchen),
                title: const Text('Pantry'),
                subtitle: const Text('tap'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {},
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: TextField(
                decoration: InputDecoration(
                  labelText: 'Item',
                  hintText: 'Milk',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  FilledButton(onPressed: () {}, child: const Text('Save')),
                  const SizedBox(width: 8),
                  OutlinedButton(onPressed: () {}, child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  TextButton(onPressed: () {}, child: const Text('More')),
                ],
              ),
            ),
            Chip(label: const Text('Dairy'), onDeleted: () {}),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: 0,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.list), label: 'List'),
            NavigationDestination(icon: Icon(Icons.kitchen), label: 'Pantry'),
          ],
          onDestinationSelected: (_) {},
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {},
          child: const Icon(Icons.add),
        ),
      );
    }

    for (final variant in <(String, ThemeData)>[
      ('classic light', appTheme),
      ('classic dark', appDarkTheme),
      ('refined light', appRefinedTheme),
      ('refined dark', appRefinedDarkTheme),
    ]) {
      testWidgets('${variant.$1} paints the kitchen sink without error',
          (tester) async {
        await tester.pumpWidget(MaterialApp(
          theme: variant.$2,
          home: kitchenSink(),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Sink'), findsOneWidget);
        expect(find.text('Save'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      });
    }
  });

  group('MaterialApp integration', () {
    testWidgets('uses classic theme when variant is classic', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (ctx, ref, _) {
              final refined = ref.watch(themeVariantProvider) == ThemeVariant.refined;
              return MaterialApp(
                theme: refined ? appRefinedTheme : appTheme,
                home: const Scaffold(body: Text('hi')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('hi'));
      expect(Theme.of(ctx).colorScheme.primary, appTheme.colorScheme.primary);
    });

    testWidgets('switches to refined theme when provider flips', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          child: Consumer(
            builder: (ctx, ref, _) {
              capturedRef = ref;
              final refined = ref.watch(themeVariantProvider) == ThemeVariant.refined;
              return MaterialApp(
                theme: refined ? appRefinedTheme : appTheme,
                home: const Scaffold(body: Text('hi')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await capturedRef
          .read(themeVariantProvider.notifier)
          .set(ThemeVariant.refined);
      await tester.pumpAndSettle();

      final ctx = tester.element(find.text('hi'));
      expect(Theme.of(ctx).colorScheme.primary,
          appRefinedTheme.colorScheme.primary);
    });
  });
}

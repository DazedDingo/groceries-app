import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:groceries_app/providers/recipe_search_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('spoonacularKeyProvider loads empty string when nothing stored',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Initial state while load is pending
    expect(container.read(spoonacularKeyProvider), '');
    // Let _load complete
    await Future.delayed(Duration.zero);
    expect(container.read(spoonacularKeyProvider), '');
  });

  test('spoonacularKeyProvider hydrates from SharedPreferences', () async {
    SharedPreferences.setMockInitialValues(
        {'spoonacularApiKey': 'SAVED-KEY'});
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Force construction (triggers _load)
    container.read(spoonacularKeyProvider);
    // Pump a microtask so _load can complete
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(container.read(spoonacularKeyProvider), 'SAVED-KEY');
  });

  test('set persists to SharedPreferences and trims whitespace', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(spoonacularKeyProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await container
        .read(spoonacularKeyProvider.notifier)
        .set('  my-new-key  ');

    expect(container.read(spoonacularKeyProvider), 'my-new-key');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('spoonacularApiKey'), 'my-new-key');
  });

  test('set with empty string clears SharedPreferences entry', () async {
    SharedPreferences.setMockInitialValues(
        {'spoonacularApiKey': 'OLD-KEY'});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(spoonacularKeyProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));

    await container.read(spoonacularKeyProvider.notifier).set('');

    expect(container.read(spoonacularKeyProvider), '');
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.containsKey('spoonacularApiKey'), false);
  });
}

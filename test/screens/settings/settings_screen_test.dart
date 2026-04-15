import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:groceries_app/providers/auth_provider.dart';
import 'package:groceries_app/providers/household_key_notifier.dart';
import 'package:groceries_app/providers/household_provider.dart';
import 'package:groceries_app/screens/settings/settings_screen.dart';
import 'package:groceries_app/services/auth_service.dart';
import 'package:groceries_app/services/household_config_service.dart';
import 'package:groceries_app/services/household_service.dart';
import 'package:groceries_app/services/notification_service.dart';
import 'package:mockito/mockito.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeNotificationService extends Mock implements NotificationService {}

/// MockUser's getter for photoURL falls back to an imgur URL when the stored
/// value is null, which would trigger a NetworkImage fetch and crash the
/// widget test. Subclass and force it to null.
// ignore: must_be_immutable
class _MockUserNoPhoto extends MockUser {
  _MockUserNoPhoto({
    required super.uid,
    required super.email,
    required super.displayName,
  });
  @override
  String? get photoURL => null;
}

/// Stub platform channels that settings_screen touches at build time so
/// tests don't need a real Firebase / package_info plugin set up.
void _stubPlatformChannels() {
  final messenger = TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/package_info'),
    (call) async {
      if (call.method == 'getAll') {
        return <String, dynamic>{
          'appName': 'Groceries',
          'packageName': 'app.groceries',
          'version': '0.1.30',
          'buildNumber': '30',
          'buildSignature': '',
          'installerStore': '',
        };
      }
      return null;
    },
  );
  // firebase_core + messaging aren't used by the key tile but the Settings
  // screen's notification section resolves them lazily on tap. Stub with
  // noop handlers so nothing blows up during the build.
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_core'),
    (call) async => <String, dynamic>{'name': '[DEFAULT]', 'options': {}},
  );
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/firebase_messaging'),
    (call) async => null,
  );
}

Widget _wrap({required FakeFirebaseFirestore db, String householdId = 'hh1'}) {
  final mockUser = _MockUserNoPhoto(
    uid: 'u1',
    email: 'a@b.com',
    displayName: 'Alice',
  );
  final auth = MockFirebaseAuth(mockUser: mockUser, signedIn: true);
  db.doc('users/${mockUser.uid}').set({'householdId': householdId});
  db.doc('households/$householdId').set({'name': 'Test Household'});

  final router = GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('login'))),
      GoRoute(
        path: '/settings/categories',
        builder: (_, __) => const Scaffold(body: Text('cats')),
      ),
      GoRoute(
        path: '/settings/locations',
        builder: (_, __) => const Scaffold(body: Text('locs')),
      ),
      GoRoute(
        path: '/settings/report-issue',
        builder: (_, __) => const Scaffold(body: Text('report')),
      ),
    ],
  );

  return ProviderScope(
    overrides: [
      householdIdProvider.overrideWith((ref) async => householdId),
      householdNameProvider.overrideWith((ref) async => 'Test Household'),
      householdServiceProvider.overrideWithValue(HouseholdService(db: db)),
      authStateProvider.overrideWith((ref) => Stream.value(mockUser)),
      authServiceProvider.overrideWithValue(AuthService(auth: auth)),
      householdConfigServiceProvider
          .overrideWithValue(HouseholdConfigService(db: db)),
      notificationServiceProvider
          .overrideWithValue(_FakeNotificationService()),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _stubPlatformChannels();
  });

  // Use a taller viewport so the expanded edit panel's Save/Cancel buttons
  // don't land off-screen and miss hit-testing.
  setUpAll(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(800, 1600);
    view.devicePixelRatio = 1.0;
  });

  Future<void> expandBulkVoiceTile(WidgetTester tester) async {
    // Scroll until the Bulk voice add tile is in view.
    await tester.scrollUntilVisible(
      find.text('Bulk voice add'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Bulk voice add'));
    await tester.pumpAndSettle();
  }

  testWidgets('Gemini tile shows "Tap to add" when no key is stored',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(db: db));
    await tester.pumpAndSettle();
    await expandBulkVoiceTile(tester);

    expect(find.text('Google Gemini'), findsOneWidget);
    expect(find.text('Tap to add your free API key'), findsOneWidget);
    // No delete button when no key set.
    expect(find.byTooltip('Remove key'), findsNothing);
  });

  testWidgets('Gemini tile shows "Key saved" + delete button when filled',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .doc('households/hh1/config/apiKeys')
        .set({'geminiKey': 'AIza-EXISTING'});
    await tester.pumpWidget(_wrap(db: db));
    await tester.pumpAndSettle();
    await expandBulkVoiceTile(tester);

    expect(find.text('Key saved'), findsOneWidget);
    expect(find.byTooltip('Remove key'), findsOneWidget);
  });

  testWidgets('entering a key and tapping Save persists to Firestore',
      (tester) async {
    final db = FakeFirebaseFirestore();
    await tester.pumpWidget(_wrap(db: db));
    await tester.pumpAndSettle();
    await expandBulkVoiceTile(tester);

    await tester.tap(find.text('Google Gemini'));
    await tester.pumpAndSettle();

    // Edit mode now shown.
    expect(find.text('Gemini API key'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Save'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'AIza-NEW-TYPED-KEY');
    // Scroll Save into view if needed (edit panel is tall).
    await tester.scrollUntilVisible(
      find.widgetWithText(FilledButton, 'Save'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    // Wait for the Firestore write to land.
    String? actual;
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pump();
      final doc = await db.doc('households/hh1/config/apiKeys').get();
      actual = doc.data()?['geminiKey'] as String?;
      if (actual == 'AIza-NEW-TYPED-KEY') break;
    }
    expect(actual, 'AIza-NEW-TYPED-KEY');
  });

  testWidgets('Cancel in edit mode leaves the key unchanged', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .doc('households/hh1/config/apiKeys')
        .set({'geminiKey': 'AIza-KEEP'});
    await tester.pumpWidget(_wrap(db: db));
    await tester.pumpAndSettle();
    await expandBulkVoiceTile(tester);

    await tester.tap(find.text('Google Gemini'));
    await tester.pumpAndSettle();

    // Scroll the Cancel button into view (expanded edit panel may be tall).
    await tester.scrollUntilVisible(
      find.widgetWithText(OutlinedButton, 'Cancel'),
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byType(TextField), 'GARBAGE');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel'));
    await tester.pumpAndSettle();

    final doc = await db.doc('households/hh1/config/apiKeys').get();
    expect(doc.data()?['geminiKey'], 'AIza-KEEP');
  });

  testWidgets('delete button clears the key', (tester) async {
    final db = FakeFirebaseFirestore();
    await db
        .doc('households/hh1/config/apiKeys')
        .set({'geminiKey': 'AIza-WIPE'});
    await tester.pumpWidget(_wrap(db: db));
    await tester.pumpAndSettle();
    await expandBulkVoiceTile(tester);

    await tester.tap(find.byTooltip('Remove key'));
    await tester.pumpAndSettle();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    final doc = await db.doc('households/hh1/config/apiKeys').get();
    expect(doc.data()?['geminiKey'], '');
    expect(find.text('Tap to add your free API key'), findsOneWidget);
  });

}

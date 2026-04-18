import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Static checks against `android/app/src/main/AndroidManifest.xml`.
///
/// These are NOT integration tests — no emulator, no plugin code runs. They
/// catch the platform-config misses that no Dart unit test could otherwise
/// reach: a missing `RECORD_AUDIO` perm silently disables voice add, a
/// missing deep-link intent-filter silently breaks household invites, etc.
///
/// Inspired by a sister project (gps-pinger, v0.1.2) where two missing
/// `local_auth` perms shipped to the first APK because nothing in CI knew
/// to check the manifest. Cheap, no flake, runs in `flutter test`.
const _manifestPath = 'android/app/src/main/AndroidManifest.xml';

String _manifest() => File(_manifestPath).readAsStringSync();

bool _hasPermission(String name) =>
    _manifest().contains('android:name="android.permission.$name"');

void main() {
  group('AndroidManifest — runtime perms', () {
    test('declares RECORD_AUDIO (voice add — the headline feature)', () {
      // speech_to_text fails silently with a permission error overlay if
      // RECORD_AUDIO is missing. Voice add is the main differentiator —
      // do NOT let this perm get accidentally stripped.
      expect(_hasPermission('RECORD_AUDIO'), isTrue,
          reason: 'speech_to_text needs RECORD_AUDIO; without it voice add '
              'silently no-ops with a permission error.');
    });

    test('declares CAMERA (barcode scanner)', () {
      // mobile_scanner can't initialize without it; the scan screen shows
      // a black box.
      expect(_hasPermission('CAMERA'), isTrue);
    });

    test('declares POST_NOTIFICATIONS (FCM restock nudges, Android 13+)', () {
      // Without this, Android 13+ never delivers the FCM-driven restock
      // nudges that justify the firebase_messaging dep.
      expect(_hasPermission('POST_NOTIFICATIONS'), isTrue);
    });
  });

  group('AndroidManifest — household-invite deep link', () {
    test('declares the `groceries://join` intent filter', () {
      // app_links resolves this on cold + warm starts to add the user to a
      // shared household. If the intent-filter goes missing, invite links
      // open a browser-style "no app handles this" dialog.
      final m = _manifest();
      expect(m.contains('android:scheme="groceries"'), isTrue,
          reason: 'household invite links use the `groceries` scheme.');
      expect(m.contains('android:host="join"'), isTrue,
          reason: 'invite path is `groceries://join/<token>` — host must '
              'be `join` or app_links never matches.');
      expect(m.contains('android.intent.action.VIEW'), isTrue);
      expect(m.contains('android.intent.category.BROWSABLE'), isTrue,
          reason: 'BROWSABLE is required for the link to be reachable from '
              'a browser/email tap.');
    });
  });

  group('AndroidManifest — voice-add home-screen widget', () {
    test('declares GroceryWidgetProvider receiver + APPWIDGET_UPDATE filter',
        () {
      // The "voice add" widget is a top-level user feature; if the provider
      // disappears from the manifest the widget vanishes from the picker
      // with no user-visible error.
      final m = _manifest();
      expect(m.contains('.GroceryWidgetProvider'), isTrue);
      expect(m.contains('android.appwidget.action.APPWIDGET_UPDATE'), isTrue);
    });

    test('declares VoiceAddActivity (transparent host for the widget tap)',
        () {
      // Tapping the widget launches this transparent activity which kicks
      // speech_to_text and inserts the result. Removing it makes the
      // widget tap a no-op.
      expect(_manifest().contains('.VoiceAddActivity'), isTrue);
    });

    test('declares the GroceryListWidgetProvider + RemoteViews service', () {
      final m = _manifest();
      expect(m.contains('.GroceryListWidgetProvider'), isTrue);
      expect(m.contains('.GroceryListWidgetService'), isTrue);
      expect(m.contains('android.permission.BIND_REMOTEVIEWS'), isTrue,
          reason: 'BIND_REMOTEVIEWS must guard the RemoteViewsService — '
              'without it the list widget refuses to render.');
    });
  });

  group('AndroidManifest — FCM wiring', () {
    test('declares the default notification channel meta-data', () {
      // Without the default-channel meta, Android falls back to a "Misc"
      // channel for FCM notifications (silently). The channel ID
      // `restock_nudges` is the user-visible label in Settings → Apps →
      // Groceries → Notifications.
      final m = _manifest();
      expect(
        m.contains(
            'com.google.firebase.messaging.default_notification_channel_id'),
        isTrue,
        reason: 'FCM default channel meta-data is what makes the user-facing '
            'channel name correct.',
      );
      expect(m.contains('android:value="restock_nudges"'), isTrue,
          reason: 'channel id `restock_nudges` is what the user sees in '
              'system notification settings.');
    });
  });

  group('AndroidManifest — launcher activity sanity', () {
    test('exactly one MAIN/LAUNCHER activity (the launcher entry-point)', () {
      // A drift bug could add a second LAUNCHER activity (eg. when copy-
      // pasting a widget host activity stanza), which makes Android show
      // two icons in the launcher.
      final m = _manifest();
      final mainCount =
          'android.intent.action.MAIN'.allMatches(m).length;
      final launcherCount =
          'android.intent.category.LAUNCHER'.allMatches(m).length;
      expect(mainCount, 1, reason: 'exactly one MAIN intent allowed.');
      expect(launcherCount, 1,
          reason: 'two LAUNCHER intents = two icons in the launcher.');
    });
  });
}

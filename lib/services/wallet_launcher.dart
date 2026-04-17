import 'package:android_intent_plus/android_intent.dart';
import 'package:url_launcher/url_launcher.dart';

/// Launches the Google Wallet Android app; falls back to the Play Store
/// listing when Wallet isn't installed. Shared between the shopping-list chip,
/// settings tile, and trip-completion sheet so each entry point behaves
/// identically.
Future<void> openGoogleWallet() async {
  const intent = AndroidIntent(
    action: 'android.intent.action.MAIN',
    category: 'android.intent.category.LAUNCHER',
    package: 'com.google.android.apps.walletnfcrel',
    flags: <int>[0x10000000],
  );
  try {
    await intent.launch();
    return;
  } catch (_) {
    // fall through to Play Store
  }
  final playStore =
      Uri.parse('market://details?id=com.google.android.apps.walletnfcrel');
  try {
    await launchUrl(playStore, mode: LaunchMode.externalApplication);
  } catch (_) {
    // Swallowed — caller's responsibility to notify user if desired.
  }
}

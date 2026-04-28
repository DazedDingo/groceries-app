import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'main.dart' show pendingInviteToken;
import 'theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/household_provider.dart';
import 'providers/items_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/household/setup_screen.dart';
import 'screens/shopping_list/shopping_list_screen.dart';
import 'screens/pantry/pantry_screen.dart';
import 'screens/pantry/pantry_item_detail_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/manage_categories_screen.dart';
import 'screens/settings/manage_locations_screen.dart';
import 'screens/settings/report_issue_screen.dart';
import 'screens/shopping_list/history_screen.dart';
import 'screens/shopping_list/templates_screen.dart';
import 'screens/shopping_list/bulk_voice_screen.dart';
import 'screens/pantry/bulk_voice_screen.dart';
import 'screens/recipes/recipes_screen.dart';
import 'screens/recipes/recipe_detail_screen.dart';
import 'screens/recipes/add_recipe_screen.dart';
import 'screens/recipes/discover_recipes_screen.dart';
import 'screens/meal_plan/meal_plan_screen.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(
      path: '/setup',
      builder: (_, state) => SetupScreen(
        inviteToken: state.uri.queryParameters['token'],
      ),
    ),
    // StatefulShellRoute keeps each tab's Navigator alive across bottom-nav
    // switches, so screen-local flags (e.g. _restockChecked, _expiryChecked,
    // _promotedThisSession, _sawNonEmptyList) and scroll positions don't
    // reset when the user moves to another tab and back.
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) =>
          ScaffoldWithNavBar(navigationShell: navigationShell),
      branches: [
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/list',
            builder: (_, __) => const ShoppingListScreen(),
            routes: [
              GoRoute(path: 'history', builder: (_, __) => const HistoryScreen()),
              GoRoute(path: 'templates', builder: (_, __) => const TemplatesScreen()),
              GoRoute(path: 'bulk-voice', builder: (_, __) => const BulkVoiceScreen()),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/pantry',
            builder: (_, __) => const PantryScreen(),
            routes: [
              GoRoute(path: 'bulk-voice', builder: (_, __) => const PantryBulkVoiceScreen()),
              GoRoute(
                path: ':itemId',
                builder: (_, state) =>
                    PantryItemDetailScreen(itemId: state.pathParameters['itemId']!),
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/recipes',
            builder: (_, __) => const RecipesScreen(),
            routes: [
              GoRoute(
                path: 'new',
                builder: (_, state) => AddRecipeScreen(
                  autoImport: state.uri.queryParameters['import'] == 'true',
                ),
              ),
              GoRoute(
                path: 'discover',
                builder: (_, __) => const DiscoverRecipesScreen(),
              ),
              GoRoute(
                path: ':recipeId',
                builder: (_, state) => RecipeDetailScreen(
                  recipeId: state.pathParameters['recipeId']!,
                ),
                routes: [
                  GoRoute(
                    path: 'edit',
                    builder: (_, state) => AddRecipeScreen(
                      recipeId: state.pathParameters['recipeId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(path: '/plan', builder: (_, __) => const MealPlanScreen()),
        ]),
        StatefulShellBranch(routes: [
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
            routes: [
              GoRoute(path: 'categories', builder: (_, __) => const ManageCategoriesScreen()),
              GoRoute(path: 'locations', builder: (_, __) => const ManageLocationsScreen()),
              GoRoute(path: 'report-issue', builder: (_, __) => const ReportIssueScreen()),
            ],
          ),
        ]),
      ],
    ),
  ],
);

class GroceriesApp extends ConsumerStatefulWidget {
  const GroceriesApp({super.key});

  @override
  ConsumerState<GroceriesApp> createState() => _GroceriesAppState();
}

class _GroceriesAppState extends ConsumerState<GroceriesApp> {
  late final AppLinks _appLinks;
  StreamSubscription<Uri>? _linkSub;

  static final _tokenPattern = RegExp(r'^[a-zA-Z0-9]{20,64}$');

  @override
  void initState() {
    super.initState();
    _appLinks = AppLinks();
    // Listen for deep links while app is running (warm start)
    _linkSub = _appLinks.uriLinkStream.listen(
      (uri) {
        if (uri.host == 'join') {
          final token = uri.queryParameters['token'];
          if (token != null && _tokenPattern.hasMatch(token)) {
            _router.go('/setup?token=$token');
          }
        }
      },
      onError: (_) {}, // Silently ignore malformed links
    );

    // Handle cold-start deep link
    if (pendingInviteToken != null && _tokenPattern.hasMatch(pendingInviteToken!)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _router.go('/setup?token=$pendingInviteToken');
        pendingInviteToken = null;
      });
    }
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final variant = ref.watch(themeVariantProvider);
    final refined = variant == ThemeVariant.refined;
    return MaterialApp.router(
      title: 'Groceries',
      theme: refined ? appRefinedTheme : appTheme,
      darkTheme: refined ? appRefinedDarkTheme : appDarkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

class ScaffoldWithNavBar extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;
  const ScaffoldWithNavBar({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Register the device's FCM token under the user's member doc as soon as
    // both the auth state and household id are known. Runs once per change of
    // either, which is fine — writing the same token back is a no-op.
    ref.listen(householdIdProvider, (_, next) {
      final householdId = next.value;
      final uid = ref.read(authStateProvider).value?.uid;
      if (householdId != null && householdId.isNotEmpty && uid != null) {
        // Fire-and-forget; failures are acceptable (permission denied, etc.)
        // and we'll retry on the next app launch.
        ref.read(notificationServiceProvider)
            .registerToken(householdId, uid)
            .catchError((_) {});
      }
    });

    final selectedIndex = navigationShell.currentIndex;
    final itemCount = ref.watch(itemsProvider).value?.length ?? 0;

    return Scaffold(
      body: _TabBackground(index: selectedIndex, child: navigationShell),
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: [
          NavigationDestination(
            icon: Badge(
              isLabelVisible: itemCount > 0,
              label: Text('$itemCount'),
              child: const Icon(Icons.shopping_cart),
            ),
            label: 'List',
          ),
          const NavigationDestination(icon: Icon(Icons.kitchen), label: 'Pantry'),
          const NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Recipes'),
          const NavigationDestination(icon: Icon(Icons.calendar_month), label: 'Plan'),
          const NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
        // initialLocation: true means tapping the active tab pops back to its
        // root — matches the iOS-style expectation when retapping a tab.
        onDestinationSelected: (i) => navigationShell.goBranch(
          i,
          initialLocation: i == selectedIndex,
        ),
      ),
    );
  }
}

/// Subtle, theme-aware gradient tint that distinguishes each tab without
/// fighting content. Picks a role color from the active ColorScheme and
/// blends it into the surface so the list / pantry / recipes / plan / settings
/// tabs feel visually distinct even on screens that share widgets.
class _TabBackground extends StatelessWidget {
  final int index;
  final Widget child;
  const _TabBackground({required this.index, required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tint = switch (index) {
      0 => cs.primary,     // List
      1 => cs.tertiary,    // Pantry
      2 => cs.secondary,   // Recipes
      3 => cs.primary,     // Plan
      _ => cs.outline,     // Settings
    };
    final alpha = Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(tint.withValues(alpha: alpha), cs.surface),
            cs.surface,
          ],
        ),
      ),
      child: child,
    );
  }
}

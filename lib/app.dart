import 'dart:async';
import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'main.dart' show pendingInviteToken;
import 'theme/app_theme.dart';
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
    ShellRoute(
      builder: (context, state, child) => ScaffoldWithNavBar(child: child),
      routes: [
        GoRoute(
          path: '/list',
          builder: (_, __) => const ShoppingListScreen(),
          routes: [
            GoRoute(path: 'history', builder: (_, __) => const HistoryScreen()),
            GoRoute(path: 'templates', builder: (_, __) => const TemplatesScreen()),
          ],
        ),
        GoRoute(path: '/pantry', builder: (_, __) => const PantryScreen()),
        GoRoute(
          path: '/pantry/:itemId',
          builder: (_, state) => PantryItemDetailScreen(itemId: state.pathParameters['itemId']!),
        ),
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
        GoRoute(path: '/plan', builder: (_, __) => const MealPlanScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/settings/categories', builder: (_, __) => const ManageCategoriesScreen()),
        GoRoute(path: '/settings/locations', builder: (_, __) => const ManageLocationsScreen()),
        GoRoute(path: '/settings/report-issue', builder: (_, __) => const ReportIssueScreen()),
      ],
    ),
  ],
);

class GroceriesApp extends StatefulWidget {
  const GroceriesApp({super.key});

  @override
  State<GroceriesApp> createState() => _GroceriesAppState();
}

class _GroceriesAppState extends State<GroceriesApp> {
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
    return MaterialApp.router(
      title: 'Groceries',
      theme: appTheme,
      darkTheme: appDarkTheme,
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

class ScaffoldWithNavBar extends ConsumerWidget {
  final Widget child;
  const ScaffoldWithNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = GoRouterState.of(context).uri.toString();
    int selectedIndex = 0;
    if (location.startsWith('/pantry')) selectedIndex = 1;
    if (location.startsWith('/recipes')) selectedIndex = 2;
    if (location.startsWith('/plan')) selectedIndex = 3;
    if (location.startsWith('/settings')) selectedIndex = 4;

    final itemCount = ref.watch(itemsProvider).value?.length ?? 0;

    return Scaffold(
      body: child,
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
        onDestinationSelected: (i) {
          const routes = ['/list', '/pantry', '/recipes', '/plan', '/settings'];
          context.go(routes[i]);
        },
      ),
    );
  }
}

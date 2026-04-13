import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'theme/app_theme.dart';
import 'screens/auth/login_screen.dart';
import 'screens/household/setup_screen.dart';
import 'screens/shopping_list/shopping_list_screen.dart';
import 'screens/pantry/pantry_screen.dart';
import 'screens/pantry/pantry_item_detail_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/settings/manage_categories_screen.dart';
import 'screens/shopping_list/history_screen.dart';
import 'screens/recipes/recipes_screen.dart';
import 'screens/recipes/recipe_detail_screen.dart';
import 'screens/recipes/add_recipe_screen.dart';

final _router = GoRouter(
  initialLocation: '/login',
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
    GoRoute(path: '/setup', builder: (_, __) => const SetupScreen()),
    ShellRoute(
      builder: (context, state, child) => ScaffoldWithNavBar(child: child),
      routes: [
        GoRoute(
          path: '/list',
          builder: (_, __) => const ShoppingListScreen(),
          routes: [
            GoRoute(path: 'history', builder: (_, __) => const HistoryScreen()),
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
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(path: '/settings/categories', builder: (_, __) => const ManageCategoriesScreen()),
      ],
    ),
  ],
);

class GroceriesApp extends StatelessWidget {
  const GroceriesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Groceries',
      theme: appTheme,
      routerConfig: _router,
    );
  }
}

class ScaffoldWithNavBar extends StatelessWidget {
  final Widget child;
  const ScaffoldWithNavBar({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.toString();
    int selectedIndex = 0;
    if (location.startsWith('/pantry')) selectedIndex = 1;
    if (location.startsWith('/recipes')) selectedIndex = 2;
    if (location.startsWith('/settings')) selectedIndex = 3;

    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'List'),
          NavigationDestination(icon: Icon(Icons.kitchen), label: 'Pantry'),
          NavigationDestination(icon: Icon(Icons.restaurant_menu), label: 'Recipes'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
        onDestinationSelected: (i) {
          const routes = ['/list', '/pantry', '/recipes', '/settings'];
          context.go(routes[i]);
        },
      ),
    );
  }
}

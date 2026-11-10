import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../account/auth_controller.dart';
import '../features/account/name_screen.dart';
import '../features/account/sign_in_screen.dart';
import '../features/pantry/pantry_edit_screen.dart';
import '../features/pantry/pantry_form_screen.dart';
import '../features/pantry/pantry_screen.dart';
import '../features/planning/day_rules_screen.dart';
import '../features/planning/plan_preview_screen.dart';
import '../features/planning/plan_screen.dart';
import '../features/planning/plan_setup_screen.dart';
import '../features/planning/time_budget_screen.dart';
import '../features/recipes/from_name_screen.dart';
import '../features/recipes/from_photo_screen.dart';
import '../features/recipes/from_url_screen.dart';
import '../features/recipes/recipe_chat_screen.dart';
import '../features/recipes/recipe_form_screen.dart';
import '../features/recipes/recipes_screen.dart';
import '../features/settings/ai_keys_screen.dart';
import '../features/settings/animations_gallery_screen.dart';
import '../features/settings/appearance_screen.dart';
import '../features/settings/profile_screen.dart';
import '../features/shopping/shopping_screen.dart';
import '../features/use_first/use_first_screen.dart';
import 'home_shell.dart';

/// Kuda vodi stanje prijave: bez naloga samo "Prijava", bez imena samo
/// korak sa imenom (FR-001). Tražena adresa se pamti u `from`.
String? authRedirect(AuthState auth, Uri uri) {
  final path = uri.path;
  final from = uri.queryParameters['from'];
  String withFrom(String target) {
    final back = path.startsWith('/sign-in') ? from : uri.toString();
    return back == null || back == '/plan'
        ? target
        : Uri(path: target, queryParameters: {'from': back}).toString();
  }

  return switch (auth) {
    Starting() ||
    SignedOut() ||
    CodeSent() => path == '/sign-in' ? null : withFrom('/sign-in'),
    NeedsName() => path == '/sign-in/name' ? null : withFrom('/sign-in/name'),
    SignedIn() => path.startsWith('/sign-in') ? (from ?? '/plan') : null,
  };
}

/// Pravi novi router (testovi prave svoj, da stanje ne prelazi iz testa u
/// test). [auth] daje trenutno stanje prijave, [refresh] javlja promene.
GoRouter createRouter({
  String initialLocation = '/plan',
  AuthState Function()? auth,
  Listenable? refresh,
}) => GoRouter(
  initialLocation: initialLocation,
  refreshListenable: refresh,
  redirect: auth == null
      ? null
      : (context, state) => authRedirect(auth(), state.uri),
  routes: [
    GoRoute(
      path: '/sign-in',
      builder: (context, state) => const SignInScreen(),
      routes: [
        GoRoute(path: 'name', builder: (context, state) => const NameScreen()),
      ],
    ),
    GoRoute(
      path: '/use-first',
      builder: (context, state) => const UseFirstScreen(),
    ),
    // Profil i podešavanja su iznad tabova; otvaraju se preko avatara.
    GoRoute(
      path: '/profile',
      builder: (context, state) => const ProfileScreen(),
      routes: [
        GoRoute(
          path: 'ai-keys',
          builder: (context, state) => const AiKeysScreen(),
        ),
        GoRoute(
          path: 'appearance',
          builder: (context, state) => const AppearanceScreen(),
        ),
        GoRoute(
          path: 'animations',
          builder: (context, state) => const AnimationsGalleryScreen(),
        ),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => HomeShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/plan',
              builder: (context, state) => const PlanScreen(),
              routes: [
                GoRoute(
                  path: ':planId/entries/:entryId',
                  builder: (context, state) => MealEntryScreen(
                    planId: state.pathParameters['planId']!,
                    entryId: state.pathParameters['entryId']!,
                  ),
                ),
                GoRoute(
                  path: 'time',
                  builder: (context, state) => const TimeBudgetScreen(),
                ),
                GoRoute(
                  path: 'rules',
                  builder: (context, state) => const DayRulesScreen(),
                ),
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const PlanSetupScreen(),
                  routes: [
                    GoRoute(
                      path: 'preview',
                      builder: (context, state) => const PlanPreviewScreen(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/shopping',
              builder: (context, state) => const ShoppingScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/recipes',
              builder: (context, state) => const RecipesScreen(),
              routes: [
                GoRoute(
                  path: 'new/url',
                  builder: (context, state) => const FromUrlScreen(),
                ),
                GoRoute(
                  path: 'new/name',
                  builder: (context, state) => const FromNameScreen(),
                ),
                GoRoute(
                  path: 'new/photo',
                  builder: (context, state) => const FromPhotoScreen(),
                ),
                GoRoute(
                  path: 'new/manual',
                  builder: (context, state) => const RecipeFormScreen(),
                ),
                GoRoute(
                  path: ':id',
                  pageBuilder: (context, state) {
                    final child = RecipeRoute(id: state.pathParameters['id']!);
                    // Na širokom ekranu se samo menja izbor u listi.
                    return MediaQuery.sizeOf(context).width >= 1100
                        ? NoTransitionPage(key: state.pageKey, child: child)
                        : MaterialPage(key: state.pageKey, child: child);
                  },
                  routes: [
                    GoRoute(
                      path: 'edit',
                      builder: (context, state) =>
                          RecipeFormScreen(id: state.pathParameters['id']),
                    ),
                    GoRoute(
                      path: 'chat',
                      builder: (context, state) =>
                          RecipeChatScreen(id: state.pathParameters['id']!),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/pantry',
              builder: (context, state) => const PantryScreen(),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const PantryFormScreen(),
                ),
                GoRoute(
                  path: ':id/edit',
                  builder: (context, state) =>
                      PantryEditScreen(id: state.pathParameters['id']!),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

class TabSpec {
  const TabSpec(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const tabs = [
  TabSpec('/plan', 'Plan', Icons.calendar_month_outlined, Icons.calendar_month),
  TabSpec(
    '/shopping',
    'Nabavka',
    Icons.shopping_basket_outlined,
    Icons.shopping_basket,
  ),
  TabSpec('/recipes', 'Recepti', Icons.menu_book_outlined, Icons.menu_book),
  TabSpec('/pantry', 'Ostava', Icons.kitchen_outlined, Icons.kitchen),
];

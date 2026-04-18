# Groceries App — Developer Onboarding

## Project Overview

Shared household grocery app: shopping lists, pantry tracking, recipes, meal planning. Real-time sync via Firestore; Google Sign-In auth; voice input; Google Home/Tasks integrations.

**Tech Stack:**
- **Frontend:** Flutter ^3.11.4 (Dart)
- **State management:** Riverpod (flutter_riverpod ^2.5.1)
- **Routing:** go_router ^14.2.7
- **Backend:** Firebase (Auth, Firestore, Cloud Messaging, Cloud Functions)
- **Cloud Functions:** TypeScript (Node 22, firebase-functions ^7.2.5)
- **Theme:** Material 3 with classic & refined (sage) variants

---

## Directory Structure

### lib/

- **models/** — Data models: `ShoppingItem`, `PantryItem`, `Recipe`, `Category`, `HistoryEntry`, `HouseholdConfig`, `MealPlan`. Serialized via `toMap()`/`fromMap()` (no codegen); `ItemSource` & enums use extensions for string conversion.
- **providers/** — Riverpod providers: `*Provider` (e.g., `itemsProvider`, `pantryProvider`, `recipesProvider`), `*ServiceProvider` for injected services, `*NotifierProvider` for state. Pattern: watch Firestore streams; filter/compute via dependent providers.
- **screens/** — UI organized by feature: `auth/`, `household/`, `shopping_list/`, `pantry/`, `recipes/`, `meal_plan/`, `settings/`. Sub-screens in nested `GoRoute` definitions. Bulk actions (voice, multi-select) in dedicated screens.
- **services/** — Business logic & API calls: `*Service` classes (e.g., `ItemsService`, `HouseholdService`, `RecipeImportService`). Thin wrappers around Firestore & Cloud Functions. Utilities like `FuzzyMatch`, `TextItemParser`, `UnitConverter`, `CategoryGuesser`, `shelf_life_guesser.dart` (per-item-name + category fallback), `shelf_life_learner.dart` (median days-between-purchases from history), `running_low_promoter.dart` (pure function: finds pantry items flagged ≥2 days ago not already on the list — called from `PantryScreen`'s post-frame callback to promote them lazily on open).
- **theme/** — `ThemeVariant` enum (classic/refined); `appTheme`/`appDarkTheme`; `_buildRefined()` for sage palette with tighter typography. Persists via `SharedPreferences`.
- **widgets/** — Reusable UI components; organized by screen (e.g., `shopping_list/widgets/item_tile.dart`).

### functions/src/

- **index.ts** — Function exports & triggers.
- **addToList.ts** — Google Home / IFTTT webhook (adds items via HTTP).
- **categoryGuesser.ts** — Maps items to categories (server-side; client-side mirror in `lib/services/category_guesser.dart`. Both length-sort keywords as of `dd46081`; keep them in sync when adding aliases).
- **nudgeRestock.ts** — Push notifications for pantry restocking.
- **syncGoogleTasks.ts** — Two-way sync with Google Tasks API.
- **firestoreWriter.ts** — Utility functions.
- **submitIssue.ts** / **issueQueue.ts** / **processIssueQueue.ts** — "Fix this" queue. The callable enqueues into `households/{hid}/issueBatches/{id}`; a scheduled drain (every 2 min) bundles each pending batch whose 10-min debounce has lapsed into a single GitHub issue. Submissions from the same user within the window append + reset the clock; clients can cancel while `status == 'pending'`.
- **types.ts** — Shared TypeScript types.

### test/

- **models/**, **providers/**, **screens/**, **services/**, **theme/** — Unit & widget tests. Uses `fake_cloud_firestore`, `firebase_auth_mocks`, `mockito`.

---

## Key Conventions

### Riverpod Providers

- **StreamProvider** for Firestore streams (e.g., `itemsProvider` watches `itemsService.itemsStream(householdId)`).
- **StateProvider** for transient UI state (e.g., `selectedCategoryFilterProvider`).
- **Provider** for computed / filtered values (e.g., `filteredItemsProvider` depends on `itemsProvider` & filter).
- **StateNotifierProvider** for persisted state (e.g., `themeVariantProvider`).
- Naming: `*Provider` for the provider, `*Service` for the implementation class.

### Models & Serialization

- No JSON codegen. Models implement `toMap()` and `factory Model.fromMap()` explicitly.
- Enums use extensions: `ItemSource` → `ItemSourceExt` with `value` getter & `fromString()` factory.
- Firestore timestamps stored as `DateTime`; serialize via `Timestamp.fromDate()`.

### Screens & Navigation

- Naming: `*_screen.dart` (e.g., `shopping_list_screen.dart`).
- `go_router` routes defined in `lib/app.dart`; nested routes via `GoRoute` with path params.
- Bulk actions in separate screens: `bulk_voice_screen.dart`, linked as sub-routes.
- Use `context.push()` / `context.go()` from `go_router`.

### Services

- Name: `*Service` (e.g., `ItemsService`, `CategoryGuesser`).
- Firestore reference via injected `FirebaseFirestore` (no singleton needed; tests inject mocks).
- Cloud Functions calls via `FirebaseFunctions.instanceFor(region: 'us-central1').httpsCallable()`.
- No caching in services; let Riverpod handle stream dedup.

### Firestore Structure

- **Collections under households/{householdId}:**
  - `members/{uid}` — household members.
  - `items/{itemId}` — shopping list.
  - `pantry/{itemId}` — pantry items.
  - `categories/{categoryId}` — custom categories.
  - `stores/{storeId}` — preferred store locations.
  - `recipes/{recipeId}` + `/ratings/{uid}` — recipe data & user ratings.
  - `templates/{templateId}` — saved shopping list templates.
  - `history/{entryId}` — purchase history (append-only).
  - `mealPlan/{entryId}` — meal plan entries.
  - `categoryOverrides/{overrideId}` — user's category corrections. Written whenever the category dropdown on pantry detail or shopping list edit dialog changes, so the guesser learns next time.
  - `config/{docId}` — household settings (units, theme, etc.).
  - `issueBatches/{batchId}` — "Fix this" queue docs. Per-submitter. `status`: pending|dispatched|cancelled. Client-writable only to set `status = cancelled`; the rest is admin-SDK-only.
- **Collections at root:**
  - `users/{uid}` — user profile (auth metadata).
  - `invites/{token}` — one-time household join links.

### Theme

- **Classic variant** (default): Material 3 green seed (`#4CAF50`).
- **Refined variant** (opt-in): sage green seed (`#2F7D4F`) with tighter tracking, higher font weights. Toggle in Settings → persists to `SharedPreferences`.
- Both use `ColorScheme.fromSeed(brightness: ...)` for light/dark.
- **Known limitation:** dark mode OLED tuning + accent tone mapping + AA contrast not yet implemented (Audit §1).

---

## Build & Deployment

**Local dev:**
```bash
flutter pub get
flutter run
```

**Cloud Functions:**
```bash
cd functions
npm install
npm run build
firebase deploy --only functions
```

**Scripts** (from `pubspec.yaml` & `functions/package.json`):
- `flutter pub get` — fetch Dart deps.
- `build_runner build` — codegen (currently unused; serialization is manual).
- `firebase deploy --only functions` — deploy TS functions.
- `firebase functions:log` — tail function logs.

---

## Commit Conventions

Pattern: `type(scope): message` where:
- **type:** `feat`, `fix`, `chore`, `test`, `docs`, `ci`
- **scope:** optional; feature area (e.g., `theme`, `pantry`, `auth`)
- **message:** imperative, lowercase. If related to issue, close with `(closes #N)`.

Examples from git log:
```
feat(theme): opt-in refined theme variant with settings toggle
feat(pantry): hands-free bulk voice add with per-item current/optimal split
fix: bulk voice parser to gemini-2.5-flash for free tier
docs: rewrite polish audit (v2) with verified claims
test: comprehensive tests for isHighPriority and priority sort logic
```

---

## Known Gotchas

1. **Category guesser parity** — Dart + TS both length-sort keywords (`dd46081`). Keep both in sync when editing `_keywords` / `KEYWORDS`; alias coverage (cilantro/coriander etc.) is still open work.

2. **Cook This is unit-aware** (`b178b9f`) — uses `hasEnough()` from `unit_converter.dart`. Weight (g/kg/oz/lb) and volume (ml/L/fl oz/gal/cups) normalise; cross-category (g vs ml) or unknown units fall back to raw compare. Three-bucket modal: `inStock` / `onList` / `missing`; only `missing` gets added.

3. **Refined theme incomplete** (Audit §5): Dark mode only uses `ColorScheme.fromSeed`. OLED surface tuning, accent tone mapping, and AA contrast verification for sage surfaces not yet done.

4. **No onboarding** (Audit §2): Setup dumps user straight onto an empty list. First activation is churn-prone.

5. **Bulk voice uses Gemini API**: Requires `GEMINI_API_KEY` per household (stored in Firestore `households/{id}/config/geminiKey`). Free tier (`gemini-2.5-flash`); monitor usage to avoid overages.

---

## Testing

- Unit tests: `flutter test test/`
- Widget tests: `flutter test test/screens/`
- Mocks: `fake_cloud_firestore`, `firebase_auth_mocks` for Firestore/Auth integration.
- Riverpod tests: use `ProviderContainer` with mocked services.

---

## Debugging

- **Firestore rules:** Check `firestore.rules` for permission errors.
- **Cloud Functions:** `firebase functions:log` to tail; check Firebase Console for error stacks.
- **Riverpod providers:** Use `ref.listen()` or Flutter DevTools Riverpod inspector to trace state.
- **Deep links:** App handles invite tokens via `app_links` package; tested in `test/flows/`.

---

## Performance Notes

- **Pagination:** Not implemented; lists assume small household (<1k items).
- **Indexing:** Firestore indexes defined in `firestore.indexes.json` (auto-created by SDK).
- **Cloud Functions:** async, trigger-based (Firestore writes, pub/sub, HTTPS endpoints).
- **Local caching:** No offline support; relies on Firestore's built-in client-side cache.

---

## Resources

- **README.md** — high-level feature list & setup.
- **docs/POLISH_AUDIT.md** — verified engineering roadmap (v2, current as of 2026-04-17).
- **lib/theme/app_theme.dart** — theme definitions.
- **firestore.rules** — security rules; member-gated access.
- **functions/** — TypeScript source; deploy via `firebase deploy --only functions`.

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
- **screens/** — UI organized by feature: `auth/`, `household/`, `shopping_list/`, `pantry/`, `recipes/`, `meal_plan/`, `settings/`. Sub-screens in nested `GoRoute` definitions. Bulk actions (voice, multi-select) in dedicated screens. The five bottom-nav tab screens use transparent Scaffolds (`backgroundColor: Colors.transparent` on both the Scaffold and its AppBar) so `_TabBackground` in `app.dart` can paint a tab-specific themed gradient behind them — new tab screens must follow this pattern or they'll hide the gradient.
- **services/** — Business logic & API calls: `*Service` classes (e.g., `ItemsService`, `HouseholdService`, `RecipeImportService`). Thin wrappers around Firestore & Cloud Functions. `pantry_barcode_matcher.dart` — pure `findPantryMatch(scannedName, pantry)` returning `{exact, fuzzy}` so the Pantry "Scan barcode" appbar action can route a scan to either auto-increment (exact), a "stock existing or add new?" prompt (fuzzy via `isFuzzyMatch`), or a prefilled add dialog (no match). Utilities like `FuzzyMatch`, `TextItemParser`, `UnitConverter`, `CategoryGuesser`, `shelf_life_guesser.dart` (per-item-name keyword table + category fallback; ~200 entries covering meats, dairy, produce, grains, canned goods, condiments, nuts/seeds, snacks, frozen — longest-key-wins), `shelf_life_learner.dart` (median days-between-purchases from history — needs ≥3 buys), `shelf_life_resolver.dart` (the ladder: `resolveShelfLifeDays({itemName, categoryName, history})` tries learned → keyword → category in order — single source of truth for the pantry detail screen and both check-off paths). `running_low_promoter.dart` — pure functions: `itemsDueForPromotion` finds pantry items flagged ≥2 days ago not already on the list; `promoteQuantities` returns the post-decrement pantry count and the list quantity so a check-off lands back at optimal — both called from `PantryScreen`'s post-frame callback to promote items lazily on open. `ItemsService.promoteFromPantry` commits the shopping-item write + history entry + pantry decrement/flag-clear in a single Firestore `WriteBatch` (atomic; marks the new shopping item with `fromRunningLow: true`). `ItemsService.undoPromoteFromPantry` is the paired reversal used by the SnackBar Undo on `PantryScreen`. `CategoryOverrideService.clearOverride` removes a stored mapping so the keyword guesser takes over again — pantry detail and shopping-list edit dialog both call this when the user picks "Uncategorised" (rather than persisting uncategorised as a sticky override). `ItemsService.checkOff` / `confirmBought` accept an optional `shelfLifeDaysFallback`; callers resolve via `resolveShelfLifeDays` when the pantry entry has none set, and the service persists the resolved value plus a freshly-set `expiresAt = now + days` so the countdown restarts on every buy. `expiry_checker.dart` (`findExpiringBelowOptimal` + `expiringFingerprint`) backs the launch banner on `ShoppingListScreen`: items that are both below optimal and expired/within-2-days show as a `MaterialBanner` with a per-user "Dismiss" that stores the fingerprint in `SharedPreferences` (`dismissedExpiryFingerprint:<uid>`), so the banner only re-surfaces when the set or its expiries change. `pantry_grouper.dart` — pure functions `groupByCategory(items, categories)` / `groupByLocation(items, customLocations)` / `statusRank(item)` back the Pantry tab's grouping toggle (status / category / location); both grouping modes float expired→expiring→below-optimal→stale→stocked within each section and fall back to "Uncategorised" / "Not set" for items lacking a category or location. `restock_reminder_service.dart` holds `RestockReminderConfig` (enabled/cadenceDays/preferredHour/timezoneOffsetMinutes/lastSentAt) + CRUD at `households/{id}/config/restockReminder`; the client never writes `lastSentAt` (owned by the scheduled function). `notification_service.dart#registerToken(householdId, uid)` requests FCM permission and writes the token onto `households/{hid}/members/{uid}.fcmToken` — wired from `ScaffoldWithNavBar` in `app.dart` via a `ref.listen(householdIdProvider, ...)` so the token lands once household + uid are both known.
- **theme/** — `ThemeVariant` enum (classic/refined); `appTheme`/`appDarkTheme`; `_buildRefined()` for sage palette with tighter typography. Persists via `SharedPreferences`.
- **widgets/** — Reusable UI components; organized by screen (e.g., `shopping_list/widgets/item_tile.dart`).

### functions/src/

- **index.ts** — Function exports & triggers.
- **addToList.ts** — Google Home / IFTTT webhook (adds items via HTTP).
- **categoryGuesser.ts** — Maps items to categories (server-side; client-side mirror in `lib/services/category_guesser.dart`. Both length-sort keywords as of `dd46081`; keep them in sync when adding aliases).
- **nudgeRestock.ts** — Push notifications for pantry restocking.
- **restockReminder.ts** — Hourly-scheduled "Grocery shopping today?" household reminder. `buildRestockMessage(itemNames, maxBodyLen=80)` assembles the FCM title/body and truncates with `", etc."` when the list overruns the soft budget (keeps item names whole). `sendRestockReminders(now)` iterates households, honours `config/restockReminder.enabled` + `preferredHour` (converted to local via `timezoneOffsetMinutes`) + cadence (with a 0.5h tolerance for cold-start jitter), collects below-optimal pantry items (alphabetical), multicasts to every member's `fcmToken`, and stamps `lastSentAt` via admin SDK. Uses Android notification channel `restock_nudges`.
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
- `ShoppingItem.fromRunningLow` (bool, defaults to false) flags items auto-promoted from a running-low pantry entry. Drives the `trending_down` badge on shopping-list tiles and is the hook for the "Undo auto-add" SnackBar action.
- `PantryItem.unitAmount` (double?) + `PantryItem.unit` (String?) describe one container (e.g. 500 g) and are intentionally separate from `currentQuantity`/`optimalQuantity`, which count whole containers. Pantry detail edits both in the Stock card; the tile renders the pair as `… · 500g`.

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
  - `config/{docId}` — household settings (units, theme, etc.). `config/restockReminder` holds the per-household "grocery shopping today?" preferences (enabled, cadenceDays, preferredHour, timezoneOffsetMinutes, lastSentAt).
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

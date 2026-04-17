---
updated: 2026-04-17
status: v2 — rewritten after verification pass against current `main`
---

# Groceries — Polish & Intelligence Audit

Each item: **State now → Move → Stack → Effort → Sequencing**.

- **Effort:** S (≤1 day), M (2–5 days), L (1–2 weeks). Frontend-only, schema-migration, and multi-service work are called out explicitly rather than hidden inside a letter.
- **Sequencing:** *one-shot* (ship and move on) vs *thread* (compounds; revisit as data accrues). Threads require a living metric.
- **Kill list** at the bottom. Nothing here is load-bearing if it only adds bloat.

---

## 0. Already shipped since v1 — cross-offs

Verified against `git log`. Do **not** re-propose these.

- **Refined theme variant** with opt-in settings toggle (`8236431`). Addresses v1 §3's first bullet.
- **Bulk voice add** for pantry with per-item current/optimal split + silence-triggered auto-advance (`d023268`, `8de7c12`, `dad93a5`).
- **Bulk multi-select + delete** on shopping, pantry, recipes (`31a3294`).
- **Custom pantry locations** (`0e458c9`) — items live somewhere, not just "pantry."
- **High-priority toggle** + priority-aware sort + nudge skip-delay (`d272066`, `ac876f8`).
- **Recurring items** — checked-off recurring re-adds on next trip (`b061216`, `b5c28af`).
- **Fuzzy name matching + priority suggestions** when adding (`3b43a3a`).
- **Help button on all main screens** (`0937a37`).
- **Per-household API keys in Firestore** (`b5c28af`, `075db4b`).
- **Meal plan screen + provider + service** (pre-existing; not in v1's scope at all).
- **Category guesser parity** (`dd46081`, 2026-04-17). Dart `category_guesser.dart` now length-sorts keywords to match `functions/src/categoryGuesser.ts`. "orange juice" → Drinks on-device and server-side.
- **Cook This: dedupe + unit-aware compare** (`b178b9f`, 2026-04-17). Three-bucket modal (inStock / onList / missing); only missing items are added. `hasEnough()` in `unit_converter.dart` normalises weight (g/kg/oz/lb) and volume (ml/L/fl oz/gal/cups) before comparing.
- **Tranche 1 polish** (v0.1.33, 2026-04-17): check-off animation (180ms scale+fade on swipe, secondary `selectionClick` haptic after success) in `item_tile.dart`; pull-to-refresh on shopping, pantry, recipes screens (invalidates provider + short haptic); trip-completion bottom sheet triggered on list ≥1 → 0 with per-person breakdown, duration, and first-of-day celebration icon. See `trip_completion_sheet.dart` + shopping_list_screen `_maybeShowTripCompletion`.

v1 rated ~8 of the last 30 commits as open work when they were already shipped. Treat v1 as a snapshot of intent, not current state.

---

## 1. Corrections to v1 claims

- **~~Category keyword table parity bug~~** — **fixed in `dd46081`**. See §0.
- **~~Cook This doesn't wire unit_converter~~** — **fixed in `b178b9f`**. See §0.
- **Category keyword table is still 28 entries, not 42.** Aliases (cilantro/coriander, aubergine/eggplant, capsicum/bell pepper, zucchini/courgette) remain open work under §3.
- **Authored dark mode is L, not M.** Both themes rely on `ColorScheme.fromSeed(brightness: dark)` (`lib/theme/app_theme.dart`). OLED surface tuning + accent tone mapping + AA contrast verification against sage surfaces is real work, not a weekend.
- **`syncGoogleTasks` 3-minute cadence** asserted in v1 is not visible in source. Cadence is defined by whatever scheduler invokes it; verify before quoting.

---

## 2. Revised Top 5 (evidence-weighted)

Reordered against the real bottleneck: **activation, then daily-utility compounding, then polish.**

1. **Onboarding → first check-off in under 60 seconds.** `setup_screen.dart` is a two-option form that dumps the user onto an empty list. Replace with: create-or-join card → partner invite with copy-link → 3 sample items preloaded and celebrated on first check. Without this, every other improvement is wasted on users who never activate. **M, one-shot.**
2. **Cadence-aware suggestions + consumption-rate restock — bundled.** Both read the same `HistoryEntry` stream. Compute per-item rolling cadence in a scheduled Cloud Function, write to `households/{id}/itemStats`. Surface as dismissable "due soon" chips atop the shopping list; use the same signal to override `restockAfterDays` in `nudgeRestock.ts`. This is the single hardest thing for competitors to copy and the "it knows us" moment. **M, thread.**
3. ~~**Cook This: dedupe against list + wire existing `unit_converter.dart`.**~~ **Shipped `b178b9f`** (2026-04-17). Three-bucket modal (inStock / onList / missing) + `hasEnough()` unit-aware compare. Validation metric (§12) still needs baselining.
4. ~~**Trip completion sheet.**~~ **Shipped v0.1.33.** See §0.
5. **Recipe imagery + `lastCookedAt`.** Adds two fields to `lib/models/recipe.dart` + image picker in add-recipe + grid in `recipes_screen.dart`. Unlocks Hero transitions and makes a future cook mode worth building. **M, thread** — schema migration is the only gotcha.

Presence / activity chips / reactions (v1's #2) is charming but **second-order**. Defer until activation is fixed — you can't socialise an empty household.

---

## 3. Intelligence the user doesn't have to ask for

- **Category guesser aliases + locale awareness.** Parity sort shipped (`dd46081`); still outstanding — cilantro/coriander, aubergine/eggplant, capsicum/bell pepper, zucchini/courgette aliases keyed off a `locale` setting. The inline "wrong? tap to fix" chip training `categoryOverridesProvider` (`lib/providers/categories_provider.dart`) is still valid — the override plumbing exists, the UI doesn't. **S, one-shot.**
- **Cadence detection** → see Top 5 #2.
- ~~**Cook This dedupe + unit conversion**~~ → **shipped `b178b9f`**.
- **Consumption-rate restock** → bundled into Top 5 #2.
- **Smarter suggestion ranking when adding an item.** Fuzzy matching is shipped (`3b43a3a`) but ranks by name similarity only. Rank by recency × frequency × priority. **S, one-shot.**

---

## 4. Moments of delight

- ~~**Trip completion sheet**~~ → **shipped v0.1.33**.
- ~~**Check-off animation.**~~ → **shipped v0.1.33**. 180ms `AnimatedScale` + `AnimatedOpacity` wrap in `item_tile.dart`, with secondary `selectionClick` haptic on successful check-off.
- **Per-screen empty-state illustrations.** `lib/screens/shared/empty_state.dart` is icon+title+subtitle. Extend with an `illustration` slot; commission 4 sage-palette vectors (pantry nap, empty list, no recipes, no meal plan). Playful copy. **S code, M art, one-shot.**
- **Onboarding** → Top 5 #1.
- **Motion language.** Pull-to-refresh shipped v0.1.33 on shopping/pantry/recipes. Chips still recolor without motion; no Hero between recipe card and detail. Spring on chip toggle, Hero on recipe image (requires §6 imagery first) still open. **S per piece, thread** — taste, not a ticket.

---

## 5. Visual polish

- **Refined theme is shipped.** Remaining gaps: define a 3-step elevation scale (rest / hover / pressed) with sage-tinted shadow; shrink 68px nav bar to 56px in the refined variant (`app_theme.dart` refined branch); tint system chrome to match. **S, one-shot.**
- **Authored dark mode.** See §1 — this is L, not M. Hand-author refined dark: `#0B0F0D` OLED base, desaturated sage surfaces, brighter accent tone mapping, AA contrast pass on chips/badges. **L, one-shot.**
- **Category palette.** `lib/services/household_service.dart:16` uses Material 500s; Dairy `#42A5F5` and Frozen `#29B6F6` are near-adjacent. Replace with a desaturated value-spaced palette tuned to sage; verify AA on chip text. **S, one-shot.**
- **Recipe cards** → Top 5 #5.

---

## 6. Recipes as something worth returning to

- **Imagery + `lastCookedAt`** → Top 5 #5.
- **Cook mode.** No step-by-step screen exists. Build `/recipes/:id/cook`: wakelock on, swipe-to-advance steps, crossed-off ingredient strip, timers parsed from step text. **Use an LLM call to extract structured steps + timers once on save** (cache to Firestore) rather than a regex parser — regex fails on real recipe prose, and per-household Gemini keys are already in place (`b5c28af`). **L, thread** — anchor of return-visit behaviour.

---

## 7. Household as a social experience

Defer until activation is fixed, then:

- **Presence + fade-in attribution chips.** `addedBy` exists on every item; surface transiently. New `households/{id}/presence` doc + foreground listener + `activity_chip.dart`. **M, thread.**
- **Reactions.** Long-press → heart/thanks emoji; FCM to adder; badge in history. **S, one-shot** — warmest cheap win once presence is live.
- **Activity feed tab.** Denormalise to `households/{id}/activity` from existing triggers; grouped event cards; weekly digest push. **L, thread.**

---

## 8. Integrations — magic vs bolted on

Pattern: all three integrate *to* the app, not *with* it. Fixable cheaply.

- **IFTTT / Google Home.** `functions/src/addToList.ts:73` + `settings_screen.dart:195` under collapsed Advanced. Zero in-app discovery, silent failures. Write `lastWebhookAt` on success; surface "last trigger 2m ago" in settings; coach-mark on voice FAB first-run. **S, one-shot.**
- **Google Tasks sync.** `functions/src/syncGoogleTasks.ts` is invisible; failures log-only. Write `householdSyncStatus` doc with last-sync + error state; settings row with enable/disable + re-auth flow. **M, thread** — trust compounds.
- **Google Wallet.** `settings_screen.dart:140` is just an intent launcher. Surface as a contextual chip atop the list when a trip starts; promote to the trip-complete sheet. **S, one-shot.**

---

## 9. Engineering health — not in v1, should have been

v1 was a UX audit. These are blockers that will bite before most v1 suggestions land.

- **Firestore indexes.** No audit of composite indexes against actual query shapes (shopping list sort, pantry bucket filter, history by date × user). Missing indexes surface as silent cold-start latency. Run with Firestore Emulator + indexed query warnings enabled; baseline p95 latency per screen. **M.**
- **Offline behaviour.** Firestore offline persistence defaults on, but no audit of conflict resolution on concurrent household edits — two users checking off the same item while offline is the obvious case. Spec + test. **M.**
- **List perf at scale.** No virtualisation check; a 500-item pantry or 2-year history will bite. Profile `ListView` vs `ListView.builder` usage; paginate history. **S to measure, M to fix.**
- **Crash + error telemetry.** No Crashlytics integration visible. Silent webhook failures (§8) are a symptom of this gap. **S.**
- **Test coverage strategy.** Strong spot coverage (bulk voice, category guesser, unit converter) but no coverage target, no integration harness for Firestore rules, no screenshot tests. **M.**
- **Firestore security rules.** Verify rules match the `recipe ratings` pattern (`86e28f0`) across every collection the household touches. One-pass review. **S.**

---

## 10. Accessibility & i18n — not in v1

- **Accessibility.** No semantics audit. `Dismissible` items need swipe-action announcements; colour-coded category chips fail for colour-blind users without icons (category icon map is a v1 §3 suggestion — pull it forward for a11y reasons); verify TalkBack/VoiceOver paths through onboarding and check-off. **M.**
- **i18n.** The alias gap (courgette/zucchini) is the tip — the whole app assumes en-GB/US. No ARB files, no locale switch, no pluralisation. If the keyword table is going to be locale-aware (§3), commit to the full i18n stack or don't start. **L, thread.**
- **Dynamic type + large text.** Untested. Verify all text scales to iOS XXL / Android 200%. **S to audit.**

---

## 11. Kill list

Polish is additive until it isn't. Candidates to **remove** to reduce friction:

- **Settings "Advanced" ExpansionTile** (`settings_screen.dart:195`). Nobody discovers it. Either promote IFTTT/Wallet/Tasks to first-class settings with live status (§8), or remove them from settings entirely and expose through feature-first entry points.
- **Empty-state subtitle text** on screens that already have a primary CTA. Redundant and sterile — drop the subtitle when the action is obvious.
- **History screen as a destination.** Once cadence chips (§2 / Top 5 #2) exist, the raw-log history screen is demoted to a rarely-used drill-down. Move it behind a tap on the cadence chip, not a primary nav slot.
- **Per-screen help buttons** (`0937a37`). Audit usage before keeping — if nobody taps them, they're visual noise. Instrument or cull.

Every one of these is a candidate, not a mandate. Verify with usage data before cutting.

---

## 12. Validation — how we'll know any of this worked

None of the above is falsifiable as written. Assign a metric before shipping each thread:

| Work | Metric | Success |
|---|---|---|
| Onboarding rewrite (Top 5 #1) | % of new households with ≥1 item checked off within 24h | ≥60% |
| Cadence suggestions (Top 5 #2) | % of shopping trips with ≥1 suggested item added | ≥30% |
| Cook This dedupe (Top 5 #3) | Dup items added per Cook This use | <0.1 |
| Trip completion sheet (Top 5 #4) | D1 retention on days a trip completes | +5pp vs control |
| Recipe imagery (Top 5 #5) | Recipe detail opens per week per household | +20% |
| Presence / activity | Sessions where another member's activity is surfaced | tracked, no target yet |

Without these baselined now (before shipping), "impact" claims on the next audit will be as unfalsifiable as v1's were.

---

## Summary

Two-week plan: **(a) fix activation + (b) wire the cheap Cook This + category parity fixes + (c) baseline the metrics above.** Next quarter: cadence thread + recipe imagery thread. Everything else is real but downstream of these.

Authored with `dazeddingo`.

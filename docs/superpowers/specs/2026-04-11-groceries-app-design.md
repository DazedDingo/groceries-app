# Groceries App — Design Spec
**Date:** 2026-04-11
**Stack:** Flutter (Android) + Firebase (Firestore, Cloud Functions, FCM, Auth)

---

## Overview

A household grocery management app that lets users add items by voice (via Google Home/IFTTT or in-app mic), tracks a running shopping list, maintains a pantry with optimal stock levels, sends configurable restock reminders, organises items by category and preferred store, and shows live UK supermarket price data to help users shop at the best time and place.

---

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   Flutter App (Android)                  │
│  ┌────────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐  │
│  │ Shopping   │ │  Pantry  │ │  Prices  │ │Settings  │  │
│  │   List     │ │ Tracker  │ │  Panel   │ │& Stores  │  │
│  └─────┬──────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘  │
│        └─────────────┴────────────┴─────────────┘        │
│                  Firestore SDK (realtime)                 │
└──────────────────────────┬───────────────────────────────┘
                           │
           Firebase (Firestore + Functions + FCM + Auth)
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
  Firestore DB      Cloud Functions      FCM (push)
  (lists, pantry,   ┌──────┴───────┐    (restock
   prices, stores,   IFTTT webhook  Scheduled   nudges)
   categories)       handler        jobs
        │                  │
        │            Trolley.co.uk API
        │            (UK supermarket prices)
        │
   IFTTT ← "Hey Google, add milk"
```

**Firebase Auth:** Google Sign-In. Each user belongs to one household. Households are joined via a shareable invite link.

---

## Data Model (Firestore)

### `households/{householdId}`
```
{
  name: string,
  createdBy: uid,
  createdAt: timestamp,
  inviteToken: string     // used to generate invite link
}
```

### `households/{id}/members/{uid}`
```
{
  displayName: string,
  email: string,
  joinedAt: timestamp,
  webhookToken: string    // unique per member for IFTTT attribution
}
```

### `households/{id}/stores/{storeId}`
```
{
  name: string,           // e.g. "Tesco"
  trolleySlug: string,    // e.g. "tesco" — null if custom/unsupported
  addedBy: uid,
  addedAt: timestamp
}
```
Pre-populated: Tesco, Asda, Sainsbury's, Morrisons, Waitrose, Aldi, Lidl, Ocado (all Trolley-supported). Users can add custom stores; these display no price data.

### `households/{id}/categories/{categoryId}`
```
{
  name: string,           // e.g. "Spices"
  color: string,          // hex color for UI chip
  addedBy: uid,
  addedAt: timestamp
}
```
Pre-populated defaults: Meats, Dairy, Produce, Spices, Frozen, Bakery, Drinks, Household, Uncategorised. All are editable and deletable. Deleting a category reassigns its items to "Uncategorised".

### `households/{id}/items/{itemId}` — active shopping list
```
{
  name: string,
  quantity: number,
  categoryId: string,
  preferredStores: [storeId],
  pantryItemId: string | null,  // set when auto-added from pantry; null for manual adds
  addedBy: {
    uid: string | null,
    displayName: string,
    source: "app" | "voice_in_app" | "google_home"
  },
  addedAt: timestamp
}
```

### `households/{id}/pantry/{itemId}` — pantry tracker
```
{
  name: string,
  categoryId: string,
  preferredStores: [storeId],
  optimalQuantity: number,
  currentQuantity: number,
  restockAfterDays: number | null,   // null = nudge disabled
  lastNudgedAt: timestamp | null,
  lastPurchasedAt: timestamp | null
}
```
When `currentQuantity < optimalQuantity`, the item is automatically added to the shopping list. Checking off an item during shopping resets `currentQuantity` to `optimalQuantity` and records `lastPurchasedAt`.

### `households/{id}/prices/{pantryItemId}/snapshots/{timestamp}`
```
{
  tesco: number | null,
  asda: number | null,
  sainsburys: number | null,
  morrisons: number | null,
  waitrose: number | null,
  aldi: number | null,
  lidl: number | null,
  ocado: number | null,
  fetchedAt: timestamp
}
```
Price snapshots are written twice daily by a scheduled Cloud Function. The app queries the last 30 days of snapshots to calculate trends and identify price lows.

---

## Screens

### 1. Shopping List (home)
- Live Firestore listener — updates in real time across all household devices
- Items grouped by category (collapsible sections)
- Filter bar: category chips + store chips (e.g. "Tesco run" shows only Tesco-preferred items)
- Each item shows: name, quantity, who added it, source icon (phone / mic / Google Home)
- Swipe right to check off — if `pantryItemId` is set, resets `currentQuantity` to `optimalQuantity` and records `lastPurchasedAt` on the pantry entry; if null (manual add), simply removes the item from the list
- Swipe left to delete
- Long-press to edit quantity, category, or preferred stores
- FAB: mic button → Android `SpeechRecognizer` → confirm item name → write to Firestore
- "Best deals" banner: highlights items currently at a 30-day price low

### 2. Pantry
- All tracked items with current vs. optimal quantity
- Tap +/- to adjust `currentQuantity`
- Items below optimal quantity shown with a warning indicator
- "Add to list" button per item (if not already on list)
- Tap item to edit: name, category, preferred stores, optimal quantity, restock reminder interval

### 3. Prices
- Scrollable list of all pantry items, each with a price panel
- Per-item: current price at each store, cheapest store highlighted, 30-day sparkline chart
- "Best time this month" label when current price matches the 30-day low
- Custom stores (no Trolley support) shown as "No price data"

### 4. Settings
- Household name + invite link (copy/share)
- Manage stores: add, rename, remove
- Manage categories: add, rename, recolor, remove
- Per-member IFTTT webhook token (copy to use in IFTTT applet)
- Notification preferences

---

## Google Home / IFTTT Integration

**Setup (one-time per member):**
1. User copies their unique webhook URL from Settings
2. Creates an IFTTT applet: Google Assistant trigger → Webhooks action
3. Trigger phrase: *"add $ to my list"* — IFTTT sends `{ "item": "{{TextField}}" }` to the webhook URL

**Cloud Function (`addItemWebhook`):**
- Receives POST request
- Authenticates via the `webhookToken` in the URL path (one per member)
- Looks up the household from the token
- Writes item to `households/{id}/items` with `source: "google_home"` and the matched member's `displayName`
- Returns 200 immediately (IFTTT doesn't need a response body)

**In-app voice:**
- Taps FAB mic → `SpeechRecognizer` streams audio → returns transcript
- Confirmation dialog shows recognised text before writing
- Writes to Firestore with `source: "voice_in_app"`

---

## Restock Notifications

**Scheduled Cloud Function (runs daily at 08:00 UTC):**
- Queries all pantry items across all households where `restockAfterDays` is not null
- For each item where `now - lastNudgedAt > restockAfterDays` (or never nudged):
  - Sends FCM push to all household members: *"Did you use any [item]? Tap to update your count."*
  - Updates `lastNudgedAt` to now
- Tapping the notification deep-links to that item in the Pantry screen

**Per-item nudge intervals:** Off, 3 days, 7 days, 14 days, 30 days (set in Pantry item detail).

---

## Theme

Dark mode only. Material Design 3 dark color scheme throughout. No light mode.

---

## Cost Estimate

All infrastructure runs on Firebase's free Spark tier for a family-sized household:

| Resource | Free Limit | Expected Usage |
|---|---|---|
| Firestore reads | 50K/day | ~500/day |
| Firestore writes | 20K/day | ~100/day |
| Cloud Functions | 2M/month | ~1K/month |
| FCM push | Free always | Free always |
| Firebase Auth | Free always | Free always |
| Trolley API | ~1K req/day free | ~200/day (2x daily × ~100 items) |

Estimated monthly cost: **$0**. Blaze pay-as-you-go would cost under $2/month if free limits were ever exceeded.

---

## Distribution

**Firebase App Distribution** (recommended). Free Firebase tool — upload a new APK build, household members receive an email/notification to install. Handles updates cleanly without manual APK transfers or a Play Store listing. No Google Play developer account required.

---

## Security

The app handles household data and push notifications — the attack surface is small but worth hardening explicitly.

**Authentication & authorisation**
- Firebase Auth with Google Sign-In only — no passwords stored anywhere in the app or backend
- All Firestore reads/writes go through Firebase Security Rules: a user can only read/write documents belonging to their own household. No document is publicly readable.
- Cloud Functions that write to Firestore on behalf of a user verify the caller's Firebase ID token before touching any data

**IFTTT webhook endpoint**
- Each member's webhook URL contains their unique `webhookToken` (a 256-bit random string generated at account creation)
- The Cloud Function rejects any request whose token doesn't match a known member — no token, no write
- Tokens are rotatable from Settings (invalidates the old IFTTT applet until reconfigured)
- Endpoint is rate-limited (max 60 requests/hour per token) to prevent list-flooding if a URL is ever leaked
- Item name is validated and sanitised server-side before writing to Firestore (max 100 chars, stripped of control characters)

**Data in transit & at rest**
- All Firebase communication is TLS-encrypted — Firestore SDK, FCM, and Cloud Function HTTPS endpoints
- No sensitive data (tokens, UIDs, household IDs) is stored in plaintext on-device; Firebase SDK manages secure credential storage via Android Keystore
- FCM device tokens are stored only in Firestore under the member's own document, readable only by household members

**App permissions**
- Microphone: requested only when the user taps the mic FAB, not at install time
- Notifications: requested on first launch with a clear explanation
- No location, contacts, camera, or storage permissions requested

**Dependency hygiene**
- Flutter and Firebase SDK dependencies pinned to specific versions in `pubspec.yaml`
- Cloud Functions dependencies pinned in `package-lock.json`
- Both reviewed and updated before each release build

---

## Out of Scope

- iOS support (Android only; Flutter makes future iOS extension straightforward)
- Barcode scanning (can be added later)
- Recipe integration (can be added later)
- Light mode

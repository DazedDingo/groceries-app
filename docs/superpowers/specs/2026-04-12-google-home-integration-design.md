# Google Home Integration Design

**Date:** 2026-04-12  
**Status:** Approved  
**Scope:** Add items to the household shopping list via Google Home voice commands

---

## Overview

A private Google Action (Actions Builder) lets household members say *"Hey Google, add milk to Groceries"* from any Google Home device. A Firebase HTTPS Function handles fulfillment: it verifies the caller's identity, finds their household, and writes the item to Firestore. The Flutter app requires no changes — it already models `ItemSource.googleHome` and the Firestore stream picks up new documents in real time.

---

## Decisions

| Decision | Choice | Reason |
|---|---|---|
| Supported commands | Add only (no read/remove) | 90% use case; read/remove can be added later |
| Quantity | Extract if spoken, default 1 | Dialogflow `@sys.number` handles this natively |
| Account linking | Google Sign-In type | Firebase auth is already Google-based; no OAuth server needed |
| Action visibility | Private (not published) | Personal household app; avoids Google review process |
| Function language | TypeScript | Matches firebase.json functions config |

---

## Architecture

```
User: "Hey Google, add 3 eggs to Groceries"
         │
         ▼
 Google Home speaker
         │  Actions SDK v2 invocation
         ▼
 Actions Builder (private Action)
   • Invocation names: "Groceries", "My Groceries"
   • Matches add_to_list intent
   • Extracts: item="eggs", quantity=3
   • Attaches Google Sign-In identity token
         │  HTTPS webhook POST
         ▼
 Firebase Function: addToList
   1. Verify Google ID token → UID
   2. Read users/{uid} → householdId
   3. Guess category from TS keyword map
   4. Batch-write item + history to Firestore
   5. Return spoken response
         │
         ▼
 Flutter app (real-time Firestore stream — no changes needed)
```

---

## Actions Builder Configuration

### Invocation names
- `Groceries`
- `My Groceries`

Both registered so *"Hey Google, talk to Groceries"* and *"Hey Google, add milk to Groceries"* work.

### Intent: `add_to_list`

**Training phrases:**
```
add {item}
add {quantity} {item}
add {item} to my list
add {quantity} {item} to my list
put {item} on my list
I need {quantity} {item}
I need some {item}
get {item}
```

**Slots:**

| Slot | Type | Required | Reprompt |
|---|---|---|---|
| `item` | `@sys.any` | Yes | *"What would you like to add?"* |
| `quantity` | `@sys.number` | No | — (defaults to 1) |

`@sys.any` is used for `item` to catch arbitrary grocery names without a product catalogue.

### Account linking
- Type: **Google Sign-In**
- Configured once in the Actions Console
- Google injects a verified identity token with every webhook request
- No OAuth server required

---

## Firebase Function

### File structure
```
functions/
  src/
    index.ts            ← HTTPS webhook entry point, registers intent handlers
    addToList.ts        ← add_to_list intent handler
    categoryGuesser.ts  ← TypeScript port of lib/services/category_guesser.dart
    firestoreWriter.ts  ← Firestore batch write (item + history)
  package.json
  tsconfig.json
```

### Dependencies
- `@assistant/conversation` — Actions SDK v2
- `firebase-admin` — Firestore + Admin SDK
- `firebase-functions` — HTTPS function host
- `google-auth-library` — Google ID token verification

### Per-request logic (`addToList.ts`)

```
1. Extract identityToken from request
2. Verify token with google-auth-library → sub = Firebase UID
3. Firestore: read users/{uid}.householdId
   • Missing → respond: "Please finish setting up the Groceries app first."
4. Normalise item: trim whitespace, lowercase first character
5. Guess categoryId from keyword map (categoryGuesser.ts)
6. quantity = session.params.quantity ?? 1, clamped to range [1, 99]
7. Firestore batch:
   Set households/{householdId}/items/{newId}:
     name, quantity, categoryId,
     preferredStores: [],
     pantryItemId: null,
     addedBy: { uid, displayName: "Google Home", source: "googleHome" },
     addedAt: serverTimestamp()
   Set households/{householdId}/history/{newId}:
     itemName: name, quantity, categoryId,
     action: "added", byName: "Google Home",
     at: serverTimestamp()
8. Return spoken response (see Voice Responses below)
```

### Firestore document written

```
households/{householdId}/items/{newId}
{
  name: "eggs",
  quantity: 3,
  categoryId: "dairy",           // guessed, falls back to "uncategorised"
  preferredStores: [],
  pantryItemId: null,
  addedBy: {
    uid: "<firebase_uid>",
    displayName: "Google Home",
    source: "googleHome"
  },
  addedAt: <serverTimestamp>
}
```

---

## Voice Responses

### Happy path
```
quantity = 1:  "Added {item} to your list."
quantity > 1:  "Added {quantity} {item} to your list."
```

### Error cases

| Situation | Spoken response |
|---|---|
| Token missing / invalid | *"Please open the Groceries app and sign in first."* |
| User doc missing / no householdId | *"Please finish setting up the Groceries app first."* |
| Item slot empty after reprompt | *"OK, no problem."* |
| Firestore write fails | *"Sorry, I couldn't add that right now. Try again in a moment."* |

### Deliberate simplification
Garbled item names (e.g. speech recognition errors) are written as-is — the same behaviour as the in-app voice flow. The user can delete from the app. No server-side name validation.

---

## Setup Steps (manual, one-time)

1. Create project in [Actions Console](https://console.actions.google.com)
2. Enable Google Sign-In account linking
3. Register invocation names: "Groceries", "My Groceries"
4. Define `add_to_list` intent with slots as above
5. Set fulfillment webhook URL to the deployed Firebase Function URL
6. Deploy `functions/` with `firebase deploy --only functions`
7. Each household member: open Google Home app → link "Groceries" action with their Google account

---

## Out of Scope (this iteration)

- Reading the list back aloud
- Removing items by voice
- Linking voice-added items to pantry entries
- Multi-household selection (one household per Google account)

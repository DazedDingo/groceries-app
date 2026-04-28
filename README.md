# Groceries

A shared household grocery app built with Flutter and Firebase. Create a household, invite family members, and collaborate on shopping lists, pantry tracking, and meal planning — all in real time.

## Features

### Shopping List
- One **expandable "+" FAB** holds every add path: type an item, quick voice, bulk voice, bulk paste, and scan a barcode
- Add items manually or by **voice** (speech-to-text)
- Items are auto-categorized for aisle-efficient shopping
- Filter by category, bulk-select to check off or delete
- Purchase history — see what you've bought and when

### Pantry
- Track what's at home with quantities and units
- **Scan a barcode to add to pantry** — exact-name matches auto-increment with undo, fuzzy hits prompt "stock existing or add new?", and a fresh product opens an add dialog prefilled with the OpenFoodFacts product name and a guessed category
- **Running low** button on each item — queues it to the shopping list 2 days later (with undo) so accidental taps are recoverable; promotion happens on the next pantry-screen open, no server job required
- Smarter **shelf-life guessing** — per-item-name defaults (milk 7d, bacon 7d, sweet potato 21d) beat category defaults, and once an item has 3+ `bought` events the household's median days-between-purchases becomes the real-world shelf life
- Automatic restock nudges via push notifications (Cloud Function)
- Drill into item details to adjust quantity or delete

### Recipes
- Save recipes with ingredient lists
- **"Cook This"** adds all missing ingredients to your shopping list in one tap
- Create, edit, and browse household recipes

### Household Sharing
- Google Sign-In authentication
- Create or join a household with an invite code
- All data syncs in real time across members via Firestore

### Integrations
- **Google Home / IFTTT** — "Hey Google, add milk to my grocery list" (via Cloud Function webhook)
- **Google Tasks** sync — two-way sync between your shopping list and Google Tasks
- **Google Wallet** quick-link in settings

### Other
- US / metric unit toggle with automatic conversion
- Color-coded, customizable categories
- Push notifications for restock nudges and household events
- Material 3 themed UI with an optional **refined** variant (sage palette, rounded cards, tighter typography) — toggleable in Settings

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Frontend | Flutter (Dart) |
| State management | Riverpod |
| Routing | go_router |
| Backend | Firebase (Auth, Firestore, Cloud Functions, Cloud Messaging) |
| Cloud Functions | TypeScript — category guesser, Google Home webhook, restock nudges, Google Tasks sync |
| Auth | Google Sign-In via Firebase Auth |

## Project Structure

```
lib/
├── models/          # Data models (Item, PantryItem, Recipe, Category, etc.)
├── providers/       # Riverpod providers
├── screens/
│   ├── auth/        # Login
│   ├── household/   # Household setup & invite flow
│   ├── shopping_list/  # List, history, voice input
│   ├── pantry/      # Pantry tracking
│   ├── recipes/     # Recipe CRUD & "Cook This"
│   └── settings/    # Unit toggle, categories, invites
├── services/        # Firebase service layer
└── theme/           # Material 3 theme

functions/src/       # Firebase Cloud Functions (TypeScript)
├── addToList.ts     # Google Home / IFTTT webhook
├── categoryGuesser.ts
├── nudgeRestock.ts  # Push notification nudges
└── syncGoogleTasks.ts
```

## Getting Started

### Prerequisites
- Flutter SDK (^3.11)
- A Firebase project with Auth, Firestore, Cloud Messaging, and Cloud Functions enabled
- `google-services.json` in `android/app/`

### Run locally
```bash
flutter pub get
flutter run
```

### Deploy Cloud Functions
```bash
cd functions
npm install
firebase deploy --only functions
```

## License

This project is provided as-is for personal and educational use.

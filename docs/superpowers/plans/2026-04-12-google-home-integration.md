# Google Home Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Firebase HTTPS Function that fulfills Google Home voice commands to add items to the household shopping list.

**Architecture:** An Actions Builder private Action invokes a Firebase HTTPS Function as its webhook. The Function verifies the caller's Google Sign-In identity token, looks up their household via `users/{uid}.householdId`, guesses a category from the item name, and batch-writes the item + history entry to Firestore. The Flutter app requires no changes — it already models `ItemSource.googleHome` and streams items in real time.

**Tech Stack:** TypeScript, Firebase Functions v1, `@assistant/conversation` v3, `firebase-admin` v12, `google-auth-library` v9, Jest + ts-jest

---

## File Map

| Path | Status | Responsibility |
|---|---|---|
| `functions/package.json` | Create | Dependencies, scripts, node engine |
| `functions/tsconfig.json` | Create | TypeScript compiler config |
| `functions/jest.config.js` | Create | Jest + ts-jest setup |
| `functions/.gitignore` | Create | Exclude lib/, node_modules/, .env |
| `functions/.env` | Create (gitignored) | `GOOGLE_CLIENT_ID` env var |
| `functions/src/types.ts` | Create | Shared interfaces: `WriteItemParams` |
| `functions/src/categoryGuesser.ts` | Create | Keyword → category name mapping |
| `functions/src/firestoreWriter.ts` | Create | Firestore batch write (item + history) |
| `functions/src/addToList.ts` | Create | Intent handler: verify token, lookup household, call writer |
| `functions/src/index.ts` | Create | HTTPS Function entry point, registers handler |
| `functions/test/categoryGuesser.test.ts` | Create | Unit tests for keyword matching |
| `functions/test/firestoreWriter.test.ts` | Create | Unit tests with mocked firebase-admin |
| `functions/test/addToList.test.ts` | Create | Unit tests with mocked dependencies |

---

## Task 1: Scaffold the functions/ project

**Files:**
- Create: `functions/package.json`
- Create: `functions/tsconfig.json`
- Create: `functions/jest.config.js`
- Create: `functions/.gitignore`
- Create: `functions/.env`

- [ ] **Step 1: Create package.json**

```json
{
  "name": "functions",
  "scripts": {
    "build": "tsc",
    "test": "jest",
    "deploy": "firebase deploy --only functions",
    "logs": "firebase functions:log"
  },
  "engines": { "node": "20" },
  "main": "lib/index.js",
  "dependencies": {
    "@assistant/conversation": "^3.0.0",
    "firebase-admin": "^12.0.0",
    "firebase-functions": "^4.0.0",
    "google-auth-library": "^9.0.0"
  },
  "devDependencies": {
    "@types/jest": "^29.0.0",
    "@types/node": "^20.0.0",
    "jest": "^29.0.0",
    "ts-jest": "^29.0.0",
    "typescript": "^5.0.0"
  },
  "private": true
}
```

- [ ] **Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "module": "commonjs",
    "noImplicitReturns": true,
    "noUnusedLocals": true,
    "outDir": "lib",
    "sourceMap": true,
    "strict": true,
    "target": "es2017"
  },
  "compileOnSave": true,
  "include": ["src"]
}
```

- [ ] **Step 3: Create jest.config.js**

```js
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  testMatch: ['**/test/**/*.test.ts'],
};
```

- [ ] **Step 4: Create .gitignore**

```
lib/
node_modules/
.env
```

- [ ] **Step 5: Create .env (placeholder — real value added in Task 6)**

```
GOOGLE_CLIENT_ID=PLACEHOLDER
```

- [ ] **Step 6: Install dependencies**

Run from `functions/`:
```bash
cd functions && npm install
```

Expected: `node_modules/` created, no errors.

- [ ] **Step 7: Verify TypeScript compiles on an empty src/index.ts**

```bash
mkdir -p src && echo "export {};" > src/index.ts && npm run build
```

Expected: `lib/index.js` created, no errors.

- [ ] **Step 8: Commit**

```bash
git checkout -b feat/google-home-integration
git add functions/
git commit -m "chore: scaffold Firebase Functions TypeScript project"
```

---

## Task 2: Category guesser module

**Files:**
- Create: `functions/src/categoryGuesser.ts`
- Create: `functions/src/types.ts`
- Create: `functions/test/categoryGuesser.test.ts`

- [ ] **Step 1: Create types.ts**

```typescript
// functions/src/types.ts
export interface WriteItemParams {
  householdId: string;
  uid: string;
  name: string;
  quantity: number;
  categoryId: string;
}
```

- [ ] **Step 2: Write the failing tests**

```typescript
// functions/test/categoryGuesser.test.ts
import { guessCategoryName } from '../src/categoryGuesser';

describe('guessCategoryName', () => {
  it('returns Dairy for milk', () => {
    expect(guessCategoryName('milk')).toBe('Dairy');
  });

  it('returns Meats for chicken breast', () => {
    expect(guessCategoryName('chicken breast')).toBe('Meats');
  });

  it('returns Produce for courgettes (partial match)', () => {
    expect(guessCategoryName('courgettes')).toBe('Produce');
  });

  it('is case-insensitive', () => {
    expect(guessCategoryName('MILK')).toBe('Dairy');
    expect(guessCategoryName('Eggs')).toBe('Dairy');
  });

  it('returns null for unknown items', () => {
    expect(guessCategoryName('gkflrb')).toBeNull();
  });

  it('returns Drinks for orange juice', () => {
    expect(guessCategoryName('orange juice')).toBe('Drinks');
  });

  it('returns Bakery for sourdough bread', () => {
    expect(guessCategoryName('sourdough bread')).toBe('Bakery');
  });

  it('returns Household for washing up liquid', () => {
    expect(guessCategoryName('washing up liquid')).toBe('Household');
  });
});
```

- [ ] **Step 3: Run tests — expect failure**

```bash
cd functions && npm test -- --testPathPattern=categoryGuesser
```

Expected: FAIL — `Cannot find module '../src/categoryGuesser'`

- [ ] **Step 4: Implement categoryGuesser.ts**

```typescript
// functions/src/categoryGuesser.ts

const KEYWORDS: Record<string, string> = {
  // Meats
  meat: 'Meats', chicken: 'Meats', beef: 'Meats', pork: 'Meats',
  lamb: 'Meats', mince: 'Meats', steak: 'Meats', bacon: 'Meats',
  sausage: 'Meats', ham: 'Meats', turkey: 'Meats', fish: 'Meats',
  salmon: 'Meats', tuna: 'Meats', prawn: 'Meats', shrimp: 'Meats',
  // Dairy
  milk: 'Dairy', cheese: 'Dairy', butter: 'Dairy', yogurt: 'Dairy',
  yoghurt: 'Dairy', cream: 'Dairy', egg: 'Dairy', eggs: 'Dairy',
  margarine: 'Dairy', cheddar: 'Dairy',
  // Produce
  apple: 'Produce', banana: 'Produce', orange: 'Produce', grape: 'Produce',
  strawberry: 'Produce', carrot: 'Produce', potato: 'Produce',
  onion: 'Produce', tomato: 'Produce', lettuce: 'Produce',
  spinach: 'Produce', broccoli: 'Produce', pepper: 'Produce',
  cucumber: 'Produce', mushroom: 'Produce', courgette: 'Produce',
  avocado: 'Produce', lemon: 'Produce', lime: 'Produce', garlic: 'Produce',
  fruit: 'Produce', veg: 'Produce', vegetable: 'Produce', salad: 'Produce',
  // Bakery
  bread: 'Bakery', roll: 'Bakery', bun: 'Bakery', cake: 'Bakery',
  pastry: 'Bakery', croissant: 'Bakery', muffin: 'Bakery', flour: 'Bakery',
  bagel: 'Bakery', wrap: 'Bakery', pitta: 'Bakery', loaf: 'Bakery',
  // Spices
  salt: 'Spices', spice: 'Spices', herb: 'Spices', cumin: 'Spices',
  paprika: 'Spices', oregano: 'Spices', thyme: 'Spices', basil: 'Spices',
  cinnamon: 'Spices', turmeric: 'Spices', ginger: 'Spices',
  // Frozen
  frozen: 'Frozen', 'ice cream': 'Frozen', chips: 'Frozen',
  // Drinks
  water: 'Drinks', juice: 'Drinks', beer: 'Drinks', wine: 'Drinks',
  coffee: 'Drinks', tea: 'Drinks', soda: 'Drinks', cola: 'Drinks',
  squash: 'Drinks', lemonade: 'Drinks', smoothie: 'Drinks',
  // Household
  soap: 'Household', shampoo: 'Household', detergent: 'Household',
  cleaner: 'Household', tissue: 'Household', toilet: 'Household',
  bleach: 'Household', sponge: 'Household', 'bin bag': 'Household',
  'washing up': 'Household', toothpaste: 'Household', deodorant: 'Household',
};

/**
 * Returns the category name for the given item name based on keyword matching,
 * or null if no keyword matches. Mirrors lib/services/category_guesser.dart.
 */
export function guessCategoryName(itemName: string): string | null {
  const lower = itemName.toLowerCase();
  for (const [keyword, categoryName] of Object.entries(KEYWORDS)) {
    if (lower.includes(keyword)) return categoryName;
  }
  return null;
}
```

- [ ] **Step 5: Run tests — expect pass**

```bash
cd functions && npm test -- --testPathPattern=categoryGuesser
```

Expected: PASS — 8 tests pass

- [ ] **Step 6: Commit**

```bash
git add functions/src/types.ts functions/src/categoryGuesser.ts functions/test/categoryGuesser.test.ts
git commit -m "feat: add TypeScript category guesser (port of Dart keyword map)"
```

---

## Task 3: Firestore writer module

**Files:**
- Create: `functions/src/firestoreWriter.ts`
- Create: `functions/test/firestoreWriter.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// functions/test/firestoreWriter.test.ts
import { writeItem } from '../src/firestoreWriter';
import type { WriteItemParams } from '../src/types';

// Mock firebase-admin before any imports that use it
const mockBatchSet = jest.fn();
const mockBatchCommit = jest.fn().mockResolvedValue(undefined);
const mockBatch = { set: mockBatchSet, commit: mockBatchCommit };
const mockDoc = jest.fn((path: string) => ({ path }));
const mockCollection = jest.fn((path: string) => ({
  doc: () => ({ path: `${path}/newdoc` }),
}));

jest.mock('firebase-admin', () => ({
  firestore: Object.assign(
    () => ({
      batch: () => mockBatch,
      doc: mockDoc,
      collection: mockCollection,
    }),
    {
      FieldValue: {
        serverTimestamp: () => 'SERVER_TIMESTAMP',
      },
    }
  ),
}));

const PARAMS: WriteItemParams = {
  householdId: 'hh1',
  uid: 'user1',
  name: 'milk',
  quantity: 2,
  categoryId: 'dairy-id',
};

describe('writeItem', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('calls batch.set twice (item + history)', async () => {
    await writeItem(PARAMS);
    expect(mockBatchSet).toHaveBeenCalledTimes(2);
  });

  it('commits the batch', async () => {
    await writeItem(PARAMS);
    expect(mockBatchCommit).toHaveBeenCalledTimes(1);
  });

  it('writes correct item fields', async () => {
    await writeItem(PARAMS);
    const [, itemData] = mockBatchSet.mock.calls[0];
    expect(itemData.name).toBe('milk');
    expect(itemData.quantity).toBe(2);
    expect(itemData.categoryId).toBe('dairy-id');
    expect(itemData.preferredStores).toEqual([]);
    expect(itemData.pantryItemId).toBeNull();
    expect(itemData.addedBy.source).toBe('googleHome');
    expect(itemData.addedBy.uid).toBe('user1');
    expect(itemData.addedBy.displayName).toBe('Google Home');
  });

  it('writes correct history fields', async () => {
    await writeItem(PARAMS);
    const [, histData] = mockBatchSet.mock.calls[1];
    expect(histData.itemName).toBe('milk');
    expect(histData.quantity).toBe(2);
    expect(histData.categoryId).toBe('dairy-id');
    expect(histData.action).toBe('added');
    expect(histData.byName).toBe('Google Home');
  });

  it('propagates Firestore errors', async () => {
    mockBatchCommit.mockRejectedValueOnce(new Error('Firestore unavailable'));
    await expect(writeItem(PARAMS)).rejects.toThrow('Firestore unavailable');
  });
});
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd functions && npm test -- --testPathPattern=firestoreWriter
```

Expected: FAIL — `Cannot find module '../src/firestoreWriter'`

- [ ] **Step 3: Implement firestoreWriter.ts**

```typescript
// functions/src/firestoreWriter.ts
import * as admin from 'firebase-admin';
import type { WriteItemParams } from './types';

export async function writeItem(params: WriteItemParams): Promise<void> {
  const db = admin.firestore();
  const batch = db.batch();

  const itemRef = db
    .collection(`households/${params.householdId}/items`)
    .doc();
  batch.set(itemRef, {
    name: params.name,
    quantity: params.quantity,
    categoryId: params.categoryId,
    preferredStores: [],
    pantryItemId: null,
    addedBy: {
      uid: params.uid,
      displayName: 'Google Home',
      source: 'googleHome',
    },
    addedAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const histRef = db
    .collection(`households/${params.householdId}/history`)
    .doc();
  batch.set(histRef, {
    itemName: params.name,
    categoryId: params.categoryId,
    quantity: params.quantity,
    action: 'added',
    byName: 'Google Home',
    at: admin.firestore.FieldValue.serverTimestamp(),
  });

  await batch.commit();
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd functions && npm test -- --testPathPattern=firestoreWriter
```

Expected: PASS — 5 tests pass

- [ ] **Step 5: Commit**

```bash
git add functions/src/firestoreWriter.ts functions/test/firestoreWriter.test.ts
git commit -m "feat: add Firestore batch writer for Google Home items"
```

---

## Task 4: Intent handler

**Files:**
- Create: `functions/src/addToList.ts`
- Create: `functions/test/addToList.test.ts`

- [ ] **Step 1: Write the failing tests**

```typescript
// functions/test/addToList.test.ts
import { buildHandleAddToList } from '../src/addToList';

// ── Mocks ────────────────────────────────────────────────────────────────────

const mockVerifyIdToken = jest.fn();
jest.mock('google-auth-library', () => ({
  OAuth2Client: jest.fn().mockImplementation(() => ({
    verifyIdToken: mockVerifyIdToken,
  })),
}));

const mockFirestoreGet = jest.fn();
const mockFirestoreQuery = jest.fn();
jest.mock('firebase-admin', () => ({
  firestore: () => ({
    doc: () => ({ get: mockFirestoreGet }),
    collection: () => ({
      where: () => ({ limit: () => ({ get: mockFirestoreQuery }) }),
    }),
  }),
}));

const mockWriteItem = jest.fn().mockResolvedValue(undefined);
jest.mock('../src/firestoreWriter', () => ({ writeItem: mockWriteItem }));

// ── Helpers ──────────────────────────────────────────────────────────────────

function makeConv(overrides: Record<string, unknown> = {}) {
  const messages: string[] = [];
  return {
    user: { identityToken: 'valid-token', ...overrides.user },
    session: { params: { item: 'milk', quantity: undefined, ...overrides.params } },
    add: (msg: string) => messages.push(msg),
    _messages: messages,
    ...overrides,
  } as any;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

describe('handleAddToList', () => {
  const handler = buildHandleAddToList({
    clientId: 'test-client-id',
    verifyToken: async (token: string) => {
      if (token !== 'valid-token') throw new Error('invalid');
      return 'uid-123';
    },
  });

  beforeEach(() => {
    jest.clearAllMocks();
    mockFirestoreGet.mockResolvedValue({ data: () => ({ householdId: 'hh-1' }) });
    mockFirestoreQuery.mockResolvedValue({ empty: true, docs: [] });
  });

  it('adds item with quantity 1 when quantity not specified', async () => {
    const conv = makeConv();
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'milk', quantity: 1, householdId: 'hh-1' })
    );
    expect(conv._messages[0]).toBe('Added milk to your list.');
  });

  it('adds item with specified quantity', async () => {
    const conv = makeConv({ params: { item: 'eggs', quantity: 6 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ name: 'eggs', quantity: 6 })
    );
    expect(conv._messages[0]).toBe('Added 6 eggs to your list.');
  });

  it('clamps quantity to 99 max', async () => {
    const conv = makeConv({ params: { item: 'apples', quantity: 999 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ quantity: 99 })
    );
  });

  it('clamps quantity to 1 min', async () => {
    const conv = makeConv({ params: { item: 'apples', quantity: -5 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ quantity: 1 })
    );
  });

  it('returns error when identity token is missing', async () => {
    const conv = makeConv({ user: { identityToken: undefined } });
    await handler(conv);
    expect(mockWriteItem).not.toHaveBeenCalled();
    expect(conv._messages[0]).toContain('sign in');
  });

  it('returns error when token verification fails', async () => {
    const conv = makeConv({ user: { identityToken: 'bad-token' } });
    await handler(conv);
    expect(mockWriteItem).not.toHaveBeenCalled();
    expect(conv._messages[0]).toContain('sign in');
  });

  it('returns error when user has no household', async () => {
    mockFirestoreGet.mockResolvedValue({ data: () => ({}) });
    const conv = makeConv();
    await handler(conv);
    expect(mockWriteItem).not.toHaveBeenCalled();
    expect(conv._messages[0]).toContain('setting up');
  });

  it('returns error when Firestore write fails', async () => {
    mockWriteItem.mockRejectedValueOnce(new Error('timeout'));
    const conv = makeConv();
    await handler(conv);
    expect(conv._messages[0]).toContain("couldn't add");
  });

  it('resolves category from Firestore when keyword matches', async () => {
    mockFirestoreQuery.mockResolvedValue({
      empty: false,
      docs: [{ id: 'dairy-cat-id' }],
    });
    const conv = makeConv({ params: { item: 'milk', quantity: 1 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'dairy-cat-id' })
    );
  });

  it('falls back to uncategorised when category not in Firestore', async () => {
    mockFirestoreQuery.mockResolvedValue({ empty: true, docs: [] });
    const conv = makeConv({ params: { item: 'milk', quantity: 1 } });
    await handler(conv);
    expect(mockWriteItem).toHaveBeenCalledWith(
      expect.objectContaining({ categoryId: 'uncategorised' })
    );
  });
});
```

- [ ] **Step 2: Run tests — expect failure**

```bash
cd functions && npm test -- --testPathPattern=addToList
```

Expected: FAIL — `Cannot find module '../src/addToList'`

- [ ] **Step 3: Implement addToList.ts**

```typescript
// functions/src/addToList.ts
import * as admin from 'firebase-admin';
import { OAuth2Client } from 'google-auth-library';
import { guessCategoryName } from './categoryGuesser';
import { writeItem } from './firestoreWriter';
import type { WriteItemParams } from './types';

type Conv = {
  user: { identityToken?: string };
  session: { params: Record<string, unknown> };
  add: (msg: string) => void;
};

type HandlerDeps = {
  clientId: string;
  verifyToken: (token: string) => Promise<string>; // resolves to Firebase UID
};

/**
 * Factory that creates the intent handler with injectable dependencies.
 * In production, call buildHandleAddToList() with no args to use real deps.
 * In tests, pass mock deps.
 */
export function buildHandleAddToList(deps?: Partial<HandlerDeps>) {
  const clientId = deps?.clientId ?? process.env.GOOGLE_CLIENT_ID ?? '';
  const authClient = new OAuth2Client();

  const verifyToken =
    deps?.verifyToken ??
    (async (token: string): Promise<string> => {
      const ticket = await authClient.verifyIdToken({
        idToken: token,
        audience: clientId,
      });
      const sub = ticket.getPayload()?.sub;
      if (!sub) throw new Error('No sub in token');
      return sub;
    });

  return async function handleAddToList(conv: Conv): Promise<void> {
    // 1. Verify identity token
    const identityToken = conv.user.identityToken;
    if (!identityToken) {
      conv.add('Please open the Groceries app and sign in first.');
      return;
    }

    let uid: string;
    try {
      uid = await verifyToken(identityToken);
    } catch {
      conv.add('Please open the Groceries app and sign in first.');
      return;
    }

    // 2. Look up household
    const db = admin.firestore();
    const userDoc = await db.doc(`users/${uid}`).get();
    const householdId = userDoc.data()?.householdId as string | undefined;
    if (!householdId) {
      conv.add('Please finish setting up the Groceries app first.');
      return;
    }

    // 3. Extract and validate params
    const name = ((conv.session.params.item as string) ?? '').trim();
    if (!name) {
      conv.add('What would you like to add?');
      return;
    }
    const rawQty = Number(conv.session.params.quantity);
    const quantity = Math.min(Math.max(1, Math.round(isNaN(rawQty) ? 1 : rawQty)), 99);

    // 4. Guess category
    const categoryGuess = guessCategoryName(name);
    let categoryId = 'uncategorised';
    if (categoryGuess) {
      const snap = await db
        .collection(`households/${householdId}/categories`)
        .where('name', '==', categoryGuess)
        .limit(1)
        .get();
      if (!snap.empty) categoryId = snap.docs[0].id;
    }

    // 5. Write to Firestore
    const params: WriteItemParams = { householdId, uid, name, quantity, categoryId };
    try {
      await writeItem(params);
    } catch {
      conv.add("Sorry, I couldn't add that right now. Try again in a moment.");
      return;
    }

    // 6. Respond
    conv.add(
      quantity === 1
        ? `Added ${name} to your list.`
        : `Added ${quantity} ${name} to your list.`
    );
  };
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd functions && npm test -- --testPathPattern=addToList
```

Expected: PASS — 10 tests pass

- [ ] **Step 5: Commit**

```bash
git add functions/src/addToList.ts functions/test/addToList.test.ts
git commit -m "feat: add Google Home add_to_list intent handler"
```

---

## Task 5: HTTPS Function entry point

**Files:**
- Modify: `functions/src/index.ts`

- [ ] **Step 1: Run all tests to confirm clean baseline**

```bash
cd functions && npm test
```

Expected: All tests pass (18 total)

- [ ] **Step 2: Implement index.ts**

```typescript
// functions/src/index.ts
import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { conversation } from '@assistant/conversation';
import { buildHandleAddToList } from './addToList';

admin.initializeApp();

const app = conversation();
app.handle('add_to_list', buildHandleAddToList());

export const fulfillment = functions.https.onRequest(app as any);
```

- [ ] **Step 3: Build TypeScript**

```bash
cd functions && npm run build
```

Expected: `lib/` directory created with compiled JS, no errors.

- [ ] **Step 4: Run all tests — confirm still passing**

```bash
cd functions && npm test
```

Expected: All tests still pass.

- [ ] **Step 5: Commit**

```bash
git add functions/src/index.ts
git commit -m "feat: wire add_to_list handler into Firebase HTTPS Function"
```

---

## Task 6: Deploy and get the webhook URL

**Prerequisites:** Firebase CLI logged in (`firebase login`), Firebase project linked.

- [ ] **Step 1: Set the GOOGLE_CLIENT_ID env var for deployment**

You will get the client ID from Actions Console in Task 7. For now, set a temporary placeholder so deployment works:

```bash
cd /path/to/groceries-app
firebase functions:config:set actions.client_id="PLACEHOLDER"
```

Then update `functions/.env`:
```
GOOGLE_CLIENT_ID=PLACEHOLDER
```

- [ ] **Step 2: Deploy the function**

```bash
firebase deploy --only functions
```

Expected output (last lines):
```
✔  functions[fulfillment(us-central1)]: Successful create operation.
Function URL (fulfillment): https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/fulfillment
```

**Copy this URL** — you will paste it into Actions Builder in Task 7.

- [ ] **Step 3: Verify the function is alive**

```bash
curl -X POST https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/fulfillment \
  -H "Content-Type: application/json" \
  -d '{}'
```

Expected: HTTP 200 with a JSON response (may contain an error about missing handler — that's fine, it proves the function is running).

- [ ] **Step 4: Commit**

```bash
git add functions/.env
# .env is gitignored — nothing to commit for it
git commit -m "feat: deploy Google Home fulfillment Function" --allow-empty
```

---

## Task 7: Actions Builder setup (manual steps)

This task configures the Google Action in the Actions Console. No code is written here.

- [ ] **Step 1: Create the project**

1. Go to [console.actions.google.com](https://console.actions.google.com)
2. Click **New project**
3. Select your existing Firebase project from the dropdown (same project as the app)
4. Click **Import project**
5. When asked "What kind of action?", choose **Custom**
6. Choose **Blank project**

- [ ] **Step 2: Set display name and invocation**

1. In the left sidebar, click **Develop → Invocation**
2. Set Display name: `Groceries`
3. Click **Save**
4. Go to **Develop → Actions**
5. Click **Add invocation**
6. Add a second invocation name: `My Groceries`

- [ ] **Step 3: Create the add_to_list intent**

1. Go to **Develop → Intents**
2. Click **+** to create a new intent
3. Name it exactly: `add_to_list`
4. Under **Training phrases**, add all of these (press Enter after each):
   ```
   add milk
   add 3 eggs
   add milk to my list
   add 3 eggs to my list
   put bread on my list
   I need 2 litres of milk
   I need some cheese
   get apples
   ```
5. For each phrase that contains an item, highlight the item word and tag it as `item` slot
6. For each phrase that contains a number, highlight it and tag it as `quantity` slot

- [ ] **Step 4: Configure slots on the intent**

1. Still on the `add_to_list` intent page, go to **Slot filling**
2. Add slot: name=`item`, type=`@sys.any`, required=`true`
   - Prompt: `What would you like to add?`
3. Add slot: name=`quantity`, type=`@sys.number`, required=`false`

- [ ] **Step 5: Set fulfillment webhook**

1. Still on `add_to_list`, scroll to **Fulfillment**
2. Enable **Call your webhook**
3. Enter the handler name: `add_to_list`
4. Go to **Develop → Webhooks**
5. Choose **HTTPS endpoint**
6. Paste the Firebase Function URL from Task 6 Step 2:
   `https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net/fulfillment`
7. Click **Save**

- [ ] **Step 6: Configure Google Sign-In account linking**

1. Go to **Deploy → Account linking**
2. Linking type: **Google Sign-In**
3. Click **Save**
4. Copy the **Client ID** shown on this page (looks like `123456-abc.apps.googleusercontent.com`)

- [ ] **Step 7: Set the real GOOGLE_CLIENT_ID and redeploy**

```bash
# Update functions/.env with the real client ID
echo "GOOGLE_CLIENT_ID=123456-abc.apps.googleusercontent.com" > functions/.env

# Redeploy
firebase deploy --only functions
```

- [ ] **Step 8: Test in the Actions Simulator**

1. In Actions Console, go to **Test**
2. Type: `Talk to Groceries`
3. Expected: Action launches, says hello
4. Type: `Add milk`
5. Expected: `"Added milk to your list."` — item appears in the Flutter app
6. Type: `Add 3 eggs to my list`
7. Expected: `"Added 3 eggs to your list."` — item with quantity 3 appears

- [ ] **Step 9: Link on a real Google Home device**

1. Open the Google Home app on your phone
2. Tap **+** → **Set up device** → **Works with Google**
3. Search for your Action name (`Groceries` or `My Groceries`)
4. Tap it and follow the account linking flow (signs in with your Google account)
5. Say *"Hey Google, add milk to Groceries"* — confirm it appears in the app

- [ ] **Step 10: Create PR**

```bash
git push origin feat/google-home-integration
gh pr create \
  --title "feat: Google Home integration (add items by voice)" \
  --body "$(cat <<'EOF'
## Summary
- Firebase HTTPS Function fulfilling Actions Builder webhooks
- Google Sign-In account linking — maps Google identity to Firebase household
- Category guessing ported from Dart keyword map
- Atomic Firestore batch write (item + history entry)
- 18 unit tests covering all error paths

## Test plan
- [ ] `npm test` passes in functions/
- [ ] Actions Simulator: add item, add item with quantity
- [ ] Real device: link action and test voice command

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Covered by |
|---|---|
| Private Google Action, invocable as "Groceries" or "My Groceries" | Task 7 Steps 2-3 |
| Single intent: add item + optional quantity | Task 7 Step 3-4 |
| Google Sign-In account linking | Task 7 Step 6 |
| Verify identity token → Firebase UID | Task 4, `buildHandleAddToList` |
| Read `users/{uid}.householdId` | Task 4, Firestore lookup |
| Category guessing from keyword map | Task 2, `guessCategoryName` |
| Firestore batch write (item + history) | Task 3, `writeItem` |
| `source: "googleHome"` on addedBy | Task 3, verified in tests |
| Happy path voice responses | Task 4, tests cover qty=1 and qty>1 |
| All 4 error cases (no token, no household, empty item, write fail) | Task 4, tests cover all |
| Quantity clamped [1, 99] | Task 4, tests cover min/max |
| PR to GitHub | Task 7 Step 10 |

**No gaps found.**

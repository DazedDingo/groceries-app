// functions/src/addToList.ts
import * as admin from 'firebase-admin';
import { guessCategoryName } from './categoryGuesser';
import { writeItem } from './firestoreWriter';
import type { WriteItemParams } from './types';

/**
 * Parse an item string like "3 eggs" into { quantity, name }.
 * If no leading number is found, quantity defaults to 1.
 */
const UNIT_REGEX = /^(pounds?|lbs?|kilos?|kg|grams?|g|ounces?|oz|litres?|liters?|l|ml|cups?|pints?|gallons?|bags?|boxes?|cans?|bottles?|packs?|packets?|bunche?s?|loave?s|dozen|doz)\b\s*(?:of\s+)?/i;

const UNIT_NORMALISE: Record<string, string> = {
  pound: 'lb', pounds: 'lb', lbs: 'lb',
  kilo: 'kg', kilos: 'kg',
  gram: 'g', grams: 'g',
  ounce: 'oz', ounces: 'oz',
  litre: 'L', litres: 'L', liter: 'L', liters: 'L', l: 'L',
  cup: 'cups',
  pint: 'pints', gallon: 'gallons',
  bag: 'bags', box: 'boxes', can: 'cans', bottle: 'bottles',
  pack: 'packs', packet: 'packs', packets: 'packs',
  bunch: 'bunches', bunches: 'bunches',
  loaf: 'loaves', loaves: 'loaves',
  doz: 'dozen',
};

export interface ParsedItem { quantity: number; name: string; unit?: string }

export function parseItemString(raw: string): ParsedItem {
  const trimmed = raw.trim();
  const match = trimmed.match(/^(\d+)\s+(.+)$/);
  if (match) {
    const rawQty = Math.max(1, Math.round(Number(match[1])));
    const rest = match[2].trim();
    const unitMatch = rest.match(UNIT_REGEX);
    if (unitMatch) {
      const rawUnit = unitMatch[1].toLowerCase();
      const unit = UNIT_NORMALISE[rawUnit] ?? rawUnit;
      const name = rest.slice(unitMatch[0].length).trim();
      // No upper clamp when unit is present (300g is valid)
      return { quantity: rawQty, name: name || rest, unit };
    }
    // Clamp unitless quantities to 99
    const qty = Math.min(rawQty, 99);
    return { quantity: qty, name: rest };
  }
  return { quantity: 1, name: trimmed };
}

type Req = {
  query: Record<string, string | undefined>;
  headers: Record<string, string | undefined>;
  body: Record<string, unknown>;
  method?: string;
};

type Res = {
  status: (code: number) => Res;
  json: (data: unknown) => void;
  send: (data: string) => void;
};

export type HandleIftttDeps = {
  getSecret: () => string;
  getUserUid: () => string;
};

/**
 * HTTPS webhook handler for IFTTT.
 * Validates a shared secret, extracts the item, guesses category, and writes to Firestore.
 */
export async function handleIftttWebhook(
  req: Req,
  res: Res,
  deps?: Partial<HandleIftttDeps>,
): Promise<void> {
  // 1. Validate secret
  const secret = deps?.getSecret?.() ?? process.env.IFTTT_WEBHOOK_SECRET ?? '';
  const providedKey =
    req.query.key ??
    req.headers.authorization?.replace(/^Bearer\s+/i, '');

  if (!secret || providedKey !== secret) {
    res.status(401).json({ error: 'Unauthorized' });
    return;
  }

  // 2. Extract item name (IFTTT sends "item" or "value1")
  const rawItem = (req.body.item as string) ?? (req.body.value1 as string) ?? '';
  if (!rawItem.trim()) {
    res.status(400).json({ error: 'Missing item' });
    return;
  }

  // 3. Parse quantity + name
  const { quantity, name, unit } = parseItemString(rawItem);
  const lowerName = name.toLowerCase();

  // 4. Guess category
  const categoryGuess = guessCategoryName(lowerName);

  // 5. Look up householdId
  const uid = deps?.getUserUid?.() ?? process.env.IFTTT_USER_UID ?? '';
  const db = admin.firestore();

  let householdId: string | undefined;
  try {
    const userDoc = await db.doc(`users/${uid}`).get();
    householdId = userDoc.data()?.householdId as string | undefined;
  } catch {
    res.status(500).json({ error: 'Failed to look up user' });
    return;
  }

  if (!householdId) {
    res.status(500).json({ error: 'User has no household' });
    return;
  }

  // 6. Resolve category doc ID
  let categoryId = 'uncategorised';
  if (categoryGuess) {
    try {
      const snap = await db
        .collection(`households/${householdId}/categories`)
        .where('name', '==', categoryGuess)
        .limit(1)
        .get();
      if (!snap.empty) categoryId = snap.docs[0].id;
    } catch {
      // fallback to uncategorised
    }
  }

  // 7. Write to Firestore
  const params: WriteItemParams = { householdId, uid, name: lowerName, quantity, unit, categoryId };
  try {
    await writeItem(params);
  } catch {
    res.status(500).json({ error: 'Failed to write item' });
    return;
  }

  // 8. Record last-webhook status (best-effort; failure here shouldn't break the
  //    write that just succeeded). Powers the "last trigger Xm ago" line in
  //    Settings → Advanced.
  try {
    await db.doc(`households/${householdId}/config/webhookStatus`).set(
      {
        lastWebhookAt: admin.firestore.FieldValue.serverTimestamp(),
        lastItemName: lowerName,
        lastQuantity: quantity,
      },
      { merge: true },
    );
  } catch {
    // swallow — status is non-critical
  }

  // 9. Success
  res.status(200).json({ ok: true, name: lowerName, quantity, categoryId });
}

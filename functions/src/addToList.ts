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
    let householdId: string | undefined;
    try {
      const userDoc = await db.doc(`users/${uid}`).get();
      householdId = userDoc.data()?.householdId as string | undefined;
    } catch {
      conv.add("Sorry, I couldn't add that right now. Try again in a moment.");
      return;
    }
    if (!householdId) {
      conv.add('Please finish setting up the Groceries app first.');
      return;
    }

    // 3. Extract and validate params
    const rawName = ((conv.session.params.item as string) ?? '').trim();
    const name = rawName.length > 0 ? rawName[0].toLowerCase() + rawName.slice(1) : rawName;
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

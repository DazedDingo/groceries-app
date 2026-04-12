import * as admin from 'firebase-admin';
import type { WriteItemParams } from './types.js';

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

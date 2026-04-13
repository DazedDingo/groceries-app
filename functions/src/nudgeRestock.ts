import * as admin from 'firebase-admin';

/**
 * Check all pantry items across all households for restock nudges.
 * If an item has restockAfterDays set and enough time has passed since
 * lastNudgedAt (or lastPurchasedAt), and the item is below optimal,
 * auto-add it to the shopping list and update lastNudgedAt.
 */
export async function nudgeRestock(): Promise<{ nudged: number }> {
  const db = admin.firestore();
  const now = new Date();
  let nudged = 0;

  // Get all households
  const householdsSnap = await db.collection('households').get();

  for (const householdDoc of householdsSnap.docs) {
    const householdId = householdDoc.id;
    const pantrySnap = await db
      .collection(`households/${householdId}/pantry`)
      .where('restockAfterDays', '>', 0)
      .get();

    for (const pantryDoc of pantrySnap.docs) {
      const data = pantryDoc.data();
      const restockAfterDays: number = data.restockAfterDays;
      const currentQty: number = data.currentQuantity ?? 0;
      const optimalQty: number = data.optimalQuantity ?? 1;
      const name: string = data.name ?? '';
      const categoryId: string = data.categoryId ?? 'uncategorised';

      // Only nudge if below optimal
      if (currentQty >= optimalQty) continue;

      // Check if enough time has passed
      const lastNudged = data.lastNudgedAt?.toDate?.() as Date | undefined;
      const lastPurchased = data.lastPurchasedAt?.toDate?.() as Date | undefined;
      const baseline = lastNudged ?? lastPurchased ?? new Date(0);
      const daysSince = (now.getTime() - baseline.getTime()) / (1000 * 60 * 60 * 24);

      if (daysSince < restockAfterDays) continue;

      // Check if item already exists on the shopping list
      const existingSnap = await db
        .collection(`households/${householdId}/items`)
        .where('name', '==', name.toLowerCase())
        .limit(1)
        .get();
      if (!existingSnap.empty) {
        // Already on the list — just update lastNudgedAt to avoid re-checking
        await pantryDoc.ref.update({
          lastNudgedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        continue;
      }

      // Add to shopping list
      const quantity = optimalQty - currentQty;
      const batch = db.batch();

      const itemRef = db.collection(`households/${householdId}/items`).doc();
      batch.set(itemRef, {
        name: name.toLowerCase(),
        quantity,
        unit: null,
        categoryId,
        preferredStores: [],
        pantryItemId: pantryDoc.id,
        recipeSource: null,
        addedBy: {
          uid: 'system',
          displayName: 'Restock nudge',
          source: 'app',
        },
        addedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      const histRef = db.collection(`households/${householdId}/history`).doc();
      batch.set(histRef, {
        itemName: name.toLowerCase(),
        categoryId,
        quantity,
        action: 'added',
        byName: 'Restock nudge',
        at: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update lastNudgedAt
      batch.update(pantryDoc.ref, {
        lastNudgedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();
      nudged++;
    }
  }

  return { nudged };
}

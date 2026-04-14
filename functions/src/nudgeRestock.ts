import * as admin from 'firebase-admin';

/**
 * Check all pantry items across all households for restock nudges.
 *
 * Two paths:
 * - High-priority items: nudge fires immediately when below optimal,
 *   no time-delay check.
 * - Regular items: must have restockAfterDays set and enough time must
 *   have passed since lastNudgedAt / lastPurchasedAt.
 */
export async function nudgeRestock(): Promise<{ nudged: number }> {
  const db = admin.firestore();
  const now = new Date();
  let nudged = 0;

  const householdsSnap = await db.collection('households').get();

  for (const householdDoc of householdsSnap.docs) {
    const householdId = householdDoc.id;

    // Fetch both query sets, deduplicate by doc id
    const [scheduledSnap, prioritySnap] = await Promise.all([
      db.collection(`households/${householdId}/pantry`)
        .where('restockAfterDays', '>', 0)
        .get(),
      db.collection(`households/${householdId}/pantry`)
        .where('isHighPriority', '==', true)
        .get(),
    ]);

    const seen = new Set<string>();
    const candidates: Array<{ doc: FirebaseFirestore.QueryDocumentSnapshot; skipDelayCheck: boolean }> = [];

    for (const doc of scheduledSnap.docs) {
      seen.add(doc.id);
      candidates.push({ doc, skipDelayCheck: false });
    }
    for (const doc of prioritySnap.docs) {
      if (!doc.data().isHighPriority) continue; // guard against mock/stale data
      if (!seen.has(doc.id)) {
        candidates.push({ doc, skipDelayCheck: true });
      } else {
        // Already in scheduled set — skip delay since it is high priority
        const idx = candidates.findIndex(c => c.doc.id === doc.id);
        if (idx !== -1) candidates[idx].skipDelayCheck = true;
      }
    }

    for (const { doc: pantryDoc, skipDelayCheck } of candidates) {
      const data = pantryDoc.data();
      const currentQty: number = data.currentQuantity ?? 0;
      const optimalQty: number = data.optimalQuantity ?? 1;
      const name: string = data.name ?? '';
      const categoryId: string = data.categoryId ?? 'uncategorised';

      if (currentQty >= optimalQty) continue;

      if (!skipDelayCheck) {
        const restockAfterDays: number = data.restockAfterDays;
        const lastNudged = data.lastNudgedAt?.toDate?.() as Date | undefined;
        const lastPurchased = data.lastPurchasedAt?.toDate?.() as Date | undefined;
        const baseline = lastNudged ?? lastPurchased ?? new Date(0);
        const daysSince = (now.getTime() - baseline.getTime()) / (1000 * 60 * 60 * 24);
        if (daysSince < restockAfterDays) continue;
      }

      // Check if item already exists on the shopping list
      const existingSnap = await db
        .collection(`households/${householdId}/items`)
        .where('name', '==', name.toLowerCase())
        .limit(1)
        .get();
      if (!existingSnap.empty) {
        await pantryDoc.ref.update({
          lastNudgedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
        continue;
      }

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

      batch.update(pantryDoc.ref, {
        lastNudgedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      await batch.commit();
      nudged++;
    }
  }

  return { nudged };
}

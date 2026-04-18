import { onCall, HttpsError } from 'firebase-functions/v2/https';
import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';
import {
  DEBOUNCE_WINDOW_MS,
  validateInput,
} from './issueQueue.js';

/**
 * Enqueues an issue report. If the caller already has a pending batch in this
 * household, appends to it and resets the 10-minute debounce window. Otherwise
 * opens a new batch. The scheduled `processIssueQueue` function picks batches
 * up once their dispatch time has passed and files them on GitHub.
 */
export const submitIssue = onCall(
  { region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }

    const householdId = String(request.data?.householdId ?? '').trim();
    if (householdId.length === 0) {
      throw new HttpsError('invalid-argument', 'householdId is required');
    }

    let title: string;
    let description: string;
    try {
      const v = validateInput(request.data?.title, request.data?.description);
      title = v.title;
      description = v.description;
    } catch (e) {
      throw new HttpsError('invalid-argument', (e as Error).message);
    }

    const uid = request.auth.uid;
    const submitter =
      (request.auth.token.name as string | undefined) ||
      (request.auth.token.email as string | undefined) ||
      uid;

    const db = admin.firestore();

    // Verify the caller is actually a member of this household.
    const memberSnap = await db
      .doc(`households/${householdId}/members/${uid}`)
      .get();
    if (!memberSnap.exists) {
      throw new HttpsError('permission-denied', 'Not a member of this household');
    }

    const batchesCol = db.collection(`households/${householdId}/issueBatches`);

    // Find any already-open batch for this uid. We do the query outside the
    // transaction (Firestore only lets transactions act on refs, not queries)
    // and then re-verify status inside the tx to avoid racing another
    // submission that dispatched or cancelled in between.
    const pendingSnap = await batchesCol
      .where('uid', '==', uid)
      .where('status', '==', 'pending')
      .limit(1)
      .get();

    const now = admin.firestore.Timestamp.now();
    const dispatchAt = admin.firestore.Timestamp.fromMillis(
      now.toMillis() + DEBOUNCE_WINDOW_MS,
    );
    const newItem = {
      title,
      description,
      submittedAt: now,
    };

    const result = await db.runTransaction(async (tx) => {
      if (!pendingSnap.empty) {
        const ref = pendingSnap.docs[0].ref;
        const fresh = await tx.get(ref);
        const data = fresh.data();
        if (fresh.exists && data?.status === 'pending') {
          tx.update(ref, {
            items: admin.firestore.FieldValue.arrayUnion(newItem),
            dispatchAt,
            updatedAt: now,
          });
          return {
            batchId: ref.id,
            appended: true,
            itemCount: (data.items?.length ?? 0) + 1,
          };
        }
      }
      const ref = batchesCol.doc();
      tx.set(ref, {
        uid,
        submitter,
        items: [newItem],
        createdAt: now,
        dispatchAt,
        status: 'pending',
      });
      return { batchId: ref.id, appended: false, itemCount: 1 };
    });

    logger.info('Issue enqueued', {
      householdId,
      batchId: result.batchId,
      appended: result.appended,
      itemCount: result.itemCount,
    });

    return {
      batchId: result.batchId,
      dispatchAtMs: dispatchAt.toMillis(),
      itemCount: result.itemCount,
      appended: result.appended,
    };
  },
);

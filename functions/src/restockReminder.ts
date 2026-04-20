import * as admin from 'firebase-admin';
import * as logger from 'firebase-functions/logger';

export interface RestockReminderBody {
  title: string;
  body: string;
}

/**
 * Build the FCM title/body for the "grocery shopping today?" nudge.
 *
 * The title is always the question prompt; the body lists items with a soft
 * cap on length. If the full item list won't fit in a standard one-line
 * notification body, we keep as many whole names as will fit and append
 * ", etc." so the user knows the list was truncated.
 *
 * [maxBodyLen] defaults to 80 — slightly under Android's typical single-line
 * body truncation point, so the reminder stays readable on the lock screen
 * without needing to expand the notification.
 */
export function buildRestockMessage(
  itemNames: string[],
  maxBodyLen = 80,
): RestockReminderBody {
  const title = 'Grocery shopping today?';
  const suffix = ' need to be bought!';
  const etcMark = ', etc.';

  // Degenerate inputs — still return a valid body so the caller can decide
  // whether to fire at all.
  if (itemNames.length === 0) {
    return { title, body: `Check your pantry!` };
  }

  const joined = itemNames.join(', ');
  if (joined.length + suffix.length <= maxBodyLen) {
    return { title, body: joined + suffix };
  }

  // Items won't all fit. Keep full item names + ", etc." + " need to be bought!"
  const innerBudget = maxBodyLen - suffix.length - etcMark.length;
  const kept: string[] = [];
  let used = 0;
  for (const name of itemNames) {
    const added = kept.length === 0 ? name.length : used + 2 + name.length;
    if (added > innerBudget) break;
    kept.push(name);
    used = added;
  }

  if (kept.length === 0) {
    // Even the first item is too long on its own — include it anyway; the OS
    // can truncate. Better an over-long body than a generic message that
    // hides the actual signal.
    return { title, body: itemNames[0] + etcMark + suffix };
  }
  return { title, body: kept.join(', ') + etcMark + suffix };
}

export interface SendRestockRemindersResult {
  sent: number;
  skipped: number;
  errors: number;
}

/**
 * Send the household-level "grocery shopping today?" reminder to every
 * configured household whose cadence has lapsed and whose local time matches
 * the user's preferred hour (±1 hour tolerance).
 *
 * Runs hourly via a scheduled trigger. No-op for households where the
 * reminder is disabled, no pantry items are below optimal, or nobody has
 * registered an FCM token yet.
 */
export async function sendRestockReminders(
  now: Date = new Date(),
): Promise<SendRestockRemindersResult> {
  const db = admin.firestore();
  const messaging = admin.messaging();
  let sent = 0;
  let skipped = 0;
  let errors = 0;

  const householdsSnap = await db.collection('households').get();

  for (const householdDoc of householdsSnap.docs) {
    const householdId = householdDoc.id;
    try {
      const configDoc = await db
        .doc(`households/${householdId}/config/restockReminder`)
        .get();
      const config = configDoc.data() ?? {};
      if (!config.enabled) {
        skipped++;
        continue;
      }

      const cadenceDays: number = config.cadenceDays ?? 2;
      const preferredHour: number = config.preferredHour ?? 9;
      const offsetMinutes: number = config.timezoneOffsetMinutes ?? 0;
      const lastSentAt = config.lastSentAt?.toDate?.() as Date | undefined;

      // Convert "now" to the household's local time so the comparison with
      // preferredHour is timezone-aware. offsetMinutes = local - UTC.
      const localMs = now.getTime() + offsetMinutes * 60 * 1000;
      const localHour = Math.floor(localMs / (60 * 60 * 1000)) % 24;
      const normalisedLocalHour = ((localHour % 24) + 24) % 24;
      if (normalisedLocalHour !== preferredHour) {
        skipped++;
        continue;
      }

      if (lastSentAt) {
        const msSince = now.getTime() - lastSentAt.getTime();
        // Fire as long as we're at least cadenceDays - 0.5 since last send.
        // This tolerance avoids a single missed hour (clock skew, function
        // cold start) pushing delivery out by a whole extra cadence cycle.
        const minGapMs = (cadenceDays * 24 - 0.5) * 60 * 60 * 1000;
        if (msSince < minGapMs) {
          skipped++;
          continue;
        }
      }

      // Collect pantry items below optimal
      const pantrySnap = await db
        .collection(`households/${householdId}/pantry`)
        .get();
      const itemNames: string[] = [];
      for (const d of pantrySnap.docs) {
        const data = d.data();
        const curr = data.currentQuantity ?? 0;
        const opt = data.optimalQuantity ?? 1;
        const name = data.name as string | undefined;
        if (curr < opt && name && name.trim()) {
          itemNames.push(name.trim());
        }
      }
      if (itemNames.length === 0) {
        skipped++;
        continue;
      }
      // Alphabetical order — keeps the prefix of a truncated list
      // deterministic so users see the same items across re-sends.
      itemNames.sort((a, b) => a.localeCompare(b));

      const membersSnap = await db
        .collection(`households/${householdId}/members`)
        .get();
      const tokens = membersSnap.docs
        .map((d) => d.data().fcmToken as string | undefined)
        .filter((t): t is string => !!t && t.trim().length > 0);
      if (tokens.length === 0) {
        skipped++;
        continue;
      }

      const { title, body } = buildRestockMessage(itemNames);

      await messaging.sendEachForMulticast({
        tokens,
        notification: { title, body },
        android: {
          notification: {
            channelId: 'restock_nudges',
            priority: 'default',
          },
        },
        data: { kind: 'restockReminder' },
      });

      await configDoc.ref.set(
        { lastSentAt: admin.firestore.FieldValue.serverTimestamp() },
        { merge: true },
      );
      sent++;
    } catch (err) {
      errors++;
      logger.error('Restock reminder failed for household', {
        householdId,
        error: err instanceof Error ? err.message : String(err),
      });
    }
  }

  return { sent, skipped, errors };
}

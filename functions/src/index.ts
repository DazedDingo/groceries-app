import * as admin from 'firebase-admin';
import * as functionsV1 from 'firebase-functions/v1';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { handleIftttWebhook } from './addToList.js';
import { syncGoogleTasks } from './syncGoogleTasks.js';
import { nudgeRestock } from './nudgeRestock.js';
export { submitIssue } from './submitIssue.js';

admin.initializeApp();

// Keep as v1 — existing deployed 1st-gen function
export const fulfillment = functionsV1.https.onRequest(handleIftttWebhook as any);

// v2 scheduled function — polls Google Tasks every 3 minutes
export const syncTasksV2 = onSchedule('every 3 minutes', async () => {
  const result = await syncGoogleTasks();

  // Always log abnormal outcomes so the flow is diagnosable.
  if (!result.listFound) {
    logger.warn('Google Tasks list not found', {
      looking_for: result.listName,
      available: result.availableLists,
    });
  } else if (result.synced > 0 || result.errors > 0) {
    logger.info('Google Tasks sync', result);
  } else {
    // List found but nothing new — log once per hour on the xx:00 tick.
    const now = new Date();
    if (now.getUTCMinutes() < 3) {
      logger.info('Google Tasks idle', {
        listName: result.listName,
        tasksSeen: result.tasksSeen,
        skippedAlreadyProcessed: result.skippedAlreadyProcessed,
      });
    }
  }
});

// Check pantry items for restock nudges every 6 hours
export const restockNudge = onSchedule('every 6 hours', async () => {
  const result = await nudgeRestock();
  if (result.nudged > 0) {
    logger.info('Restock nudge', result);
  }
});

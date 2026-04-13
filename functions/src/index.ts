import * as admin from 'firebase-admin';
import * as functionsV1 from 'firebase-functions/v1';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import * as logger from 'firebase-functions/logger';
import { handleIftttWebhook } from './addToList.js';
import { syncGoogleTasks } from './syncGoogleTasks.js';
import { nudgeRestock } from './nudgeRestock.js';

admin.initializeApp();

// Keep as v1 — existing deployed 1st-gen function
export const fulfillment = functionsV1.https.onRequest(handleIftttWebhook as any);

// v2 scheduled function — polls Google Tasks every 3 minutes
export const syncTasksV2 = onSchedule('every 3 minutes', async () => {
  const result = await syncGoogleTasks();
  if (result.synced > 0 || result.errors > 0) {
    logger.info('Google Tasks sync', result);
  }
});

// Check pantry items for restock nudges every 6 hours
export const restockNudge = onSchedule('every 6 hours', async () => {
  const result = await nudgeRestock();
  if (result.nudged > 0) {
    logger.info('Restock nudge', result);
  }
});

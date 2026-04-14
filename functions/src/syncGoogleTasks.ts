import * as admin from 'firebase-admin';
import { google, tasks_v1 } from 'googleapis';
import { guessCategoryName } from './categoryGuesser.js';
import { writeItem } from './firestoreWriter.js';
import { parseItemString } from './addToList.js';
import type { WriteItemParams } from './types.js';

export interface SyncResult {
  synced: number;
  errors: number;
  listFound: boolean;
  tasksSeen: number;
  skippedAlreadyProcessed: number;
  listName: string;
  availableLists?: string[];
}

export interface SyncDeps {
  getTasksClient: () => tasks_v1.Tasks;
  getDb: () => FirebaseFirestore.Firestore;
  uid: string;
  listName: string;
}

function buildTasksClient(): tasks_v1.Tasks {
  const oauth2Client = new google.auth.OAuth2(
    process.env.GOOGLE_OAUTH_CLIENT_ID,
    process.env.GOOGLE_OAUTH_CLIENT_SECRET,
  );
  oauth2Client.setCredentials({
    refresh_token: process.env.GOOGLE_TASKS_REFRESH_TOKEN,
  });
  return google.tasks({ version: 'v1', auth: oauth2Client });
}

async function findTaskList(
  client: tasks_v1.Tasks,
  listName: string,
): Promise<{ id: string | null; available: string[] }> {
  const res = await client.tasklists.list({ maxResults: 100 });
  const lists = res.data.items ?? [];
  const available = lists.map((l) => l.title ?? '').filter(Boolean);
  const match = lists.find(
    (l) => l.title?.toLowerCase() === listName.toLowerCase(),
  );
  return { id: match?.id ?? null, available };
}

export async function syncGoogleTasks(
  deps?: Partial<SyncDeps>,
): Promise<SyncResult> {
  const client = deps?.getTasksClient?.() ?? buildTasksClient();
  const db = deps?.getDb?.() ?? admin.firestore();
  const uid = deps?.uid ?? process.env.IFTTT_USER_UID ?? '';
  const listName =
    deps?.listName ?? process.env.GOOGLE_TASKS_LIST_NAME ?? 'My Tasks';

  // 1. Find the task list
  const { id: listId, available } = await findTaskList(client, listName);
  if (!listId) {
    return {
      synced: 0,
      errors: 0,
      listFound: false,
      tasksSeen: 0,
      skippedAlreadyProcessed: 0,
      listName,
      availableLists: available,
    };
  }

  // 2. Get incomplete tasks
  const tasksRes = await client.tasks.list({
    tasklist: listId,
    showCompleted: false,
    maxResults: 100,
  });
  const tasks = tasksRes.data.items ?? [];

  if (tasks.length === 0) {
    return {
      synced: 0,
      errors: 0,
      listFound: true,
      tasksSeen: 0,
      skippedAlreadyProcessed: 0,
      listName,
    };
  }

  // 3. Look up household
  const userDoc = await db.doc(`users/${uid}`).get();
  const householdId = userDoc.data()?.householdId as string | undefined;
  if (!householdId) {
    return {
      synced: 0,
      errors: tasks.length,
      listFound: true,
      tasksSeen: tasks.length,
      skippedAlreadyProcessed: 0,
      listName,
    };
  }

  let synced = 0;
  let errors = 0;
  let skippedAlreadyProcessed = 0;

  for (const task of tasks) {
    const taskId = task.id;
    const title = task.title?.trim();
    if (!taskId || !title) continue;

    try {
      // 4. Check if already processed
      const processedRef = db.doc(`sync/googleTasks/processed/${taskId}`);
      const processedDoc = await processedRef.get();
      if (processedDoc.exists) {
        skippedAlreadyProcessed++;
        continue;
      }

      // 5. Parse and categorize
      const { quantity, name, unit } = parseItemString(title);
      const lowerName = name.toLowerCase();
      const categoryGuess = guessCategoryName(lowerName);

      let categoryId = 'uncategorised';
      if (categoryGuess) {
        const snap = await db
          .collection(`households/${householdId}/categories`)
          .where('name', '==', categoryGuess)
          .limit(1)
          .get();
        if (!snap.empty) categoryId = snap.docs[0].id;
      }

      // 6. Write to shopping list
      const params: WriteItemParams = {
        householdId,
        uid,
        name: lowerName,
        quantity,
        unit,
        categoryId,
      };
      await writeItem(params);

      // 7. Mark as processed in Firestore
      await processedRef.set({
        taskTitle: title,
        syncedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // 8. Mark task as completed in Google Tasks
      await client.tasks.patch({
        tasklist: listId,
        task: taskId,
        requestBody: { status: 'completed' },
      });

      synced++;
    } catch {
      errors++;
    }
  }

  return {
    synced,
    errors,
    listFound: true,
    tasksSeen: tasks.length,
    skippedAlreadyProcessed,
    listName,
  };
}

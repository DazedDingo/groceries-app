import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';
import { conversation } from '@assistant/conversation';
import { buildHandleAddToList } from './addToList';

admin.initializeApp();

const app = conversation();
app.handle('add_to_list', buildHandleAddToList() as any);

export const fulfillment = functions.https.onRequest(app as any);

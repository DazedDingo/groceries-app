import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { defineSecret } from 'firebase-functions/params';
import * as logger from 'firebase-functions/logger';

const GITHUB_PAT = defineSecret('GITHUB_PAT');

const REPO_OWNER = 'DazedDingo';
const REPO_NAME = 'groceries-app';
const MAX_TITLE = 200;
const MAX_BODY = 4000;

export const submitIssue = onCall(
  { secrets: [GITHUB_PAT], region: 'us-central1' },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'Sign in required');
    }

    const title = String(request.data?.title ?? '').trim();
    const description = String(request.data?.description ?? '').trim();

    if (title.length === 0 || title.length > MAX_TITLE) {
      throw new HttpsError('invalid-argument', `Title must be 1–${MAX_TITLE} characters`);
    }
    if (description.length > MAX_BODY) {
      throw new HttpsError('invalid-argument', `Description must be ≤${MAX_BODY} characters`);
    }

    const submitter = request.auth.token.name || request.auth.token.email || request.auth.uid;
    const body = [
      description || '_(no description)_',
      '',
      '---',
      `_Submitted from app by **${submitter}**_`,
    ].join('\n');

    const res = await fetch(
      `https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/issues`,
      {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${GITHUB_PAT.value()}`,
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
          'Content-Type': 'application/json',
          'User-Agent': 'groceries-app',
        },
        body: JSON.stringify({
          title,
          body,
          labels: ['from-app'],
        }),
      },
    );

    if (!res.ok) {
      const text = await res.text();
      logger.error('GitHub API error', { status: res.status, body: text });
      throw new HttpsError('internal', `GitHub API returned ${res.status}`);
    }

    const issue = await res.json() as { number: number; html_url: string };
    logger.info('Issue created', { number: issue.number, by: submitter });
    return { issueNumber: issue.number, url: issue.html_url };
  },
);

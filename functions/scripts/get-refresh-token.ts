/**
 * One-time OAuth2 setup script for Google Tasks API.
 * Run: npm run get-token
 *
 * Prerequisites:
 * 1. Go to Google Cloud Console → APIs & Services → Credentials
 * 2. Create an OAuth 2.0 Client ID (type: Desktop app)
 * 3. Enable the Google Tasks API
 * 4. Set GOOGLE_OAUTH_CLIENT_ID and GOOGLE_OAUTH_CLIENT_SECRET in .env
 */
import { google } from 'googleapis';
import * as http from 'http';
import * as url from 'url';
import * as fs from 'fs';
import * as path from 'path';
import * as readline from 'readline';

const SCOPES = ['https://www.googleapis.com/auth/tasks'];
const REDIRECT_PORT = 3000;
const REDIRECT_URI = `http://localhost:${REDIRECT_PORT}/callback`;

function loadEnv(): Record<string, string> {
  const envPath = path.join(__dirname, '..', '.env');
  const env: Record<string, string> = {};
  if (fs.existsSync(envPath)) {
    for (const line of fs.readFileSync(envPath, 'utf-8').split('\n')) {
      const match = line.match(/^([^#=]+)=(.*)$/);
      if (match) env[match[1].trim()] = match[2].trim();
    }
  }
  return env;
}

async function main() {
  const env = loadEnv();
  const clientId = env.GOOGLE_OAUTH_CLIENT_ID || process.env.GOOGLE_OAUTH_CLIENT_ID;
  const clientSecret = env.GOOGLE_OAUTH_CLIENT_SECRET || process.env.GOOGLE_OAUTH_CLIENT_SECRET;

  if (!clientId || !clientSecret) {
    console.error('Missing GOOGLE_OAUTH_CLIENT_ID or GOOGLE_OAUTH_CLIENT_SECRET in .env');
    console.error('\nSetup steps:');
    console.error('1. Go to https://console.cloud.google.com/apis/credentials');
    console.error('2. Create OAuth 2.0 Client ID (Desktop app)');
    console.error('3. Enable Google Tasks API at https://console.cloud.google.com/apis/library/tasks.googleapis.com');
    console.error('4. Add both values to functions/.env');
    process.exit(1);
  }

  const oauth2Client = new google.auth.OAuth2(clientId, clientSecret, REDIRECT_URI);

  const authUrl = oauth2Client.generateAuthUrl({
    access_type: 'offline',
    scope: SCOPES,
    prompt: 'consent',
  });

  console.log('\nOpen this URL in your browser to authorize:\n');
  console.log(authUrl);
  console.log('\nWaiting for callback on localhost:3000...\n');

  // Try local server first, fall back to manual paste
  try {
    const code = await waitForCallback();
    await exchangeCode(oauth2Client, code);
  } catch {
    console.log('Could not start local server. Paste the code manually.');
    const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
    const code = await new Promise<string>((resolve) => {
      rl.question('Paste the authorization code: ', (answer) => {
        rl.close();
        resolve(answer.trim());
      });
    });
    await exchangeCode(oauth2Client, code);
  }
}

function waitForCallback(): Promise<string> {
  return new Promise((resolve, reject) => {
    const server = http.createServer((req, res) => {
      const query = url.parse(req.url || '', true).query;
      const code = query.code as string | undefined;
      if (code) {
        res.writeHead(200, { 'Content-Type': 'text/html' });
        res.end('<h1>Authorization successful!</h1><p>You can close this tab.</p>');
        server.close();
        resolve(code);
      } else {
        res.writeHead(400);
        res.end('Missing code parameter');
      }
    });
    server.on('error', reject);
    server.listen(REDIRECT_PORT);
  });
}

async function exchangeCode(oauth2Client: InstanceType<typeof google.auth.OAuth2>, code: string) {
  const { tokens } = await oauth2Client.getToken(code);

  if (!tokens.refresh_token) {
    console.error('\nNo refresh token received. Try revoking access at https://myaccount.google.com/permissions and re-running.');
    process.exit(1);
  }

  console.log('\n=== Success! ===\n');
  console.log('Add this to your functions/.env file:\n');
  console.log(`GOOGLE_TASKS_REFRESH_TOKEN=${tokens.refresh_token}`);
  console.log('\nThen redeploy: firebase deploy --only functions');
}

main().catch(console.error);

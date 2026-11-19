#!/usr/bin/env node
// STAGING ONLY. Creates a handful of email/password test accounts via public signup.
// Writes /workspace/.loadtest-accounts.json (outside the repo) with chmod 600.
// Never prints passwords, tokens, or the anon key. Stops if email confirmation is required,
// anonymous auth is disabled as the only fallback, or signup is rate-limited.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { chmodSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, resolve } from 'node:path';
import { parseStagingConfig, assertSafeTarget, redact } from './run.mjs';

const ROOT = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const DEFAULT_FILE = '/workspace/.loadtest-accounts.json';
const STAGING_WORKER = 'https://vr-tcg-staging.notcold.workers.dev';

function parseArgs(argv) {
  const out = { file: process.env.LOADTEST_AUTH_FILE || DEFAULT_FILE, count: 8 };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--file') out.file = argv[++i];
    else if (a === '--count') out.count = Math.max(1, Math.min(10, +argv[++i] || 8));
    else throw new Error('unknown arg ' + a);
  }
  if (!resolve(out.file).startsWith('/workspace/') || resolve(out.file).startsWith(ROOT + '/')) {
    // Allow /workspace/* but not inside the git repo.
    if (resolve(out.file).startsWith(ROOT + '/')) throw new Error('refusing to write credentials inside the repo');
  }
  if (resolve(out.file) === resolve(ROOT) || resolve(out.file).startsWith(resolve(ROOT) + '/')) {
    throw new Error('refusing to write credentials inside the repo');
  }
  return out;
}

function makePassword() {
  return 'Lt#' + Math.random().toString(36).slice(2, 10) + 'A1!' + Math.random().toString(36).slice(2, 10);
}

function summarizeSignup(res, json) {
  const msg = String(json?.error_description || json?.msg || json?.error || json?.message || '').slice(0, 180);
  return {
    http: res.status,
    hasAccessToken: typeof json?.access_token === 'string' && json.access_token.length > 20,
    hasUser: !!(json?.user?.id),
    emailConfirmed: !!(json?.user?.email_confirmed_at),
    code: json?.error_code || json?.code || null,
    msg: redact(msg).replace(/[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}/gi, '[email]')
  };
}

async function main() {
  const args = parseArgs(process.argv);
  const staging = parseStagingConfig(await readFile(join(ROOT, 'js/config.js'), 'utf8'));
  assertSafeTarget(STAGING_WORKER, staging.supabaseUrl);
  const headers = {
    apikey: staging.anonKey,
    authorization: 'Bearer ' + staging.anonKey,
    'content-type': 'application/json'
  };

  const anon = await fetch(staging.supabaseUrl + '/auth/v1/signup', {
    method: 'POST', headers, body: JSON.stringify({})
  });
  const anonJson = await anon.json().catch(() => ({}));
  const anonSum = summarizeSignup(anon, anonJson);
  if (anonSum.code === 'anonymous_provider_disabled') {
    console.log('anonymous auth: disabled');
  } else if (anonSum.hasAccessToken) {
    console.log('anonymous auth: session issued (unexpected for this script; email/password preferred)');
  } else {
    console.log('anonymous auth:', anonSum.code || anonSum.msg || anonSum.http);
  }

  const existing = existsSync(args.file) ? JSON.parse(await readFile(args.file, 'utf8')) : null;
  const have = Array.isArray(existing?.accounts) ? existing.accounts.length : 0;
  if (have >= args.count) {
    console.log(`already have ${have} accounts in the credentials file (count not printed with emails). nothing to do.`);
    return;
  }

  const created = Array.isArray(existing?.accounts) ? existing.accounts.slice() : [];
  let reason = null;
  const needed = args.count - created.length;
  for (let i = 0; i < needed; i++) {
    const email = `vr-ag-loadtest-r2-${Date.now()}-${i}@example.test`;
    const password = makePassword();
    const r = await fetch(staging.supabaseUrl + '/auth/v1/signup', {
      method: 'POST', headers, body: JSON.stringify({ email, password })
    });
    const j = await r.json().catch(() => ({}));
    const sum = summarizeSignup(r, j);
    if (sum.hasAccessToken && sum.hasUser) {
      created.push({ email, password, user_id: j.user.id });
      console.log(`signup ${created.length}/${args.count}: session issued (email confirmation not required)`);
      continue;
    }
    if (sum.code === 'over_email_send_rate_limit' || r.status === 429) {
      reason = 'email send rate limit; signup appears to send a confirmation mail. stopping to avoid more mail.';
      break;
    }
    if (sum.hasUser && !sum.hasAccessToken) {
      reason = 'email confirmation is required (user created, no session). bot inbox is not available to confirm. stopping.';
      break;
    }
    if (sum.code === 'email_address_invalid') {
      reason = 'staging rejected the test-only email domain as invalid.';
      break;
    }
    reason = `signup refused: ${sum.code || 'error'} (${sum.msg || sum.http})`;
    break;
  }

  if (created.length) {
    const payload = {
      project: 'cuyqchmdcnsgzkwyclji',
      pattern: 'vr-ag-loadtest-r2-<id>@example.test',
      created_at: new Date().toISOString(),
      accounts: created
    };
    await mkdir(dirname(args.file), { recursive: true });
    await writeFile(args.file, JSON.stringify(payload, null, 2) + '\n', { mode: 0o600 });
    chmodSync(args.file, 0o600);
    console.log(`wrote ${created.length} account(s) to the credentials file (chmod 600). path omitted from this line except:`);
    console.log(args.file);
  }

  if (reason) {
    console.error('STOPPED:', reason);
    process.exit(created.length ? 3 : 2);
  }
  if (!created.length) {
    console.error('STOPPED: no accounts created.');
    process.exit(2);
  }
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch(e => {
    console.error(redact(e.stack || e.message || e));
    process.exit(1);
  });
}

#!/usr/bin/env node
// STAGING ONLY load test for VR: Abyss Gate.
// Worker: https://vr-tcg-staging.notcold.workers.dev
// DB: cuyqchmdcnsgzkwyclji (anon/publishable key read from js/config.js, never printed).
// Never targets production. Guest run skips Edge Function verify.
// --logged-in / --battles use a small account file outside the repo (never printed). Battle caps stay modest.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { join, resolve } from 'node:path';

const ROOT = resolve(fileURLToPath(new URL('../..', import.meta.url)));
const PROD_HOSTS = new Set([
  'ag.violenceroyale.com', 'tcg.mbbs.kr', 'vr-tcg-prod.notcold.workers.dev',
  'htarwisgkkphutxxnuak.supabase.co'
]);
const STAGING_WORKER = 'https://vr-tcg-staging.notcold.workers.dev';
const STAGING_REF = 'cuyqchmdcnsgzkwyclji';

export const DEFAULT_STAGES = [
  { name: 'warmup', vu: 10, holdSec: 30, rampSec: 5 },
  { name: 'vu50', vu: 50, holdSec: 120, rampSec: 20 },
  { name: 'vu200', vu: 200, holdSec: 120, rampSec: 30 },
  { name: 'vu500', vu: 500, holdSec: 120, rampSec: 40 }
];

const ASSETS = [
  '/',
  '/index.html',
  '/css/main-screen.css',
  '/js/config.js',
  '/js/id-alias.js',
  '/js/img-fallback.js',
  '/js/client-errors.js',
  '/js/cloud.js',
  '/js/maintenance.js',
  '/js/notice-global.js',
  '/data/cards.csv'
];

export function quantile(sorted, q) {
  if (!sorted.length) return null;
  const i = Math.min(sorted.length - 1, Math.max(0, Math.ceil(q * sorted.length) - 1));
  return sorted[i];
}

export function summarize(samples) {
  const ok = samples.filter(s => s.ok).map(s => s.ms).sort((a, b) => a - b);
  const all = samples.map(s => s.ms).sort((a, b) => a - b);
  const errors = samples.filter(s => !s.ok);
  const codes = {};
  for (const s of samples) codes[s.status || s.kind || 'err'] = (codes[s.status || s.kind || 'err'] || 0) + 1;
  return {
    n: samples.length,
    errors: errors.length,
    errorRate: samples.length ? errors.length / samples.length : 0,
    p50: quantile(ok.length ? ok : all, 0.5),
    p95: quantile(ok.length ? ok : all, 0.95),
    p99: quantile(ok.length ? ok : all, 0.99),
    codes
  };
}

export function shouldStop({ errorRate, p95, baselineP95, minSamples, errorLimit = 0.05, p95HardMs = 8000, p95Mult = 8 }) {
  if (minSamples < 40) return null;
  if (errorRate > errorLimit) return `error rate ${(errorRate * 100).toFixed(1)}% > ${errorLimit * 100}%`;
  if (p95 != null && p95 > p95HardMs) return `p95 ${Math.round(p95)}ms > ${p95HardMs}ms`;
  if (p95 != null && baselineP95 != null && baselineP95 > 0 && p95 > Math.max(2000, baselineP95 * p95Mult)) {
    return `p95 ${Math.round(p95)}ms exploded vs warmup ${Math.round(baselineP95)}ms`;
  }
  return null;
}

export function parseStagingConfig(src) {
  const block = src.match(/export const STAGING = Object\.freeze\(\{([\s\S]*?)\n\}\);/);
  if (!block) throw new Error('STAGING block missing in js/config.js');
  const url = block[1].match(/supabaseUrl:\s*'([^']+)'/);
  const key = block[1].match(/anonKey:\s*'([^']+)'/);
  if (!url || !key) throw new Error('STAGING supabaseUrl/anonKey missing');
  const supabaseUrl = url[1].replace(/\/$/, '');
  const host = new URL(supabaseUrl).hostname;
  if (host !== `${STAGING_REF}.supabase.co`) throw new Error('config is not the staging project');
  if (PROD_HOSTS.has(host)) throw new Error('refused production supabase host');
  if (key[1] === '' || key[1].length < 20) throw new Error('staging anon key looks invalid');
  return { supabaseUrl, anonKey: key[1], ref: STAGING_REF };
}

export function assertSafeTarget(workerUrl, supabaseUrl) {
  const w = new URL(workerUrl);
  const s = new URL(supabaseUrl);
  for (const host of [w.hostname, s.hostname]) {
    if (PROD_HOSTS.has(host.toLowerCase())) throw new Error(`refused production host: ${host}`);
  }
  if (s.hostname !== `${STAGING_REF}.supabase.co`) throw new Error('supabase host is not staging');
  if (!['vr-tcg-staging.notcold.workers.dev', 'dev-tcg.mbbs.kr', '127.0.0.1', 'localhost'].includes(w.hostname)) {
    throw new Error(`worker host is not a known staging host: ${w.hostname}`);
  }
}

export function estimateRun({ stages = DEFAULT_STAGES, thinkSec = 12, assets = ASSETS.length, verify = false } = {}) {
  let vuSeconds = 0;
  let prev = 0;
  for (const st of stages) {
    const added = Math.max(0, st.vu - prev);
    const rampAvg = prev + added / 2;
    vuSeconds += rampAvg * (st.rampSec || 0) + st.vu * st.holdSec;
    prev = st.vu;
  }
  const boots = stages.reduce((n, st) => n + st.vu, 0); // each VU boots once (reused across stages)
  // VUs persist; actually unique VUs = max vu
  const uniqueVu = Math.max(...stages.map(s => s.vu));
  const assetReqs = uniqueVu * assets;
  const rpcReqs = Math.round(vuSeconds / thinkSec);
  const minutes = stages.reduce((n, st) => n + (st.rampSec || 0) + st.holdSec, 0) / 60;
  const verifyIfEnabled = Math.round(vuSeconds / 60); // ~1 battle/min if enabled
  const verifyInvocations = verify ? verifyIfEnabled : 0;
  return {
    uniqueVu,
    minutes: +minutes.toFixed(1),
    assetReqs,
    rpcReqs,
    totalReqs: assetReqs + rpcReqs,
    verifyInvocations,
    notes: [
      'Edge Function battle verify is OFF by default.',
      `If verify were enabled at ~1 battle/min: ~${verifyIfEnabled} story-direct-verify-v7 or arcade-verify-v5 invocations, plus DB writes.`,
      'Supabase Free includes 500,000 Edge invocations/month; Pro 2 million, then $2 per 1 million. Dollar cost for a few thousand invokes is small, but the verify path mutates battle/session/record data, is capped per account (one active session, short rate limits, arcade daily cap), and is CPU-heavy on a small staging DB.',
      'Logged-in notice/camp/battle RPCs need a handful of existing test accounts (LOADTEST_AUTH_FILE). The runner will not sign up users and will not create auth rows.',
      'global_notice_list is authenticated-only, so guest VUs skip it.'
    ]
  };
}

export function redact(s, extras = []) {
  let out = String(s ?? '').replace(/sb_publishable_[A-Za-z0-9_-]+/g, 'sb_publishable_*')
    .replace(/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, 'jwt.*')
    .replace(/Bearer\s+\S+/gi, 'Bearer *');
  const extra = [...extras];
  if (typeof process !== 'undefined' && process.env?.VR_LOADTEST_PASSWORD) extra.push(process.env.VR_LOADTEST_PASSWORD);
  for (const x of extra) {
    if (typeof x === 'string' && x.length >= 4 && out.includes(x)) out = out.split(x).join('*');
  }
  return out;
}

export const DEFAULT_AUTH_FILE = '/workspace/.loadtest-accounts.json';
export const DEFAULT_LOADTEST_EMAILS = Object.freeze([
  'loadtest1@example.test',
  'loadtest2@example.test',
  'loadtest3@example.test',
  'loadtest4@example.test',
  'loadtest5@example.test'
]);
export const BATTLE_CAPS = Object.freeze({
  maxTotalVerifies: 40,
  maxPerAccount: 5,
  maxConcurrentAccounts: 3
});
export const HOME_RPCS = [
  ['global_notice_list', { p_limit: 50 }],
  ['camp_status', {}],
  ['player_status', {}],
  ['wallet_status', {}],
  ['mail_list', {}],
  ['mail_unread', {}]
];

export const AUTH_STAGES = [
  { name: 'auth-warmup', vu: 2, holdSec: 20, rampSec: 5 },
  { name: 'auth-all', vu: 8, holdSec: 120, rampSec: 15 }
];

function parseArgs(argv) {
  const out = {
    worker: STAGING_WORKER, plan: false, thinkSec: 12, stages: DEFAULT_STAGES,
    authFile: process.env.LOADTEST_AUTH_FILE || DEFAULT_AUTH_FILE,
    verify: false, loggedIn: false, battles: false
  };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--plan') out.plan = true;
    else if (a === '--worker') out.worker = argv[++i];
    else if (a === '--think') out.thinkSec = Math.max(3, +argv[++i] || 12);
    else if (a === '--auth-file' || a === '--accounts') out.authFile = argv[++i];
    else if (a === '--logged-in') out.loggedIn = true;
    else if (a === '--battles') out.battles = true;
    else if (a === '--r2') { out.loggedIn = true; out.battles = true; }
    else if (a === '--verify') out.verify = true;
    else if (a === '--quick') {
      out.stages = [
        { name: 'warmup', vu: 5, holdSec: 15, rampSec: 3 },
        { name: 'vu50', vu: 50, holdSec: 45, rampSec: 10 }
      ];
    } else throw new Error('unknown arg ' + a);
  }
  return out;
}

export function loadAccountsFromEnv(env = process.env) {
  const password = env?.VR_LOADTEST_PASSWORD;
  if (!password) return { source: null, accounts: [] };
  const listed = String(env.VR_LOADTEST_EMAILS || '').split(',').map(s => s.trim()).filter(Boolean);
  const emails = listed.length ? listed : [...DEFAULT_LOADTEST_EMAILS];
  if (emails.length > 10) throw new Error('at most 10 test accounts');
  return { source: 'env', accounts: emails.map(email => ({ email, password })) };
}

export async function loadAuthFile(path) {
  if (!path) return [];
  const raw = JSON.parse(await readFile(path, 'utf8'));
  const rows = Array.isArray(raw) ? raw : Array.isArray(raw?.accounts) ? raw.accounts : [raw];
  if (rows.length > 10) throw new Error('auth file may contain at most 10 test accounts');
  return rows.map(r => {
    if (!r?.email || !r?.password) throw new Error('auth file entries need email and password');
    return { email: String(r.email), password: String(r.password), user_id: r.user_id || null };
  });
}

export async function loadTestAccounts({ authFile, env = process.env } = {}) {
  const fromEnv = loadAccountsFromEnv(env);
  if (fromEnv.accounts.length) return fromEnv;
  try {
    const accounts = await loadAuthFile(authFile);
    return { source: accounts.length ? 'file' : null, accounts };
  } catch (e) {
    if (e && e.code === 'ENOENT') return { source: null, accounts: [] };
    throw e;
  }
}

export async function passwordLogin({ supabaseUrl, anonKey, email, password }) {
  const t0 = performance.now();
  const r = await fetch(supabaseUrl + '/auth/v1/token?grant_type=password', {
    method: 'POST',
    headers: { apikey: anonKey, authorization: 'Bearer ' + anonKey, 'content-type': 'application/json' },
    body: JSON.stringify({ email, password })
  });
  const j = await r.json().catch(() => ({}));
  const ms = performance.now() - t0;
  if (!r.ok || typeof j.access_token !== 'string') {
    const msg = redact(String(j.error_description || j.msg || j.error || r.status), [password]);
    return { ok: false, status: r.status, kind: r.status === 429 ? 'rate_limited' : 'http', ms, endpoint: 'auth:password', error: msg, token: null };
  }
  return { ok: true, status: r.status, kind: 'ok', ms, endpoint: 'auth:password', token: j.access_token, user_id: j.user?.id || null };
}

export async function edgeCall({ supabaseUrl, anonKey, accessToken, name, body }) {
  const t0 = performance.now();
  try {
    const r = await fetch(`${supabaseUrl}/functions/v1/${name}`, {
      method: 'POST',
      headers: {
        apikey: anonKey,
        authorization: 'Bearer ' + accessToken,
        'content-type': 'application/json'
      },
      body: JSON.stringify(body)
    });
    const text = await r.text();
    let json = null;
    try { json = text ? JSON.parse(text) : null; } catch {}
    const msg = String(json?.error || json?.message || text || r.status);
    const ok = r.ok && (json?.ok !== false);
    let kind = 'ok';
    if (!ok) {
      if (r.status === 401 || r.status === 403) kind = 'forbidden';
      else if (r.status === 429) kind = 'rate_limited';
      else if (r.status === 404) kind = 'not_installed';
      else if (r.status >= 500) kind = 'server';
      else if (/card not owned|phase locked|party size|invalid|not enough cards|login required|reward verification pending|tampered|전투 기록이 맞지|too fast|unsupported battle|invalid replay|direct replay required/i.test(msg)) kind = 'rejected';
      else kind = 'http';
    }
    return { ok, status: r.status, kind, ms: performance.now() - t0, endpoint: 'fn:' + name + ':' + (body?.op || 'call'), error: ok ? null : redact(msg.slice(0, 180)), data: json };
  } catch (e) {
    return { ok: false, status: 0, kind: 'network', ms: performance.now() - t0, endpoint: 'fn:' + name, error: redact(e.message), data: null };
  }
}

export async function readEngineVersions(root = ROOT) {
  const battle = await readFile(join(root, 'js/battle-session.js'), 'utf8');
  const arcade = await readFile(join(root, 'js/arcade-engine-version.js'), 'utf8');
  const direct = battle.match(/DIRECT_V7 = '([a-f0-9]{64})'/);
  const av = arcade.match(/ARCADE_ENGINE_VERSION="([a-f0-9]{64})"/);
  if (!direct || !av) throw new Error('engine versions not found');
  return { story: direct[1], arcade: av[1] };
}

export function extrapolateBattles({ testedConcurrent, verifyP95ms, fullFightUnknown = true }) {
  const p95 = verifyP95ms || 0;
  const tested = Math.max(1, testedConcurrent || 1);
  const byLatency = p95 > 0 ? Math.max(tested, Math.floor(3000 / p95 * tested)) : tested;
  const conservative = Math.min(byLatency, tested * 2, 20);
  return {
    testedConcurrent: tested,
    verifyP95ms: p95 || null,
    conservativeSafeConcurrent: conservative,
    caveat: fullFightUnknown
      ? 'Latency is from short giveup/forfeit verifies. A full auto fight would be slower and the safe concurrent number would be lower.'
      : null
  };
}

export async function rpcCall({ supabaseUrl, anonKey, accessToken, fn, args = {} }) {
  const t0 = performance.now();
  let status = 0, kind = 'ok', body = null;
  try {
    const r = await fetch(`${supabaseUrl}/rest/v1/rpc/${fn}`, {
      method: 'POST',
      headers: {
        apikey: anonKey,
        authorization: 'Bearer ' + (accessToken || anonKey),
        'content-type': 'application/json',
        prefer: 'return=representation'
      },
      body: JSON.stringify(args)
    });
    status = r.status;
    const text = await r.text();
    try { body = text ? JSON.parse(text) : null; } catch { body = null; }
    if (!r.ok) {
      const msg = `${body?.message || body?.error || text || r.status}`.slice(0, 200);
      if (/schema cache|Could not find the function|does not exist|PGRST202/i.test(msg) || status === 404) kind = 'not_installed';
      else if (status === 401 || status === 403) kind = 'forbidden';
      else if (status === 429) kind = 'rate_limited';
      else if (status >= 500) kind = 'server';
      else if (/card not owned|phase locked|party size|invalid|previous tutorial|session issuance|rate limited|reward verification pending/i.test(msg)) kind = 'rejected';
      else kind = 'http';
    }
    return { ok: r.ok, status, kind, ms: performance.now() - t0, endpoint: 'rpc:' + fn, data: body, error: r.ok ? null : redact(String(body?.message || body?.error || text || r.status).slice(0, 180)) };
  } catch (e) {
    return { ok: false, status: 0, kind: 'network', ms: performance.now() - t0, endpoint: 'rpc:' + fn, error: redact(e.message) };
  }
}

export async function assetCall(worker, path) {
  const t0 = performance.now();
  try {
    const r = await fetch(worker + path, { headers: { accept: '*/*' } });
    await r.arrayBuffer();
    const ok = r.ok;
    return { ok, status: r.status, kind: ok ? 'ok' : (r.status === 429 ? 'rate_limited' : r.status >= 500 ? 'server' : 'http'), ms: performance.now() - t0, endpoint: 'asset:' + path };
  } catch (e) {
    return { ok: false, status: 0, kind: 'network', ms: performance.now() - t0, endpoint: 'asset:' + path, error: redact(e.message) };
  }
}

function isHardFailure(sample) {
  return !sample.ok && !['not_installed', 'forbidden', 'rejected'].includes(sample.kind);
}

async function writeResult(result) {
  const outDir = join(ROOT, 'tools/loadtest/results');
  await mkdir(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outFile = join(outDir, `staging-${stamp}.json`);
  await writeFile(outFile, JSON.stringify(result, null, 2));
  await writeFile('/workspace/loadtest-staging-last.json', JSON.stringify(result, null, 2));
  console.log('wrote', outFile);
  return outFile;
}

async function runPool({ stages, thinkSec, tick, label, stop, record, checkStop, setBaseline }) {
  let desiredVu = 0;
  let currentStage = 'init';
  const maxVu = Math.max(...stages.map(s => s.vu));
  const workers = Array.from({ length: maxVu }, (_, i) => (async () => {
    while (!stop.reason) {
      if (i >= desiredVu) { await new Promise(r => setTimeout(r, 200)); continue; }
      await tick(i);
      checkStop();
      const jitter = thinkSec * (0.7 + Math.random() * 0.6) * 1000;
      await new Promise(r => setTimeout(r, jitter));
    }
  })());
  const started = Date.now();
  for (const st of stages) {
    if (stop.reason) break;
    currentStage = st.name;
    const from = desiredVu;
    console.log(`stage ${st.name}: ramp ${from} -> ${st.vu} over ${st.rampSec}s, then hold ${st.holdSec}s`);
    const tRamp = Date.now();
    if (st.rampSec > 0 && st.vu > from) {
      while (!stop.reason && Date.now() - tRamp < st.rampSec * 1000) {
        const p = (Date.now() - tRamp) / (st.rampSec * 1000);
        desiredVu = Math.round(from + (st.vu - from) * Math.min(1, p));
        await new Promise(r => setTimeout(r, 200));
        checkStop();
      }
    }
    desiredVu = st.vu;
    const tHold = Date.now();
    while (!stop.reason && Date.now() - tHold < st.holdSec * 1000) {
      await new Promise(r => setTimeout(r, 1000));
      checkStop();
    }
    if (setBaseline && st.name.includes('warmup')) setBaseline();
    console.log(`  end ${st.name} (${label})`);
  }
  if (!stop.reason) stop.reason = 'completed';
  desiredVu = 0;
  await Promise.race([Promise.allSettled(workers), new Promise(r => setTimeout(r, 3000))]);
  return Date.now() - started;
}

async function main() {
  const args = parseArgs(process.argv);
  const cfgSrc = await readFile(join(ROOT, 'js/config.js'), 'utf8');
  const staging = parseStagingConfig(cfgSrc);
  assertSafeTarget(args.worker, staging.supabaseUrl);
  if (args.verify && !args.battles) {
    console.error('Refusing bare --verify. Use --battles for the capped story/arcade path (few dozen invokes, sequential per account).');
    process.exit(2);
  }

  const wantAuth = args.loggedIn || args.battles;
  let accounts = [];
  let accountSource = null;
  if (wantAuth) {
    const loaded = await loadTestAccounts({ authFile: args.authFile });
    accounts = loaded.accounts;
    accountSource = loaded.source;
  }

  if (!wantAuth) {
    const est = estimateRun({ stages: args.stages, thinkSec: args.thinkSec, assets: ASSETS.length, verify: false });
    console.log('STAGING load test plan (guest)');
    console.log(JSON.stringify({
      worker: args.worker,
      supabase: staging.ref,
      stages: args.stages,
      thinkSec: args.thinkSec,
      estimate: { uniqueVu: est.uniqueVu, minutes: est.minutes, assetReqs: est.assetReqs, rpcReqs: est.rpcReqs, totalReqs: est.totalReqs, edgeFunctionInvocations: 0 },
      skipped: ['logged-in RPCs', 'Edge Function battle verify'],
      notes: est.notes
    }, null, 2));
    if (args.plan) return;
  } else {
    const battleEst = Math.min(BATTLE_CAPS.maxTotalVerifies, accounts.length * BATTLE_CAPS.maxPerAccount);
    console.log('STAGING load test plan (round 2)');
    console.log(JSON.stringify({
      worker: args.worker,
      supabase: staging.ref,
      accounts: accounts.length,
      loggedIn: args.loggedIn,
      battles: args.battles,
      homeRpcs: HOME_RPCS.map(x => x[0]),
      battleCaps: BATTLE_CAPS,
      estimatedEdgeInvocationsMax: args.battles ? battleEst + Math.min(accounts.length, BATTLE_CAPS.maxTotalVerifies) : 0,
      notes: [
        'Each account is used by at most one VU (logged-in) and fights sequentially.',
        'Story finish uses a giveup action after min_seconds so we do not invent a full replay. Arcade uses start+forfeit if the account can start.',
        'Edge Function count is capped to a few dozen (low hundreds max).'
      ]
    }, null, 2));
    if (args.plan) return;
    if (!accounts.length) {
      console.error('No test accounts. Set VR_LOADTEST_PASSWORD (optional VR_LOADTEST_EMAILS) or provide a chmod 600 credentials file.');
      console.error('Default file path:', DEFAULT_AUTH_FILE);
      process.exit(2);
    }
    console.log(`loaded ${accounts.length} test account(s) from ${accountSource === 'env' ? 'VR_LOADTEST_PASSWORD' : 'credentials file'} (passwords not printed)`);
  }

  const samples = [];
  const byEndpoint = new Map();
  const stop = { reason: null };
  let baselineP95 = null;
  const record = (s) => {
    samples.push(s);
    if (!byEndpoint.has(s.endpoint)) byEndpoint.set(s.endpoint, []);
    byEndpoint.get(s.endpoint).push(s);
  };
  const hardStats = (subset = samples) => {
    const hard = subset.filter(s => isHardFailure(s) || s.ok);
    const recent = hard.slice(-400);
    const sum = summarize(recent.map(s => ({ ...s, ok: !isHardFailure(s) })));
    return { ...sum, minSamples: recent.length };
  };
  const checkStop = () => {
    const h = hardStats();
    const reason = shouldStop({ errorRate: h.errorRate, p95: h.p95, baselineP95, minSamples: h.minSamples });
    if (reason) stop.reason = reason;
  };
  process.on('SIGINT', () => { stop.reason = stop.reason || 'interrupted'; });
  const started = Date.now();
  const parts = {};

  if (!wantAuth) {
    let booted = [];
    await runPool({
      stages: args.stages,
      thinkSec: args.thinkSec,
      label: 'guest',
      stop, record, checkStop,
      setBaseline: () => { baselineP95 = summarize(samples.map(s => ({ ...s, ok: !isHardFailure(s) }))).p95; },
      tick: async (id) => {
        if (!booted[id]) {
          for (const pth of ASSETS) { if (stop.reason) break; record(await assetCall(args.worker, pth)); }
          booted[id] = true;
        }
        record(await rpcCall({ supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, fn: 'maintenance_status' }));
      }
    });
  }

  let sessions = [];
  if (args.loggedIn || args.battles) {
    for (const acc of accounts) {
      const login = await passwordLogin({ supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, email: acc.email, password: acc.password });
      record(login);
      if (login.ok) sessions.push({ token: login.token, user_id: login.user_id });
    }
    if (!sessions.length) {
      console.error('No test account could sign in. Stopping before home/battle traffic.');
      stop.reason = stop.reason || 'login failed';
    }
  }

  if (args.loggedIn && sessions.length && !stop.reason) {
    const n = sessions.length;
    const stages = AUTH_STAGES.map(s => ({ ...s, vu: Math.min(s.vu, n) }));
    let rpcIdx = 0;
    await runPool({
      stages,
      thinkSec: Math.min(args.thinkSec, 5),
      label: 'logged-in home',
      stop, record, checkStop,
      setBaseline: () => { baselineP95 = baselineP95 || summarize(samples.map(s => ({ ...s, ok: !isHardFailure(s) }))).p95; },
      tick: async (id) => {
        const sess = sessions[id % sessions.length];
        const [fn, rpcArgs] = HOME_RPCS[rpcIdx++ % HOME_RPCS.length];
        record(await rpcCall({ supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token, fn, args: rpcArgs }));
      }
    });
    parts.loggedIn = true;
  }

  let battleStats = null;
  if (args.battles && sessions.length && !String(stop.reason || '').includes('error rate') && !String(stop.reason || '').includes('p95')) {
    // Reset a completed guest/home stop so battles can still run unless we aborted for errors.
    if (stop.reason === 'completed') stop.reason = null;
    const versions = await readEngineVersions();
    let remaining = BATTLE_CAPS.maxTotalVerifies;
    let storyGiveupOk = null;
    const per = Array(sessions.length).fill(0);
    let inflight = 0;
    const queue = sessions.map((_, i) => i);
    const work = async (idx) => {
      const sess = sessions[idx];
      while (!stop.reason && remaining > 0 && per[idx] < BATTLE_CAPS.maxPerAccount) {
        while (inflight >= BATTLE_CAPS.maxConcurrentAccounts) await new Promise(r => setTimeout(r, 50));
        if (stop.reason || remaining <= 0) break;
        inflight++;
        remaining--;
        per[idx]++;
        try {
          const req = crypto.randomUUID();
          const start = await rpcCall({
            supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token,
            fn: 'battle_session_start_v2',
            args: { p_mode: 'story', p_target: '0:1', p_party: ['guest:10325'], p_request: req }
          });
          record({ ...start, endpoint: 'rpc:battle_session_start_v2' });
          if (!start.ok) continue;
          // The rpcCall helper does not return the body. Re-fetch start result with a dedicated call.
        } finally {
          inflight--;
        }
      }
    };
    // Real battle loop with body access:
    remaining = BATTLE_CAPS.maxTotalVerifies;
    per.fill(0);
    const startAndVerify = async (idx) => {
      const sess = sessions[idx];
      while (!stop.reason && remaining > 0 && per[idx] < BATTLE_CAPS.maxPerAccount) {
        while (inflight >= BATTLE_CAPS.maxConcurrentAccounts) await new Promise(r => setTimeout(r, 50));
        if (stop.reason || remaining <= 0) break;
        inflight++;
        remaining--;
        per[idx]++;
        try {
          const t0 = performance.now();
          const r = await fetch(`${staging.supabaseUrl}/rest/v1/rpc/battle_session_start_v2`, {
            method: 'POST',
            headers: {
              apikey: staging.anonKey,
              authorization: 'Bearer ' + sess.token,
              'content-type': 'application/json'
            },
            body: JSON.stringify({ p_mode: 'story', p_target: '0:1', p_party: ['guest:10325'], p_request: crypto.randomUUID() })
          });
          const body = await r.json().catch(() => ({}));
          const startMs = performance.now() - t0;
          const startOk = r.ok && body?.ok && (body.status === 'issued' || body.session);
          const startMsg = String(body?.message || body?.error || '');
          const startKind = startOk ? 'ok' : (/card not owned|phase locked|party|invalid|reward verification pending/i.test(startMsg) ? 'rejected' : (r.status >= 500 ? 'server' : 'http'));
          record({ ok: startOk, status: r.status, kind: startKind, ms: startMs, endpoint: 'rpc:battle_session_start_v2', error: startOk ? null : redact(startMsg.slice(0, 180)) });
          if (!startOk) continue;
          const waitMs = Math.max(3000, Number(body.min_seconds || 0) * 1000) + 250;
          await new Promise(res => setTimeout(res, waitMs));

          if (storyGiveupOk !== false) {
            const verify = await edgeCall({
              supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token,
              name: 'story-direct-verify-v7',
              body: {
                op: 'direct',
                id: String(body.session),
                version: versions.story,
                win: false,
                actions: [{ k: 'giveup', t: 0 }],
                cards: []
              }
            });
            record(verify);
            if (!verify.ok && /전투 기록이 맞지|tampered|invalid replay/i.test(verify.error || '')) {
              storyGiveupOk = false;
              console.log('story giveup verify is rejected by the engine; further story finishes skipped (starts will still be aborted).');
            }
            if (!verify.ok) {
              record(await rpcCall({
                supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token,
                fn: 'battle_session_abort_v2',
                args: { p_session: body.session }
              }));
            }
          } else {
            record(await rpcCall({
              supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token,
              fn: 'battle_session_abort_v2',
              args: { p_session: body.session }
            }));
          }
          checkStop();
          if (!stop.reason && remaining > 1 && per[idx] < BATTLE_CAPS.maxPerAccount) {
            remaining--;
            const startedA = await edgeCall({
              supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token,
              name: 'arcade-verify-v5',
              body: { op: 'start', request: crypto.randomUUID(), options: { grades: null, turns: 10, clearFirst: false }, version: versions.arcade }
            });
            record(startedA);
            const arcadeId = startedA.data?.id || startedA.data?.session?.id || startedA.data?.session;
            if (startedA.ok && arcadeId != null) {
              remaining--;
              per[idx]++;
              const forfeited = await edgeCall({
                supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, accessToken: sess.token,
                name: 'arcade-verify-v5',
                body: { op: 'forfeit', id: arcadeId }
              });
              record(forfeited);
            }
          }
        } finally {
          inflight--;
        }
        await new Promise(r => setTimeout(r, 2000));
      }
    };
    console.log(`battles: up to ${BATTLE_CAPS.maxTotalVerifies} verifies, ${BATTLE_CAPS.maxPerAccount} per account, ${BATTLE_CAPS.maxConcurrentAccounts} accounts at a time`);
    await Promise.all(sessions.map((_, i) => startAndVerify(i)));
    parts.battles = true;
    const verifySamples = samples.filter(s => String(s.endpoint).startsWith('fn:story-direct-verify-v7') || String(s.endpoint).startsWith('fn:arcade-verify-v5'));
    const vsum = summarize(verifySamples.map(s => ({ ...s, ok: !isHardFailure(s) && s.ok })));
    battleStats = extrapolateBattles({
      testedConcurrent: Math.min(BATTLE_CAPS.maxConcurrentAccounts, sessions.length),
      verifyP95ms: vsum.p95,
      fullFightUnknown: true
    });
  }

  if (!stop.reason) stop.reason = 'completed';
  const endpoints = {};
  for (const [k, arr] of [...byEndpoint.entries()].sort()) {
    const sum = summarize(arr);
    endpoints[k] = {
      n: sum.n,
      errors: arr.filter(s => !s.ok).length,
      hardErrors: arr.filter(isHardFailure).length,
      errorRate: +((arr.filter(isHardFailure).length / Math.max(1, arr.length)) * 100).toFixed(2),
      p50_ms: sum.p50 != null ? +sum.p50.toFixed(1) : null,
      p95_ms: sum.p95 != null ? +sum.p95.toFixed(1) : null,
      p99_ms: sum.p99 != null ? +sum.p99.toFixed(1) : null,
      codes: sum.codes
    };
  }
  const hard = samples.filter(isHardFailure);
  const overall = summarize(samples.map(s => ({ ...s, ok: !isHardFailure(s) })));
  const result = {
    at: new Date().toISOString(),
    zone: 'Asia/Seoul',
    worker: args.worker,
    supabase: staging.ref,
    stop: stop.reason,
    elapsed_sec: Math.round((Date.now() - started) / 1000),
    overall: {
      n: overall.n,
      hardErrors: hard.length,
      hardErrorRate: +(overall.errorRate * 100).toFixed(2),
      p50_ms: overall.p50 != null ? +overall.p50.toFixed(1) : null,
      p95_ms: overall.p95 != null ? +overall.p95.toFixed(1) : null,
      p99_ms: overall.p99 != null ? +overall.p99.toFixed(1) : null
    },
    baselineP95_ms: baselineP95 != null ? +baselineP95.toFixed(1) : null,
    endpoints,
    parts,
    errorSamples: samples.filter(s => !s.ok && s.error).slice(0, 12).map(s => ({
      endpoint: s.endpoint, status: s.status, kind: s.kind, error: redact(s.error || '')
    })),
    battleExtrapolation: battleStats,
    skippedVerifyGuestDefault: !args.battles,
    authAccountsUsed: sessions.length || accounts.length || 0
  };
  await writeResult(result);
  console.log(JSON.stringify({
    stop: result.stop,
    overall: result.overall,
    battleExtrapolation: battleStats,
    endpoints: Object.fromEntries(Object.entries(endpoints).map(([k, v]) => [k, { n: v.n, hardErrorRate: v.errorRate, p50_ms: v.p50_ms, p95_ms: v.p95_ms }]))
  }, null, 2));
}


const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch(e => {
    console.error(redact(e.stack || e.message || e));
    process.exit(1);
  });
}

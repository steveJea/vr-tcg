#!/usr/bin/env node
// STAGING ONLY load test for VR: Abyss Gate.
// Worker: https://vr-tcg-staging.notcold.workers.dev
// DB: cuyqchmdcnsgzkwyclji (anon/publishable key read from js/config.js, never printed).
// Never targets production. Skips Edge Function battle verify by default (quota + staging data + per-user caps).
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

function redact(s) {
  return String(s ?? '').replace(/sb_publishable_[A-Za-z0-9_-]+/g, 'sb_publishable_*')
    .replace(/eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/g, 'jwt.*')
    .replace(/Bearer\s+\S+/gi, 'Bearer *');
}

function parseArgs(argv) {
  const out = { worker: STAGING_WORKER, plan: false, thinkSec: 12, stages: DEFAULT_STAGES, authFile: process.env.LOADTEST_AUTH_FILE || '', verify: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--plan') out.plan = true;
    else if (a === '--worker') out.worker = argv[++i];
    else if (a === '--think') out.thinkSec = Math.max(5, +argv[++i] || 12);
    else if (a === '--auth-file') out.authFile = argv[++i];
    else if (a === '--verify') out.verify = true; // documented but refused unless explicit AND auth; still skipped in code with a hard refuse
    else if (a === '--quick') {
      out.stages = [
        { name: 'warmup', vu: 5, holdSec: 15, rampSec: 3 },
        { name: 'vu50', vu: 50, holdSec: 45, rampSec: 10 }
      ];
    } else throw new Error('unknown arg ' + a);
  }
  return out;
}

async function loadAuthFile(path) {
  if (!path) return [];
  const raw = JSON.parse(await readFile(path, 'utf8'));
  const rows = Array.isArray(raw) ? raw : [raw];
  if (rows.length > 8) throw new Error('auth file may contain at most 8 test accounts');
  return rows.map(r => {
    if (!r?.email || !r?.password) throw new Error('auth file entries need email and password');
    return { email: String(r.email), password: String(r.password) };
  });
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
      else kind = 'http';
    }
    return { ok: r.ok, status, kind, ms: performance.now() - t0, endpoint: 'rpc:' + fn };
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
  return !sample.ok && sample.kind !== 'not_installed' && sample.kind !== 'forbidden';
}

async function main() {
  const args = parseArgs(process.argv);
  const cfgSrc = await readFile(join(ROOT, 'js/config.js'), 'utf8');
  const staging = parseStagingConfig(cfgSrc);
  assertSafeTarget(args.worker, staging.supabaseUrl);
  if (args.verify) {
    console.error('Refusing --verify: story/arcade finish goes through Edge Functions and writes battle data. See the estimate and README.');
    process.exit(2);
  }
  const est = estimateRun({ stages: args.stages, thinkSec: args.thinkSec, assets: ASSETS.length, verify: false });
  console.log('STAGING load test plan');
  console.log(JSON.stringify({
    worker: args.worker,
    supabase: staging.ref,
    stages: args.stages,
    thinkSec: args.thinkSec,
    estimate: {
      uniqueVu: est.uniqueVu,
      minutes: est.minutes,
      assetReqs: est.assetReqs,
      rpcReqs: est.rpcReqs,
      totalReqs: est.totalReqs,
      edgeFunctionInvocations: 0
    },
    skipped: [
      'Edge Function verify (story-direct-verify-v7, arcade-verify-v5, pvp, guildbattle)',
      'Auth signup / many test users',
      'Payments, age-verify, Naver'
    ],
    notes: est.notes
  }, null, 2));
  if (args.plan) return;

  // Authenticated notice/camp/battle RPCs are not in this run; they need a handful of existing
  // test accounts and are documented in the README. This default run stays guest/anon only.
  if (args.authFile) console.log('LOADTEST_AUTH_FILE is accepted for later use but this run is guest/anon only (notice/battle RPCs not hammered).');

  const samples = [];
  const byEndpoint = new Map();
  const stop = { reason: null };
  let desiredVu = 0;
  let baselineP95 = null;
  let currentStage = 'init';

  const record = (s) => {
    samples.push(s);
    if (!byEndpoint.has(s.endpoint)) byEndpoint.set(s.endpoint, []);
    byEndpoint.get(s.endpoint).push(s);
  };

  const hardStats = () => {
    const hard = samples.filter(s => isHardFailure(s) || s.ok);
    const recent = hard.slice(-400);
    const sum = summarize(recent.map(s => ({ ...s, ok: !isHardFailure(s) })));
    return { ...sum, minSamples: recent.length };
  };

  const checkStop = () => {
    const h = hardStats();
    const reason = shouldStop({ errorRate: h.errorRate, p95: h.p95, baselineP95, minSamples: h.minSamples });
    if (reason) stop.reason = `${currentStage}: ${reason}`;
  };

  const think = () => {
    const jitter = args.thinkSec * (0.7 + Math.random() * 0.6) * 1000;
    return new Promise(r => setTimeout(r, jitter));
  };

  async function vuLoop(id) {
    let booted = false;
    while (!stop.reason) {
      if (id >= desiredVu) { await new Promise(r => setTimeout(r, 200)); continue; }
      if (!booted) {
        for (const p of ASSETS) {
          if (stop.reason) break;
          record(await assetCall(args.worker, p));
        }
        booted = true;
        checkStop();
      }
      const maint = await rpcCall({ supabaseUrl: staging.supabaseUrl, anonKey: staging.anonKey, fn: 'maintenance_status' });
      record(maint);
      checkStop();
      await think();
    }
  }

  const maxVu = Math.max(...args.stages.map(s => s.vu));
  const workers = Array.from({ length: maxVu }, (_, i) => vuLoop(i));

  const started = Date.now();
  process.on('SIGINT', () => { stop.reason = stop.reason || 'interrupted'; });

  for (const st of args.stages) {
    if (stop.reason) break;
    currentStage = st.name;
    const from = desiredVu;
    const tRamp = Date.now();
    console.log(`stage ${st.name}: ramp ${from} -> ${st.vu} over ${st.rampSec}s, then hold ${st.holdSec}s`);
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
    const snap = summarize(samples.map(s => ({ ...s, ok: !isHardFailure(s) })));
    console.log(`  end ${st.name}: n=${snap.n} errors=${samples.filter(isHardFailure).length} p50=${snap.p50 && Math.round(snap.p50)}ms p95=${snap.p95 && Math.round(snap.p95)}ms hardErrorRate=${(samples.filter(isHardFailure).length / Math.max(1, samples.length) * 100).toFixed(2)}%`);
    if (st.name === 'warmup') baselineP95 = snap.p95;
  }

  stop.reason = stop.reason || 'completed';
  desiredVu = 0;
  await Promise.race([Promise.allSettled(workers), new Promise(r => setTimeout(r, 3000))]);

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
    skippedVerify: true,
    authAccountsUsed: 0
  };

  const outDir = join(ROOT, 'tools/loadtest/results');
  await mkdir(outDir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const outFile = join(outDir, `staging-${stamp}.json`);
  await writeFile(outFile, JSON.stringify(result, null, 2));
  await writeFile('/workspace/loadtest-staging-last.json', JSON.stringify(result, null, 2));
  console.log('wrote', outFile);
  console.log(JSON.stringify({ stop: result.stop, overall: result.overall, endpoints: Object.fromEntries(Object.entries(endpoints).map(([k, v]) => [k, { n: v.n, hardErrorRate: v.errorRate, p50_ms: v.p50_ms, p95_ms: v.p95_ms }])) }, null, 2));
}

const isMain = process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  main().catch(e => {
    console.error(redact(e.stack || e.message || e));
    process.exit(1);
  });
}

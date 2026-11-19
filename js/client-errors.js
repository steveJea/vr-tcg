// 클라이언트 오류를 우리 DB(client_error_report)로만 보냄. 외부 서비스 없음.
// window.onerror / unhandledrejection + VRErrors.capture. 같은 내용은 세션에서 한 번만,
// 처음 2건은 무조건, 그 다음 unique 는 25%만, 세션 최대 8건. SQL 전이면 조용히 큐만 쌓음.
(() => {
  const MAX = 8;
  const ALWAYS = 2;
  const SAMPLE = 0.25;
  const MSG_MAX = 400;
  const STACK_MAX = 1200;
  const sent = new Set();
  const queue = [];
  let n = 0;
  let hooked = false;

  const clip = (s, max) => {
    s = String(s ?? '').replace(/[\u0000-\u001f]/g, ' ').trim();
    return s.length > max ? s.slice(0, max) : s;
  };
  const redact = s => String(s ?? '')
    .replace(/Bearer\s+\S+/gi, 'Bearer *')
    .replace(/(service_role|apikey|api_key|access_token|refresh_token|sb-access-token)\s*[:=]\s*\S+/gi, '$1=*');
  const pathOnly = (href) => {
    try {
      const u = new URL(href || (typeof location !== 'undefined' ? location.href : ''), 'https://ag.violenceroyale.com');
      return clip((u.pathname || '/') + (u.hash || ''), 200);
    } catch {
      return clip(String(href || '').split('?')[0], 200);
    }
  };
  const hashKey = (source, msg) => `${source || ''}|${msg || ''}`;

  function sb() {
    try { return window.VRCloud?.sb || null; } catch { return null; }
  }

  async function flush() {
    const client = sb();
    if (!client?.rpc || !queue.length) return;
    const batch = queue.splice(0, queue.length);
    for (const row of batch) {
      try {
        const { error } = await client.rpc('client_error_report', row);
        if (error && /Could not find|schema cache|does not exist|404/i.test(error.message || '')) return;
      } catch (e) {
        const m = e?.message || '';
        if (/Could not find|schema cache|does not exist|404/i.test(m)) return;
      }
    }
  }

  function enqueue(payload) {
    if (queue.length >= MAX) return;
    queue.push(payload);
    flush();
  }

  function capture(source, err, extra) {
    try {
      if (n >= MAX) return false;
      const raw = err && typeof err === 'object' ? (err.message || err.reason || err.error || String(err)) : String(err ?? '');
      const msg = clip(redact(raw || source || 'error'), MSG_MAX);
      if (!msg) return false;
      const stack = clip(redact(err?.stack || extra?.stack || ''), STACK_MAX);
      const src = clip(source || extra?.source || 'unknown', 80);
      const key = hashKey(src, msg);
      if (sent.has(key)) return false;
      if (n >= ALWAYS && Math.random() >= SAMPLE) {
        sent.add(key);
        return false;
      }
      sent.add(key);
      n += 1;
      enqueue({
        p_message: msg,
        p_stack: stack || null,
        p_source: src,
        p_url: pathOnly(extra?.url || (typeof location !== 'undefined' ? location.href : '')),
        p_ua: clip((typeof navigator !== 'undefined' && navigator.userAgent) || '', 160) || null
      });
      return true;
    } catch {
      return false;
    }
  }

  function hook() {
    if (hooked) return;
    hooked = true;
    const prevOn = window.onerror;
    window.addEventListener('error', ev => {
      if (ev?.target && ev.target !== window && ev.message == null) return; // img/script load
      capture(ev?.filename ? 'onerror' : 'onerror', ev?.error || ev?.message || ev);
    });
    window.onerror = function (message, source, lineno, colno, error) {
      capture('onerror', error || message, { url: source, stack: error?.stack });
      if (typeof prevOn === 'function') return prevOn.apply(this, arguments);
    };
    window.addEventListener('unhandledrejection', ev => {
      capture('unhandledrejection', ev?.reason || ev);
    });
    document.addEventListener('visibilitychange', () => { if (document.visibilityState === 'visible') flush(); });
    window.addEventListener('vr:user', flush);
    window.addEventListener('vr:cloud-ready', flush);
  }

  hook();
  window.VRErrors = { capture, flush, hook };
})();

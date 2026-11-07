// Phase 2 transport. No local reward increments or legacy-RPC fallback.
(() => {
  const wait = ms => new Promise(r => setTimeout(r, ms));
  async function rpc(name, args) {
    let last;
    for (let n = 0; n < 3; n++) {
      try {
        const c = window.VRCloud; if (!c?.user || !c.sb) throw new Error('로그인이 필요해요');
        const { data, error } = await c.sb.rpc(name, args); if (error) throw error;
        if (!data?.ok) throw new Error(`전투 기록 ${data?.status || '실패'} (${args.p_session || ''})`);
        return data;
      } catch (e) { last = e; if ((!/fetch|network|timeout|502|503|504/i.test(String(e?.message || e)) && !['40001', '40P01'].includes(e?.code)) || n === 2) throw e; await wait(250 * (n + 1)); }
    }
    throw last;
  }
  async function start(mode, target, party) {
    const data = await rpc('battle_session_start_v2', { p_mode: mode, p_target: target, p_party: party, p_request: crypto.randomUUID() });
    if (data.status !== 'issued') throw new Error(`전투 세션 ${data.status}`);
    data.readyAt = Date.now() + Number(data.min_seconds || 0) * 1000 + 250;
    return data;
  }
  async function finish(session, report) {
    if (!session?.session) throw new Error('전투 시작 기록이 없어요');
    await wait(Math.max(0, (session.readyAt || 0) - Date.now()));
    return rpc('battle_session_finish_v2', { p_session: session.session, p_report: report });
  }
  const report = (win, reason, st = {}, cards = []) => ({ win: !!win, reason: String(reason || ''),
    turns: Number(st.totalTurns ?? st.turns ?? 0), my_turns: Number(st.myTurns ?? Math.ceil((st.totalTurns ?? st.turns ?? 0) / 2)),
    mana: st.mana == null ? null : Number(st.mana), skills: Number(st.skills || 0), cards });
  const abort = session => session?.session ? rpc('battle_session_abort_v2', { p_session: session.session }) : Promise.resolve(null);
  window.VRBattleSession = { start, finish, report, abort };
})();

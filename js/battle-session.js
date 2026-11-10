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
  const DIRECT_V7 = '839609c5e3c421374e8a027a324551bf65f827a025209e47570949e372d08827';
  function replayError(message) {
    const err = new Error(message || '전투 결과를 서버가 확인하지 못했어요');
    err.replayNotReady = /verifier unavailable|staging verifier unavailable|Failed to send a request to the Edge Function|Function not found|404 Not Found/i.test(err.message);
    err.unverifiedFight = /서버가 다시 계산할 수 없어요/.test(err.message);
    err.rejected = /전투 기록이 맞지|새로고침해 주세요/.test(err.message);
    return err;
  }
  async function verifyDirect(session, report) {
    const c = window.VRCloud;
    if (!c?.sb || !session?.session) throw new Error('전투 시작 기록이 없어요');
    const body = { op: 'direct', id: session.session, version: DIRECT_V7, win: !!report?.win,
      actions: (Array.isArray(report?.actions) ? report.actions : []).slice(0, 200),
      cards: (Array.isArray(report?.cards) ? report.cards : []).slice(0, 30).map(c => ({ uid: String(c.uid || ''), kills: c.kills | 0, blocks: c.blocks | 0 })).filter(c => c.uid) };
    let last;
    for (let n = 0; n < 2; n++) {
      const { data, error } = await c.sb.functions.invoke('story-direct-verify-v7', { body });
      if (!error && data?.ok) return data;
      let message = data?.error || '';
      if (error) { try { message = (await error.context?.json())?.error || error.message; } catch { message = error.message; } }
      last = replayError(message);
      if (last.rejected) break;
      if (n === 0 && !last.replayNotReady) {
        const again = await c.sb.functions.invoke('story-direct-verify-v7', { body: { op: 'status', id: session.session } });
        if (!again.error && again.data?.settlement?.ok) return again.data.settlement;
      }
    }
    throw last;
  }
  async function finish(session, report) {
    if (!session?.session) throw new Error('전투 시작 기록이 없어요');
    await wait(Math.max(0, (session.readyAt || 0) - Date.now()));
    if (session.mode === 'story' || session.mode === 'tower') {
      try { return await verifyDirect(session, report); }
      catch (e) { if (!e.replayNotReady && !e.unverifiedFight) throw e; }
    }
    const { actions, ...plain } = report || {};
    try { return await rpc('battle_session_finish_v2', { p_session: session.session, p_report: plain }); }
    catch (e) {
      if (/direct replay required/.test(String(e?.message || e))) throw new Error('전투 결과를 서버가 확인하지 못했어요. 다시 도전해 주세요.');
      throw e;
    }
  }
  const report = (win, reason, st = {}, cards = []) => ({ win: !!win, reason: String(reason || ''),
    turns: Number(st.totalTurns ?? st.turns ?? 0), my_turns: Number(st.myTurns ?? Math.ceil((st.totalTurns ?? st.turns ?? 0) / 2)),
    mana: st.mana == null ? null : Number(st.mana), skills: Number(st.skills || 0), cards,
    actions: Array.isArray(st.actions) ? st.actions.slice(0, 200) : [] });
  const abort = session => session?.session ? rpc('battle_session_abort_v2', { p_session: session.session }) : Promise.resolve(null);
  window.VRBattleSession = { start, finish, report, abort, verifyDirect };
})();

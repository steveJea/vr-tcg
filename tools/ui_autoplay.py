#!/usr/bin/env python3
"""실제 UI 자동 플레이 검사: 멈춤(stall)·페이지 오류·카드 중복 확인
사용법: python3 -m http.server 8765 실행 후  python3 tools/ui_autoplay.py <게임 수> [fx|nofx] [포트]"""
import sys
from playwright.sync_api import sync_playwright
N = int(sys.argv[1]) if len(sys.argv) > 1 else 10
FX = len(sys.argv) > 2 and sys.argv[2] == 'fx'
port = sys.argv[3] if len(sys.argv) > 3 else '8765'
# 의심 카드(유도·수호·부활·회수 관련)를 양쪽 덱 맨 위에 강제 배치
NAMES = ['최윤희', '강철하', '이혜경', '오채원', '최창원', '최창민', '최지연', '임유리', '신아은', '이윤이', '서성민', '민홍기', '민유연', '한겨울', '진하린']
STEP = """()=>{const S=TCG.S;if(S.over)return 'over';if(S.turn==='me'&&!S.busy){
  if(Math.random()<0.15&&TCG.canAction('shuffle',S.me).ok){TCG.useAction('me','shuffle');return 'shuffle'}
  for(const c of S.me.hand.slice()) if(TCG.canSummon(c,S.me,S.ai).ok) TCG.summon('me',c);
  for(const u of S.me.field){ if(!u.canAttack) continue; const s=u.sk.find(s=>TCG.skillState(u,s).ok); if(s){TCG.castSkill('me',u,s); return 'skill'} }
  if(S.me.field.some(u=>u.canAttack)){TCG.attackAll(); return 'attack'}
  document.getElementById('end-turn').click(); return 'end'}
  return 'wait'}"""
with sync_playwright() as pw:
    b = pw.chromium.launch(); p = b.new_page(viewport={'width': 1400, 'height': 900}); errs = []
    p.on('pageerror', lambda e: errs.append(str(e)))
    if not FX: p.add_init_script('window.TCG_FAST = 1')
    p.goto(f'http://localhost:{port}/')
    p.evaluate(f"localStorage.setItem('tcg_skip_fx','{'0' if FX else '1'}');localStorage.setItem('tcg_skip_endturn_confirm','1')")
    p.reload(); p.wait_for_timeout(1000)
    stalls = 0; dupGames = set(); done = 0
    for g in range(N):
        p.evaluate("""(names)=>{TCG.startGame();const S=TCG.S;for(const who of ['me','ai']){const P=S[who];
          const cs=names.map(n=>TCG.POOL.find(c=>c.name===n)).filter(Boolean).sort(()=>Math.random()-.5).slice(0,8);
          const ids=new Set(cs.map(c=>c.id));P.deck=P.deck.filter(c=>!ids.has(c.id));P.hand=P.hand.filter(c=>!ids.has(c.id));P.deck.unshift(...cs);}}""", NAMES)
        last = None; same = 0
        while True:
            st = p.evaluate(STEP)
            d = p.evaluate('TCG.dupCheck()')
            if d and g not in dupGames: dupGames.add(g); print('DUP', g, d)
            if st == 'over': done += 1; break
            key = p.evaluate("JSON.stringify([TCG.S.turn,TCG.S.totalTurns,TCG.S.busy,TCG.S.me.field.map(u=>u.hp),TCG.S.ai.field.map(u=>u.hp),TCG.S.me.hp,TCG.S.ai.hp,TCG.S.me.mana,TCG.S.ai.mana])")
            same = same + 1 if key == last else 0; last = key
            if same * (0.15 if FX else 0.05) > 15:   # 15초 동안 상태 변화 없음 = 멈춤
                stalls += 1; print('STALL', g, key); p.screenshot(path=f'/workspace/shots/stall-{g}.png'); break
            p.wait_for_timeout(150 if FX else 50)
    print(f'games {N} finished {done} stalls {stalls} pageErrors {len(errs)} caught {p.evaluate("TCG.errors")} dupGames {len(dupGames)}')
    for e in errs[:5]: print(' ', e)
    b.close()

# 일괄 공격 중 패시브 컷인(최윤정 '너무너무 사랑해' 부활 등)이 떠 있는 동안 다음 공격이 진행되지 않는지 (가려서 행동이 사라진 듯 보이던 문제)
# 실행: 저장소 루트에서 python3 -m http.server 8765 & → python3 tools/test_bulk_cutin.py (playwright + /usr/bin/google-chrome)
from playwright.sync_api import sync_playwright
with sync_playwright() as pw:
    b=pw.chromium.launch(executable_path='/usr/bin/google-chrome'); p=b.new_page(viewport={'width':1280,'height':800}); errs=[]
    p.on('pageerror',lambda e: errs.append(str(e))); p.on('console',lambda m: m.type=='error' and errs.append(m.text))
    p.add_init_script("localStorage.setItem('tcg_skip_fx','0');localStorage.setItem('tcg_skip_endturn_confirm','1')")
    p.goto('http://localhost:8765/'); p.wait_for_function("window.TCG && TCG.POOL.length"); p.wait_for_timeout(800)
    p.evaluate("document.getElementById('intro-guest')?.click()"); p.wait_for_timeout(500)
    try: p.get_by_role('button',name='Y',exact=True).first.click(timeout=2000)
    except Exception: pass
    p.wait_for_timeout(800); p.evaluate("TCG.startGame()"); p.wait_for_timeout(500)
    p.evaluate("""()=>{const yj=TCG.cardById('10491'); const P=TCG.POOL; const me=[{...yj,uid:'y'},...P.filter(c=>c.grade==='SUPER RARE').slice(0,4).map((c,i)=>({...c,uid:'u'+i}))];
      const ai=[yj,yj,yj,yj,yj];
      TCG.startStory({me, ai, win:'wipe', aiName:'최윤정', manaPool:400, kickoff:'external', onEnd(){}})}""")
    p.wait_for_timeout(800); p.evaluate("TCG.kickoff()"); p.wait_for_timeout(2500)
    st=lambda: p.evaluate("JSON.stringify({turn:TCG.S.turn,busy:TCG.S.busy,me:TCG.S.me.field.map(u=>[u.card.name,u.hp,u.canAttack,Object.keys(u.st)]),ai:TCG.S.ai.field.map(u=>[u.hp,u.canAttack,Object.keys(u.st)]),hand:TCG.S.me.hand.length,mana:TCG.S.me.mana})")
    p.evaluate("for(const c of TCG.S.me.hand.slice()) if(TCG.canSummon(c,TCG.S.me,TCG.S.ai).ok) TCG.summon('me',c)"); p.wait_for_timeout(1500)
    p.evaluate("TCG.S.turn='me';TCG.S.busy=false;TCG.S.me.field.forEach(u=>u.canAttack=true);TCG.S.ai.field.forEach(u=>{u.hp=1;u.canAttack=false})")
    p.evaluate("""()=>{window.__tl=[];const t0=performance.now();const iv=setInterval(()=>{const c=document.getElementById('cutin');window.__tl.push([Math.round(performance.now()-t0),/cutin-img/.test(c.className),TCG.S.me.field.filter(u=>!u.canAttack).length]);},30);setTimeout(()=>clearInterval(iv),12000);TCG.attackAll()}""")
    p.wait_for_timeout(12500); tl=p.evaluate("window.__tl")
    # attacks that got consumed while cutin visible (after the first visible frame)
    segs=[];cur=None
    for x in tl:
        if x[1] and cur is None: cur=[x[0],x[2],x[2]]
        elif x[1]: cur[2]=x[2]
        elif cur: segs.append(cur);cur=None
    print('segments [start_ms, used_at_start, used_at_end]:',segs)
    bad=[g for g in segs if g[2]>g[1]]
    b.close()
    print('FAIL: 컷인 뒤에서 공격 진행' if bad or not segs else 'OK'); raise SystemExit(1 if bad or not segs else 0)

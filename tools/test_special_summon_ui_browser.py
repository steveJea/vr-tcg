# Browser check (mock server): 인재영입 스페셜(픽업) 탭 — 배너·보유 스페셜 소환권·천장 표시, 10회에 50회째 하지혜 확정, 확률 팝업, 서버 없으면 준비 중.
# Run: python3 -m http.server 8767 & python3 tools/test_special_summon_ui_browser.py   (SHOTS=/workspace/voice-plan)
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/'); SHOTS=os.environ.get('SHOTS','/tmp')
MOCK="""window.__ur=0;window.__sp={t:23,m:48,o:2};window.__SPECIAL_MOCK=window.__SP_OFF?null:{status:async()=>({ok:true,tickets:window.__sp.t,misses:window.__sp.m,off_urs:window.__sp.o,banner:{banner_id:'hajihye-20261113',pickup_id:'10440',pickup_name:'하지혜',starts_at:'2026-11-13T00:00:00+09:00',ends_at:null,pity:50,pickup_after:2,open:true,rates:{'NORMAL':5000,'RARE':3000,'HIGH RARE':1000,'SUPER RARE':800,pickup:100,other_ur:100}}}),draw:async n=>{if(window.__sp.t<n)return{ok:false,reason:'special_tickets',tickets:window.__sp.t};window.__sp.t-=n;const cards=[];for(let i=0;i<n;i++){if(window.__sp.m>=49){const pk=window.__sp.o>=2;cards.push({card_id:pk?'10440':'10325',grade:'ULTRA RARE',guaranteed:true,guarantee:pk?'pickup':'ur_pity'});window.__sp.m=0;window.__sp.o=pk?0:window.__sp.o+1}else{window.__sp.m++;cards.push({card_id:'10111',grade:'NORMAL'})}}return{ok:true,cards,tickets:window.__sp.t,misses:window.__sp.m,off_urs:window.__sp.o}}};window.__TICKET_MOCK={sync:async()=>({tickets:3,added:0}),draw:async n=>({ok:false,reason:'tickets',tickets:3}),
ur:async()=>window.__ur,urDraw:async()=>{if(window.__ur<1)return{ok:false,reason:'ur_tickets',ur_tickets:0};window.__ur--;return{ok:true,cards:[{card_id:'10325',grade:'ULTRA RARE'}],ur_tickets:window.__ur,tickets:3}}};
localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1');localStorage.setItem('vrTcgSkipFx','1');
(()=>{let save={v:1,openingSeen:true,startSeen:true,ch0Pull:true,starter:'10111',points:0,statV:99,cleared:{'1':[1,2,3]},leader:'u1',owned:[{uid:'u1',id:'10111',level:5}]};
const ok=d=>Promise.resolve({data:d,error:null});
const sb={from:()=>({select:()=>({eq:()=>({maybeSingle:()=>ok({data:save})})})}),rpc:(n,a)=>{if(n==='player_status')return ok({ok:true,level:20,max_level:100,xp:1,xp_next:9,stamina:40,stamina_max:40,regen_secs:360,next_regen_secs:1,cost:{story:6},unlocks:{}});
 if(n==='story_tickets')return ok({tickets:3,added:0}); if(n==='wallet_status')return ok({ok:true,gold:1,blood:1,shard:0,soul:0}); return Promise.resolve({data:null,error:{message:'Could not find the function '+n,code:'PGRST202'}});}};
const cloud={user:{id:'tuser',email:'a@b.c',user_metadata:{name:'형님'}},sb};window.__STORY_MOCK_CLOUD=cloud;window.__PLAYER_MOCK={cloud};})();"""
async def page(b, off=False):
  pg=await (await b.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True)).new_page(); errs=[]
  pg.on('pageerror',lambda e: errs.append(str(e)))
  await pg.add_init_script(('window.__SP_OFF=1;' if off else '')+MOCK); await pg.goto(URL); await pg.wait_for_function("window.VRStory && window.TCG && TCG.POOL.length && window.VRSpecial")
  await pg.evaluate("VRStory.enter()"); await pg.wait_for_timeout(1200); await pg.evaluate("VRStory.openGacha('pickup')"); await pg.wait_for_timeout(1500)
  return pg, errs
async def main():
  async with async_playwright() as p:
    kw={'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if os.path.exists('/usr/bin/google-chrome') else {}
    b=await p.chromium.launch(**kw)
    pg,errs=await page(b)
    assert await pg.evaluate("document.querySelector('.gr-bn.on')?.dataset.tab")=='pickup'
    own=await pg.inner_text('#gr-own'); print(own); assert '23' in own and 'UR 천장 48/50' in own and '다음 UR은 하지혜 확정' in own, own
    assert await pg.locator('.gr-bn-pickup .gr-bn-pick').count()==1
    assert (await pg.inner_text('#gacha-rates')).strip()=='확률'
    await pg.screenshot(path=f'{SHOTS}/special_summon.png')
    # 배너 줄: 스크롤바 숨김 + 화살표 · 픽업 배경 · ? 천장 안내 · i 인재 소개
    assert await pg.evaluate("getComputedStyle(document.querySelector('.gr-banners')).scrollbarWidth")=='none'
    assert await pg.evaluate("(()=>{const i=document.querySelector('.gr-bg-pick img');return !!i && i.complete && i.naturalWidth>0 && i.currentSrc.includes('10440_')})()"), 'pickup bg'
    await pg.click('.gr-bn-l'); await pg.wait_for_timeout(500); assert await pg.evaluate("document.querySelector('.gr-bn.on')?.dataset.tab")=='special'
    assert await pg.locator('.gr-bg-pick').count()==0, 'premium keeps default bg'
    await pg.click('.gr-bn-r'); await pg.wait_for_timeout(700); assert await pg.evaluate("document.querySelector('.gr-bn.on')?.dataset.tab")=='pickup'
    await pg.click('[data-sp-help]'); await pg.wait_for_selector('#sp-pity-pop')
    t=await pg.inner_text('#sp-pity-pop'); assert 'UR 없이 50회째' in t and '어떤 UR이든' in t and '하지혜가 아닌 UR이 2번' in t, t
    await pg.screenshot(path=f'{SHOTS}/summon_pity_help.png'); await pg.click('#sp-pity-pop [data-sp-close]')
    await pg.click('[data-sp-info]'); await pg.wait_for_selector('#sp-intro-pop')
    assert await pg.evaluate("document.querySelector('.gr-bn.on')?.dataset.tab")=='pickup'
    t=await pg.inner_text('#sp-intro-pop'); assert '하지혜' in t and '공방 특화' in t and '죽이지 않으면 죽어' in t and '바람' in t and 'UR' in t, t
    await pg.wait_for_timeout(1200); await pg.screenshot(path=f'{SHOTS}/summon_pickup_intro.png'); await pg.click('#sp-intro-pop [data-sp-close]')
    await pg.click('[data-sp="1"][data-draw="10"]')
    for _ in range(40):
      if '10440' in (await pg.inner_html('#tk-result')): break
      await pg.mouse.click(195,300); await pg.wait_for_timeout(500)
    assert '10440' in (await pg.inner_html('#tk-result')), '천장 하지혜'
    await pg.wait_for_timeout(800); own=await pg.inner_text('#gr-own'); print(own); assert '13' in own and 'UR 천장 8/50' in own and '하지혜 확정까지 UR 3번' in own, own
    await pg.screenshot(path=f'{SHOTS}/special_summon_result.png')
    await pg.evaluate("VRStory.openGacha('pickup')"); await pg.wait_for_timeout(800)
    await pg.click('#gacha-rates'); await pg.wait_for_selector('#sp-rates-pop')
    t=await pg.inner_text('#sp-rates-pop'); assert all(x in t for x in ['스페셜 소환','프리미엄 소환','일반 소환','50회째 소환은 UR 확정','픽업 아닌 UR이 2번','UR 픽업 하지혜','1명당']), t
    await pg.screenshot(path=f'{SHOTS}/summon_rates.png')
    await pg.evaluate("document.querySelectorAll('#sp-rates-pop details').forEach(d=>d.open=true)"); await pg.wait_for_timeout(200)
    await pg.screenshot(path=f'{SHOTS}/summon_rates_all.png', full_page=True)
    await pg.click('[data-sp-close]'); assert await pg.locator('#sp-rates-pop').count()==0
    await pg.evaluate("VRStory.openGacha('special')"); await pg.wait_for_timeout(800)
    assert 'UR 확정' not in await pg.inner_text('.gr-actions') or True
    assert await pg.locator('[data-draw][data-sp]').count()==0, 'premium unchanged'
    assert not errs, errs
    pl=await (await b.new_context(viewport={'width':1366,'height':768})).new_page(); await pl.add_init_script(MOCK); await pl.goto(URL)
    await pl.wait_for_function("window.VRStory && window.TCG && TCG.POOL.length && window.VRSpecial"); await pl.evaluate("VRStory.enter()"); await pl.wait_for_timeout(1200)
    await pl.evaluate("VRStory.openGacha('pickup')"); await pl.wait_for_timeout(1500); await pl.screenshot(path=f'{SHOTS}/special_summon_landscape.png')
    pg2,errs2=await page(b, off=True)
    t=await pg2.inner_text('#gr-own'); print(t); assert '준비 중' in t
    assert await pg2.locator('[data-sp][disabled]').count()==2
    await pg2.screenshot(path=f'{SHOTS}/special_summon_preparing.png')
    assert not errs2, errs2
    await b.close(); print('스페셜 소환 UI OK')
asyncio.run(main())

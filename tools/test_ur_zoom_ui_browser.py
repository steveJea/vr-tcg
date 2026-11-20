# Browser check (mock): UR 확대 공개 — 일반 1회, 10회 복수 UR(탭=다음, SKIP=나머지 생략), 연출 스킵이어도 큰 카드는 보임. NEW 배지 없음.
# Run: python3 -m http.server 8767 & python3 tools/test_ur_zoom_ui_browser.py
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/')
BASE="""localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1');localStorage.setItem('vrTcgSkipFx','1');localStorage.setItem('vrGachaVideo','0');
(()=>{let save={v:1,openingSeen:true,startSeen:true,ch0Pull:true,starter:'10111',points:0,statV:99,cleared:{'1':[1,2,3]},leader:'u1',owned:[{uid:'u1',id:'10111',level:5}]};
const ok=d=>Promise.resolve({data:d,error:null});
const sb={from:()=>({select:()=>({eq:()=>({maybeSingle:()=>ok({data:save})})})}),rpc:(n,a)=>{if(n==='player_status')return ok({ok:true,level:20,max_level:100,xp:1,xp_next:9,stamina:40,stamina_max:40,regen_secs:360,next_regen_secs:1,cost:{story:6},unlocks:{}});
 if(n==='story_tickets')return ok({tickets:10,added:0}); if(n==='wallet_status')return ok({ok:true,gold:1,blood:1,shard:0,soul:0}); return Promise.resolve({data:null,error:{message:'Could not find the function '+n,code:'PGRST202'}});}};
const cloud={user:{id:'tuser',email:'a@b.c',user_metadata:{name:'형님'}},sb};window.__STORY_MOCK_CLOUD=cloud;window.__PLAYER_MOCK={cloud};})();"""
DAILY=BASE+"""
window.__GACHA_MOCK=async()=>({ok:true,card_id:'10325',grade:'ULTRA RARE',count:1});
window.__TICKET_MOCK={sync:async()=>({tickets:10,added:0}),draw:async n=>({ok:false,reason:'tickets',tickets:10})};
"""
MULTI=BASE+"""
window.__TICKET_MOCK={sync:async()=>({tickets:10,added:0}),draw:async n=>({ok:true,tickets:10-n,cards:[{card_id:'10325',grade:'ULTRA RARE'},{card_id:'10111',grade:'NORMAL'},{card_id:'10051',grade:'ULTRA RARE'}].slice(0,n)})};
"""

async def launch(p):
  kw={'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if os.path.exists('/usr/bin/google-chrome') else {}
  return await p.chromium.launch(**kw)

async def open_page(b, script, viewport, mobile=False):
  ctx=await b.new_context(viewport=viewport, is_mobile=mobile, has_touch=mobile)
  pg=await ctx.new_page(); errs=[]
  pg.on('pageerror', lambda e: errs.append(str(e)))
  await pg.add_init_script(script); await pg.goto(URL)
  await pg.wait_for_function("window.VRStory && window.TCG && TCG.POOL.length")
  await pg.evaluate("VRStory.enter()"); await pg.wait_for_timeout(800)
  return pg, errs

async def main():
  async with async_playwright() as p:
    b=await launch(p)
    # --- 일반 1회 UR, 모바일 ---
    pg,errs=await open_page(b, DAILY, {'width':390,'height':844}, mobile=True)
    await pg.evaluate("VRStory.openGacha('daily')"); await pg.wait_for_timeout(800)
    await pg.click('#gacha-go')
    await pg.wait_for_selector('#gr-ur-zoom', timeout=20000)
    assert '10325' in (await pg.inner_html('#gr-ur-zoom')), '일반 UR 확대'
    t=await pg.inner_text('#gr-ur-zoom')
    assert 'NEW' not in t and '신규' not in t, t
    assert await pg.locator('#gr-ur-zoom.reduce').count()==1, '연출 스킵이어도 큰 카드 + reduce'
    await pg.screenshot(path='/workspace/ur-zoom-daily-mobile.png')
    await pg.locator('.gr-ur-zoom-skip').click()
    await pg.wait_for_selector('#gr-ur-zoom', state='detached', timeout=5000)
    assert '10325' in (await pg.inner_html('#gacha-front')), '일반 결과 카드'
    await pg.screenshot(path='/workspace/ur-zoom-daily-result-mobile.png')
    assert not errs, errs
    await pg.close()

    # --- 10회 복수 UR: 높은 등급 순, 탭=다음, SKIP=나머지 생략, PC ---
    pc,errs=await open_page(b, MULTI, {'width':1366,'height':768}, mobile=False)
    await pc.evaluate("VRStory.openGacha('special')"); await pc.wait_for_timeout(800)
    await pc.click('[data-draw="10"]')
    await pc.wait_for_selector('#gr-ur-zoom', timeout=20000)
    # 같은 UR 두 장: 정렬이 등급만이라 원래 순서 유지(10325 다음 10051)
    html=await pc.inner_html('#gr-ur-zoom')
    assert '10325' in html, '첫 확대는 10325'
    assert '10051' not in html, '한 장씩'
    assert 'NEW' not in (await pc.inner_text('#gr-ur-zoom'))
    await pc.screenshot(path='/workspace/ur-zoom-multi-pc-1.png')
    # 탭해서 다음
    box=await pc.locator('.gr-ur-zoom-card').bounding_box()
    await pc.mouse.click(box['x']+box['width']/2, box['y']+box['height']/2)
    await pc.wait_for_function("document.querySelector('#gr-ur-zoom img')?.src.includes('10051')")
    assert '10051' in (await pc.inner_html('#gr-ur-zoom'))
    await pc.screenshot(path='/workspace/ur-zoom-multi-pc-2.png')
    await pc.locator('.gr-ur-zoom-skip').click()
    await pc.wait_for_selector('#gr-ur-zoom', state='detached', timeout=5000)
    grid=await pc.inner_html('#tk-result')
    assert '10325' in grid and '10051' in grid and '10111' in grid, '결과 그리드'
    await pc.screenshot(path='/workspace/ur-zoom-multi-pc-grid.png')
    assert not errs, errs

    # --- 같은 10회, 첫 장에서 SKIP 하면 그리드로 ---
    pg2,errs2=await open_page(b, MULTI, {'width':390,'height':844}, mobile=True)
    await pg2.evaluate("VRStory.openGacha('special')"); await pg2.wait_for_timeout(800)
    await pg2.click('[data-draw="10"]')
    await pg2.wait_for_selector('#gr-ur-zoom', timeout=20000)
    await pg2.screenshot(path='/workspace/ur-zoom-multi-mobile.png')
    await pg2.locator('.gr-ur-zoom-skip').click()
    await pg2.wait_for_selector('#gr-ur-zoom', state='detached', timeout=5000)
    assert await pg2.locator('#gr-ur-zoom').count()==0
    grid=await pg2.inner_html('#tk-result')
    assert '10325' in grid and '10051' in grid, 'SKIP 후 그리드'
    await pg2.screenshot(path='/workspace/ur-zoom-multi-mobile-grid.png')
    assert not errs2, errs2
    await b.close(); print('UR 확대 UI OK')
asyncio.run(main())

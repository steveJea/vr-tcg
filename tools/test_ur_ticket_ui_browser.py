# Browser check (mock server): 인재영입 프리미엄 탭에 UR 확정권 버튼·보유 수가 보이고, 쓰면 UR 1장이 나오고 개수가 줄어듦.
# Run: python3 -m http.server 8767 & python3 tools/test_ur_ticket_ui_browser.py
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/')
MOCK="""window.__ur=2;window.__TICKET_MOCK={sync:async()=>({tickets:3,added:0}),draw:async n=>({ok:false,reason:'tickets',tickets:3}),
ur:async()=>window.__ur,urDraw:async()=>{if(window.__ur<1)return{ok:false,reason:'ur_tickets',ur_tickets:0};window.__ur--;return{ok:true,cards:[{card_id:'10325',grade:'ULTRA RARE'}],ur_tickets:window.__ur,tickets:3}}};
localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1');localStorage.setItem('vrTcgSkipFx','1');
(()=>{let save={v:1,openingSeen:true,startSeen:true,ch0Pull:true,starter:'10111',points:0,statV:99,cleared:{'1':[1,2,3]},leader:'u1',owned:[{uid:'u1',id:'10111',level:5}]};
const ok=d=>Promise.resolve({data:d,error:null});
const sb={from:()=>({select:()=>({eq:()=>({maybeSingle:()=>ok({data:save})})})}),rpc:(n,a)=>{if(n==='player_status')return ok({ok:true,level:20,max_level:100,xp:1,xp_next:9,stamina:40,stamina_max:40,regen_secs:360,next_regen_secs:1,cost:{story:6},unlocks:{}});
 if(n==='story_tickets')return ok({tickets:3,added:0}); if(n==='wallet_status')return ok({ok:true,gold:1,blood:1,shard:0,soul:0}); return Promise.resolve({data:null,error:{message:'Could not find the function '+n,code:'PGRST202'}});}};
const cloud={user:{id:'tuser',email:'a@b.c',user_metadata:{name:'형님'}},sb};window.__STORY_MOCK_CLOUD=cloud;window.__PLAYER_MOCK={cloud};})();"""
async def main():
  async with async_playwright() as p:
    kw={'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if os.path.exists('/usr/bin/google-chrome') else {}
    b=await p.chromium.launch(**kw); pg=await (await b.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True)).new_page(); errs=[]
    pg.on('pageerror',lambda e: errs.append(str(e)))
    await pg.add_init_script(MOCK); await pg.goto(URL); await pg.wait_for_function("window.VRStory && window.TCG && TCG.POOL.length")
    await pg.evaluate("VRStory.enter()"); await pg.wait_for_timeout(1200); await pg.evaluate("VRStory.openGacha('special')"); await pg.wait_for_timeout(1500)
    await pg.screenshot(path='/workspace/shots/ur-0.png'); print(await pg.evaluate("({shop:!!document.querySelector('.story-shop'),tab:document.querySelector('.gr-bn.on')?.dataset.tab,own:document.getElementById('gr-own')?.outerHTML,forced:!!document.querySelector('.gr-forced')})"))
    assert await pg.locator('.gr-go-ur').is_visible(), 'UR 확정 버튼'
    assert (await pg.inner_text('#gr-own-ur')).strip()=='2'
    await pg.screenshot(path='/workspace/shots/ur-1.png')
    await pg.click('.gr-go-ur')
    for _ in range(40):
      if '10325' in (await pg.inner_html('#tk-result')): break
      await pg.mouse.click(195,300); await pg.wait_for_timeout(500)
    assert '10325' in (await pg.inner_html('#tk-result')), 'UR 결과'
    assert (await pg.inner_text('#gr-own-ur')).strip()=='1'
    await pg.screenshot(path='/workspace/shots/ur-2.png')
    assert not errs, errs
    await b.close(); print('UR 확정권 UI OK')
asyncio.run(main())

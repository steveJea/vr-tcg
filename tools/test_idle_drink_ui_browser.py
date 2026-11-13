# Browser check (mock server): 방치 보상 창에 "드링크 2시간당 1" · 쌓인 보상/빠른 보상 미리보기에 드링크 · 예전 서버(드링크 없음)면 드링크 줄 없음
# Run: python3 -m http.server 8767 & python3 tools/test_idle_drink_ui_browser.py   (SHOTS=/workspace/voice-plan)
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/'); SHOTS=os.environ.get('SHOTS','/tmp')
INIT="""localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1');"""
def fake(old):
  return """(old) => { const st=()=>{const s={ok:true,level:100,rate:{gold:2400,shard:11,blood:6,dust:5,drink_every_h:2},hours:6.5,max_hours:8,full:false,
    pending:{gold:15600,shard:71,blood:39,dust:32,drink:3},ready:true,drink:{every_h:2,pending:3,carry_h:0,next_in_h:1.5,max_per_claim:4},
    boost:{cost:30,hours:4,left:2,max:2,reward:{gold:9600,shard:44,blood:24,dust:20,drink:2}}};
    if(old){delete s.rate.drink_every_h;delete s.pending.drink;delete s.drink;delete s.boost.reward.drink;} return s;};
    const sb={rpc:async n=>n==='idle_box_status'?{data:st(),error:null}:{data:null,error:{code:'PGRST202',message:'Could not find '+n}}};
    window.VRCloud={sb,user:{id:'mock'},isStaging:true}; }"""
async def run(b, old):
  pg=await (await b.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True)).new_page(); errs=[]
  pg.on('pageerror',lambda e: errs.append(str(e)))
  await pg.add_init_script(INIT); await pg.goto(URL); await pg.wait_for_function('window.VRIdleBox')
  await pg.evaluate(fake(old), old); await pg.evaluate('VRIdleBox.status().then(()=>VRIdleBox.open())')
  await pg.wait_for_selector('.idle-panel .idle-rate'); await pg.wait_for_timeout(700)
  t=await pg.inner_text('.idle-panel:visible' if False else '.idle-panel')
  return pg,t,errs
async def main():
  async with async_playwright() as p:
    kw={'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if os.path.exists('/usr/bin/google-chrome') else {}
    b=await p.chromium.launch(**kw)
    pg,t,errs=await run(b, False); print(t.replace('\n',' | ')[:300])
    assert '드링크 2시간당 1' in t and '드링크 3' in t and '드링크 2' in t and '다음 1개까지 1시간 30분' in t and '최대 4개' in t, t
    await pg.screenshot(path=f'{SHOTS}/idle_drink.png'); assert not errs, errs
    pg,t,errs=await run(b, True)
    assert '드링크' not in t and '2,400' in t, t; assert not errs, errs
    await b.close(); print('방치 보상 드링크 UI OK')
asyncio.run(main())

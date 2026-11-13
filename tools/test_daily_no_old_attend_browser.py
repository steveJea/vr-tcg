# Browser check: 일일 미션 창에 예전 7일 출석(attend_claim)이 없음 · 서버가 attend 를 보내도(오늘 안 받음) 뱃지·창에 안 나옴 · 미션 받기 정상 · 새 🎁 출석 버튼은 그대로
# Run: python3 -m http.server 8767 & python3 tools/test_daily_no_old_attend_browser.py   (SHOTS=/workspace/voice-plan)
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/'); SHOTS=os.environ.get('SHOTS','/tmp')
INIT="""localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1');localStorage.setItem('vrAttendShown:mock',new Date(Date.now()+9*3600e3).toISOString().slice(0,10));
window.__calls=[];window.__got=new Set();
const M=(key,name,goal,prog,reward)=>({key,name,goal,prog,reward,claimed:window.__got.has(key)});
window.__daily=()=>({ok:true,next_reset:new Date(Date.now()+3600e3).toISOString(),reward_held:false,
 attend:{today:false,step:2,total:9,rewards:Array.from({length:7},()=>({gold:3000}))},
 missions:[M('arcade','아케이드 플레이 x 1',1,1,{gold:1000}),M('win','전투 승리 x 3',3,1,{gold:2000}),M('story','스토리 스테이지 클리어 x 2',2,2,{gold:2000,gem:10}),M('tower','시련의 탑 도전 x 1',1,0,{gold:1500,gem:10}),M('skill','고유기술 사용 x 10',10,3,{gold:1500})],
 all:{reward:{gem:30},done:window.__got.size,goal:5,claimed:false}});
window.__ATTEND_MOCK=async n=>n==='attend_status'?{ok:true,today:'2026-11-13',lucky:{eligible:false,open:false,reason:'old_account',claims:0,claimed_today:false,rewards:[]},monthly:{month:'2026-11-01',claims:3,claimed_today:false,days:30,rewards:Array.from({length:30},()=>({gold:3000}))}}:null;"""
FAKE="""() => { const sb={rpc:async(n,a)=>{window.__calls.push(n); if(n==='daily_status')return{data:window.__daily(),error:null};
  if(n==='daily_claim'){window.__got.add(a.p_key);return{data:Object.assign(window.__daily(),{got:{gold:1000}}),error:null}}
  return{data:null,error:{code:'PGRST202',message:'Could not find the function '+n}}}};
  window.VRCloud={sb,user:{id:'mock'},isStaging:true}; window.VRDaily.status(); }"""
async def main():
  async with async_playwright() as p:
    kw={'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if os.path.exists('/usr/bin/google-chrome') else {}
    b=await p.chromium.launch(**kw); pg=await (await b.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True)).new_page(); errs=[]
    pg.on('pageerror',lambda e: errs.append(str(e)))
    await pg.add_init_script(INIT); await pg.goto(URL); await pg.wait_for_function('window.VRDaily'); await pg.evaluate(FAKE)
    await pg.wait_for_selector('[data-dailybtn] .daily-btn'); await pg.wait_for_timeout(800)
    badge=await pg.inner_text('[data-dailybtn] .story-badge'); assert badge.strip()=='2', badge   # arcade·story 만 (예전 출석 +1 없음)
    await pg.wait_for_selector('[data-attendbtn] .att-btn')   # 새 출석 버튼 그대로
    await pg.evaluate('VRDaily.open()'); await pg.wait_for_selector('.daily-panel .daily-list'); await pg.wait_for_timeout(500)
    t=await pg.inner_text('.daily-panel'); assert '출석' not in t and '일째' not in t, t
    assert await pg.locator('[data-att], .daily-att').count()==0
    await pg.screenshot(path=f'{SHOTS}/missions_no_old_attend.png')
    await pg.locator('[data-m="arcade"]:visible').first.click(); await pg.wait_for_timeout(600)
    assert 'daily_claim' in await pg.evaluate('window.__calls') and 'attend_claim' not in await pg.evaluate('window.__calls')
    assert not errs, errs
    await b.close(); print('일일 미션: 예전 출석 없음, 미션 받기·새 출석 버튼 OK')
asyncio.run(main())

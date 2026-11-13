# Browser check (mock server): 로그인 직후 출석 창 자동 표시(하루 1번) · 7일 행운 + 이번 달 칸 · 받기 → 칸 체크/버튼 잠김 · 메인 상단 출석 버튼 뱃지 · 서버 없으면 버튼 없음
# Run: python3 -m http.server 8767 & python3 tools/test_attendance_ui_browser.py   (SHOTS=/workspace/voice-plan)
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/'); SHOTS=os.environ.get('SHOTS','/tmp')
MOCK="""localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1');
const L=[{gold:10000},{drink:2},{tickets:3},{gem_free:100},{tickets:10},{gold:20000,blood:20000},{special_tickets:10}];
const C=[{gold:3000},{blood:3000},{gem_free:20},{drink:1},{shard:2000},{gold:3000,blood:3000},{tickets:1}];
const M=Array.from({length:30},(_, i)=>i>=28?{tickets:5}:C[i%7]);
window.__att={l:2,lt:false,m:9,mt:false};
const st=()=>({ok:true,today:'2026-11-13',lucky:{eligible:true,open:window.__att.l<7,reason:null,claims:window.__att.l,claimed_today:window.__att.lt,ends:'2026-11-26',window_days:14,rewards:L},
 monthly:{month:'2026-11-01',claims:window.__att.m,claimed_today:window.__att.mt,days:30,rewards:M}});
window.__ATTEND_MOCK=window.__ATT_OFF?null:async(n,a)=>{if(n==='attend_status')return st();
 const t=a.p_track;if(t==='lucky'){if(window.__att.lt)return{ok:false,reason:'already',status:st()};window.__att.l++;window.__att.lt=true;return{ok:true,track:t,slot:window.__att.l,reward:L[window.__att.l-1],got:{},status:st()}}
 if(window.__att.mt)return{ok:false,reason:'already',status:st()};window.__att.m++;window.__att.mt=true;return{ok:true,track:t,slot:window.__att.m,reward:M[window.__att.m-1],got:{},status:st()}};"""
async def main():
  async with async_playwright() as p:
    kw={'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if os.path.exists('/usr/bin/google-chrome') else {}
    b=await p.chromium.launch(**kw)
    ctx=await b.new_context(viewport={'width':390,'height':844},is_mobile=True,has_touch=True); pg=await ctx.new_page(); errs=[]
    pg.on('pageerror',lambda e: errs.append(str(e)))
    await pg.add_init_script(MOCK); await pg.goto(URL)
    await pg.wait_for_selector('#att-pop .att-panel', timeout=15000)
    t=await pg.inner_text('#att-pop'); print(t[:120].replace('\n',' '))
    assert '7일 간의 행운' in t and '11월 접속 선물' in t and '3일차 받기' in t and '10회째 받기' in t, t
    assert await pg.locator('.att-lucky .att-cell').count()==7 and await pg.locator('.att-month .att-cell').count()==30
    assert await pg.locator('.att-month .att-cell.tail').count()==2   # 29·30 (11월은 30일)
    await pg.screenshot(path=f'{SHOTS}/attendance_popup.png')
    await pg.click('[data-att-claim="lucky"]'); await pg.wait_for_timeout(300)
    await pg.click('[data-att-claim="monthly"]'); await pg.wait_for_timeout(400)
    assert await pg.locator('[data-att-claim][disabled]').count()==2
    assert await pg.locator('.att-lucky .att-cell.done').count()==3 and await pg.locator('.att-month .att-cell.done').count()==10
    await pg.screenshot(path=f'{SHOTS}/attendance_claimed.png')
    await pg.click('[data-att-x]'); assert await pg.locator('#att-pop').count()==0
    await pg.wait_for_selector('[data-attendbtn] .att-btn'); assert await pg.locator('[data-attendbtn] .story-badge').count()==0
    await pg.screenshot(path=f'{SHOTS}/attendance_button.png')
    await pg.reload(); await pg.wait_for_timeout(5000); assert await pg.locator('#att-pop').count()==0, 'auto popup once per day'
    await pg.click('[data-attendbtn] .att-btn'); await pg.wait_for_selector('#att-pop .att-panel')
    assert not errs, errs
    pg2=await (await b.new_context(viewport={'width':390,'height':844})).new_page(); e2=[]; pg2.on('pageerror',lambda e: e2.append(str(e)))
    await pg2.add_init_script('window.__ATT_OFF=1;'+MOCK); await pg2.goto(URL); await pg2.wait_for_timeout(5000)
    assert await pg2.locator('#att-pop').count()==0 and await pg2.locator('[data-attendbtn] .att-btn').count()==0, 'guest/no server: hidden'
    assert not e2, e2
    await b.close(); print('출석 UI OK')
asyncio.run(main())

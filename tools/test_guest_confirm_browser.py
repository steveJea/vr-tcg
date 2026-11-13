# 게스트 시작 확인창: 두 줄 문구 + '게스트로 시작' / '로그인하기'
# Run: python3 -m http.server 8767 & python3 tools/test_guest_confirm_browser.py   (SHOTS=/workspace/voice-plan)
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8767/'); SHOTS=os.environ.get('SHOTS','/tmp')
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome', headless=True)
    for w,h,name in [(360,740,'guest_confirm_mobile.png'),(1366,768,'guest_confirm_desktop.png')]:
      pg=await (await b.new_context(viewport={'width':w,'height':h})).new_page(); errs=[]
      pg.on('pageerror', lambda e: errs.append(str(e)))
      await pg.goto(URL); await pg.wait_for_selector('#intro:not(.hidden)', timeout=15000)
      await pg.click('#intro-guest'); await pg.wait_for_selector('#vr-confirm:not(.hidden)')
      t=await pg.inner_text('#vr-confirm-msg')
      assert '게스트는 아케이드만 할 수 있고, 기록은 저장되지 않아요.' in t and '로그인하면 인재 모집, 스토리, PvP, 조직까지 다 즐길 수 있어요!' in t, t
      assert await pg.evaluate("getComputedStyle(document.querySelector('.vc-guest-h')).fontWeight")>='700'
      assert (await pg.inner_text('#vr-confirm [data-yn=y]')).strip()=='게스트로 시작'
      assert (await pg.inner_text('#vr-confirm [data-yn=n]')).strip()=='로그인하기'
      ov=await pg.evaluate("(()=>{const c=document.querySelector('#vr-confirm .vc-card').getBoundingClientRect();return [...document.querySelectorAll('#vr-confirm .vc-card *')].some(e=>{const r=e.getBoundingClientRect();return r.width&&(r.right>c.right+1||r.left<c.left-1||e.scrollWidth>e.clientWidth+1&&getComputedStyle(e).overflow!=='visible')})||c.right>innerWidth||c.left<0})()")
      assert not ov, 'overflow'
      await pg.wait_for_timeout(300); await pg.screenshot(path=f'{SHOTS}/{name}')
      await pg.click('#vr-confirm [data-yn=n]'); await pg.wait_for_timeout(300)
      assert await pg.locator('#vr-confirm.hidden').count()==1 and await pg.locator('#intro:not(.hidden)').count()==1
      ae=await pg.evaluate("[document.activeElement?.id, document.activeElement?.tagName, getComputedStyle(document.getElementById('intro-login')).display, document.getElementById('intro-login').disabled]"); assert ae[0]=='intro-login' or (ae[3] and await pg.locator('.oauth-row.oauth-flash').count()==1), ae
      await pg.click('#intro-guest'); await pg.click('#vr-confirm [data-yn=y]'); await pg.wait_for_timeout(300)
      assert await pg.locator('#intro.hidden').count()==1
      assert (await pg.inner_text('#vr-confirm [data-yn=y]')).strip()=='Y', 'labels reset'
      assert not errs, errs
    await b.close(); print('게스트 확인창 OK')
asyncio.run(main())

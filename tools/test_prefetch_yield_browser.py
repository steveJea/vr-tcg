# 화면 그림이 늘 먼저: '전체 리소스 받기'가 도는 중에 전투를 열면 미리 받기가 바로 멈추고(받던 것도 끊음), 손패 썸네일이 빨리 뜸.
# Run: npm run build:staging && (cd .staging-dist && python3 -m http.server 8768 &) && URL=http://localhost:8768/ python3 tools/test_prefetch_yield_browser.py
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8768/')
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome', headless=True)
    ctx=await b.new_context(viewport={'width':390,'height':844}, is_mobile=True, has_touch=True)
    await ctx.add_init_script("localStorage.setItem('vrTcgIntroSeen','1'); window.__VR_PREFETCH_DELAY=600000")
    pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
    await pg.goto(URL, wait_until='load'); await pg.wait_for_function("window.TCG&&TCG.ready&&window.VRAssets", timeout=60000)
    await pg.evaluate("document.querySelectorAll('#yuri-tut,.hub-ov').forEach(e=>e.remove())"); await pg.wait_for_timeout(2500)
    await pg.evaluate("VRAssets.downloadAll((d,t,n)=>window.__n=n).then(j=>window.__job=j)")
    await pg.wait_for_function("window.__n>3 && VRAssets.prefetching>0", timeout=60000)
    await pg.evaluate("TCG.startGame()")
    await pg.wait_for_timeout(800)
    seen=[]
    for _ in range(12): seen.append(await pg.evaluate("VRAssets.prefetching")); await pg.wait_for_timeout(250)
    print('in battle prefetching', seen); assert max(seen)==0, seen
    n0=await pg.evaluate("window.__n"); await pg.wait_for_timeout(2000); n1=await pg.evaluate("window.__n"); assert n1==n0, (n0,n1)
    hand=await pg.evaluate("[...document.querySelectorAll('#me-hand img.card-img')].map(i=>i.complete&&i.naturalWidth>0)")
    print('hand', hand); assert hand and all(hand)
    await pg.evaluate("window.__job.cancel()")
    assert not errs, errs
    await b.close(); print('미리 받기 비켜 주기 OK')
asyncio.run(main())

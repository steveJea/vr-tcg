# 첫 화면 로딩 → 끝남 / 두 번째 로드는 기기 캐시(SW) / 설정 '전체 리소스 받기'(확인·진행·취소) / 캐시 삭제 / 로그인 버튼 그대로
# Run: npm run build:staging && (cd .staging-dist && python3 -m http.server 8768 &) && URL=http://localhost:8768/ python3 tools/test_asset_cache_browser.py
import asyncio, os, time
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8768/'); SHOTS=os.environ.get('SHOTS','/tmp'); THROTTLE=os.environ.get('THROTTLE')  # 예: 12 (Mbps)
async def throttle(pg):
  if not THROTTLE: return
  s=await pg.context.new_cdp_session(pg); await s.send('Network.enable')
  bps=float(THROTTLE)*1e6/8; await s.send('Network.emulateNetworkConditions',{'offline':False,'latency':60,'downloadThroughput':bps,'uploadThroughput':bps/4})
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome', headless=True)
    ctx=await b.new_context(viewport={'width':390,'height':844}, device_scale_factor=2, is_mobile=True, has_touch=True)
    await ctx.add_init_script("window.__VR_PREFETCH_DELAY=600000")   # 측정 중엔 뒤에서 미리 받기 끔
    pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
    await throttle(pg)
    t0=time.time(); await pg.goto(URL, wait_until='commit')
    await pg.wait_for_selector('#vr-boot', state='attached'); await pg.wait_for_timeout(int(os.environ.get('BOOT_SHOT_MS','450')))
    if await pg.locator('#vr-boot').count(): await pg.screenshot(path=f'{SHOTS}/boot_loading_mobile.png')
    await pg.wait_for_function("window.VRBoot", timeout=15000); boot1=await pg.evaluate("window.VRBoot"); await pg.wait_for_load_state('load'); load1=time.time()-t0
    await pg.wait_for_timeout(500); assert await pg.locator('#vr-boot').count()==0, 'loading screen removed'
    print('first', boot1, 'load', round(load1,2))
    assert boot1['ms'] <= 8500, boot1
    await pg.wait_for_function("navigator.serviceWorker && navigator.serviceWorker.controller", timeout=20000)
    # 두 번째 로드: 기기 캐시
    fromsw=[]; total=[]
    pg.on('response', lambda r: (total.append(r.url), r.from_service_worker and fromsw.append(r.url)))
    t0=time.time(); await pg.reload(wait_until='load'); load2=time.time()-t0
    await pg.wait_for_function("window.VRBoot"); boot2=await pg.evaluate("window.VRBoot")
    sw=[u for u in fromsw if '/img/' in u or '/js/' in u or '/css/' in u]
    print('repeat', boot2, 'load', round(load2,2), 'from SW', len(sw), '/', len([u for u in total if u.startswith(URL)]))
    assert len(sw) > 50, 'second load served from device cache'
    assert not [u for u in fromsw if 'supabase' in u or 'googleapis' in u or 'google' in u], 'no API/auth via cache'
    # 로그인 버튼은 그대로 (OAuth 이동은 서비스 워커가 안 건드림)
    await pg.evaluate("localStorage.removeItem('vrTcgIntroSeen')"); await pg.reload(wait_until='load'); await pg.wait_for_timeout(1500)
    if await pg.locator('#intro:not(.hidden)').count(): assert await pg.locator('#intro-login').count()==1
    await pg.evaluate("localStorage.setItem('vrTcgIntroSeen','1')"); await pg.reload(wait_until='load'); await pg.wait_for_timeout(3500)
    await pg.evaluate("document.getElementById('intro')?.classList.add('hidden'); document.querySelectorAll('#yuri-tut,.hub-ov').forEach(e=>e.remove())")
    # 설정 → 전체 리소스 받기 (게임설정 › 설정)
    await pg.evaluate("window.VRMenu.open()"); await pg.wait_for_timeout(300); await pg.evaluate("document.getElementById('main-settings-open').click()"); await pg.wait_for_timeout(1500)
    assert await pg.locator('#main-settings-pop:not(.hidden)').count()==1
    s=await pg.inner_text('#as-sum'); print('sum', s); assert 'MB' in s and '와이파이 권장' in s, s
    await pg.click('#as-dl'); await pg.wait_for_selector('#vr-confirm:not(.hidden)')
    t=await pg.inner_text('#vr-confirm-msg'); assert '약' in t and 'MB' in t and '와이파이' in t, t
    assert (await pg.inner_text('#vr-confirm [data-yn=y]')).strip()=='받기'
    await pg.wait_for_timeout(250); await pg.screenshot(path=f'{SHOTS}/settings_download_confirm_mobile.png')
    await pg.click('#vr-confirm [data-yn=y]'); await pg.wait_for_selector('#as-prog:not([hidden])')
    await pg.wait_for_function("parseInt(document.querySelector('#as-prog .as-bar i').style.width)>0", timeout=60000)
    await pg.wait_for_timeout(800); await pg.screenshot(path=f'{SHOTS}/settings_download_progress_mobile.png')
    print('progress', await pg.inner_text('#as-prog .as-txt'))
    await pg.click('#as-cancel'); await pg.wait_for_selector('#as-prog', state='hidden', timeout=20000)
    await pg.wait_for_timeout(1500); have=await pg.inner_text('#as-have'); print('have', have); assert '저장됨' in have
    # 캐시 삭제
    await pg.click('#as-clear'); await pg.wait_for_selector('#vr-confirm:not(.hidden)'); await pg.click('#vr-confirm [data-yn=y]'); await pg.wait_for_timeout(800)
    n=await pg.evaluate("caches.open('vr-assets-v1').then(c=>c.keys()).then(k=>k.length)"); assert n==0, n
    assert not errs, errs
    await b.close(); print('리소스 캐시 브라우저 검사 OK')
asyncio.run(main())

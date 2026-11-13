# 카드 그림이 같은 사이트(/img/bt_img/)에서 오고 raw.githubusercontent.com 요청이 없는지 (갤러리·인재 소개·스페셜 배너)
# Run: npm run build:staging && (cd .staging-dist && python3 -m http.server 8768 &) && URL=http://localhost:8768/ python3 tools/test_card_art_local_browser.py
import asyncio, os
from playwright.async_api import async_playwright
URL=os.environ.get('URL','http://localhost:8768/'); SHOTS=os.environ.get('SHOTS','/tmp')
async def main():
  async with async_playwright() as p:
    b=await p.chromium.launch(executable_path='/usr/bin/google-chrome', headless=True)
    ctx=await b.new_context(viewport={'width':390,'height':844}, device_scale_factor=2, is_mobile=True)
    await ctx.add_init_script("localStorage.setItem('vrTcgIntroSeen','1'); window.__VR_PREFETCH_DELAY=600000")
    pg=await ctx.new_page(); errs=[]; pg.on('pageerror', lambda e: errs.append(str(e)))
    gh=[]; art={}
    ctx.on('request', lambda r: ('githubusercontent' in r.url or 'github.com' in r.url) and gh.append(r.url))
    def resp(r):
      if '/img/bt_img/' in r.url and r.url.startswith(URL): art[r.url]=r.status
    ctx.on('response', resp)
    await pg.goto(URL, wait_until='load'); await pg.wait_for_function("window.VRBoot && window.TCG && TCG.POOL.length", timeout=30000)
    await pg.evaluate("document.querySelectorAll('#yuri-tut,.hub-ov').forEach(e=>e.remove())")
    await pg.evaluate("window.VRGallery.open()"); await pg.wait_for_timeout(3000)
    await pg.screenshot(path=f'{SHOTS}/card_art_gallery_mobile.png')
    await pg.evaluate("window.VRSpecial?.showIntro?.()"); await pg.wait_for_timeout(1500)
    ok=await pg.evaluate("(()=>{const i=document.querySelector('.sp-intro-img');return i?[i.currentSrc,i.naturalWidth]:null})()")
    print('intro', ok)
    await pg.screenshot(path=f'{SHOTS}/card_art_intro_mobile.png')
    # 모든 카드 id 의 원본이 같은 사이트에 있는지 (없으면 예전 주소로 넘어가는 대체 경로가 동작)
    miss=await pg.evaluate("(async()=>{const ids=[...new Set(TCG.POOL.map(c=>String(c.id)))];const bad=[];for(let i=0;i<ids.length;i+=24){await Promise.all(ids.slice(i,i+24).map(async id=>{const r=await fetch('/img/bt_img/'+id+'.webp',{method:'HEAD'});if(!r.ok)bad.push(id)}))}return [ids.length,bad]})()")
    print('pool ids', miss[0], 'missing locally', len(miss[1]), miss[1][:20])
    oks=[u for u,s in art.items() if s in (200,304)]
    print('bt_img responses', len(art), 'ok', len(oks), 'github requests', len(gh), gh[:3])
    assert len(oks) >= 2, art
    assert not gh, gh
    assert ok and ok[0].startswith(URL.rstrip('/')+'/img/bt_img/') and ok[1]>0, ok
    assert not errs, errs
    # 같은 사이트 파일이 빠지면 예전 주소로 한 번 더
    c2=await b.new_context(service_workers='block'); await c2.add_init_script("localStorage.setItem('vrTcgIntroSeen','1')"); pg2=await c2.new_page(); await pg2.route('**/img/bt_img/10325.webp', lambda r: r.fulfill(status=404, body='nf'))
    await pg2.route('https://raw.githubusercontent.com/**', lambda r: r.fulfill(status=200, content_type='image/webp', body=open('img/bt_img/10325.webp','rb').read()))
    await pg2.goto(URL, wait_until='load'); await pg2.wait_for_function("window.VRBoot")
    src=await pg2.evaluate("new Promise(r=>{const i=new Image();document.body.appendChild(i);i.onload=()=>r(i.src);i.src='/img/bt_img/10325.webp';setTimeout(()=>r('timeout '+i.src),6000)})")
    print('fallback', src); assert src.startswith('https://raw.githubusercontent.com/steveJea/vr-ideal-worldcup/main/img/bt_img/10325.webp'), src
    await b.close(); print('카드 그림 같은 사이트 OK')
asyncio.run(main())

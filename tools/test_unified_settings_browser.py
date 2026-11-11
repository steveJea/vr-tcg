# Browser check: every gear opens the same 게임설정 menu (home, page, battle). Run: python3 -m http.server 8766 & python3 tools/test_unified_settings_browser.py
import asyncio
from playwright.async_api import async_playwright
URL='http://localhost:8766/'
async def run(b,name,vp,mobile):
    ctx=await b.new_context(viewport=vp,is_mobile=mobile,has_touch=mobile)
    pg=await ctx.new_page(); errs=[]
    pg.on('pageerror',lambda e: errs.append(str(e)))
    await pg.add_init_script("localStorage.setItem('vrTutorialDone','1');localStorage.setItem('vrTcgIntroSeen','1')")
    await pg.goto(URL); await pg.wait_for_function("window.TCG && TCG.POOL.length && window.VRMenu")
    await pg.wait_for_timeout(500)
    vis=lambda sel: pg.evaluate(f"(()=>{{const e=document.querySelector('{sel}');return !!e&&e.getClientRects().length>0&&getComputedStyle(e).visibility!=='hidden'}})()")
    # 1 home via TNB gear
    await pg.click('#vr-tnb .tnb-set'); await pg.wait_for_timeout(300)
    assert await vis('#main-menu-pop .gm-card'); assert await vis('#main-rank'); assert await vis('#arcade-opts-btn')
    await pg.screenshot(path=f'/workspace/shots/gear/{name}-1home.png')
    await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200); assert not await vis('#main-menu-pop .gm-card')
    # 2 on a page (gallery page) via TNB gear
    await pg.evaluate("document.getElementById('main-gallery').click()"); await pg.wait_for_timeout(800)
    await pg.click('#vr-tnb .tnb-set'); await pg.wait_for_timeout(300)
    assert await vis('#main-menu-pop .gm-card'), 'menu on page'
    assert await vis('#main-rank') and not await vis('#arcade-opts-btn')
    top=await pg.evaluate("(()=>{const r=document.querySelector('#main-menu-pop .gm-card').getBoundingClientRect();const e=document.elementFromPoint(r.x+r.width/2,r.y+r.height/2);return !!e.closest('#main-menu-pop')})()")
    assert top,'menu on top of page'
    await pg.screenshot(path=f'/workspace/shots/gear/{name}-2page.png')
    await pg.click('#main-settings-open'); await pg.wait_for_timeout(300); assert await vis('#main-settings-pop .main-pop-card'); assert await vis('#main-voice')
    await pg.screenshot(path=f'/workspace/shots/gear/{name}-3settings.png')
    await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
    await pg.evaluate("window.VRPages?.closeNow?.()"); await pg.wait_for_timeout(500)
    # 3 battle
    await pg.evaluate("TCG.startGame()"); await pg.wait_for_function("TCG.S && TCG.S.turn==='me' && !TCG.S.busy",timeout=30000)
    await pg.click('#bset-btn'); await pg.wait_for_timeout(300)
    assert await vis('#main-menu-pop .gm-card'), 'menu in battle'
    assert await vis('#main-menu-pop #bset-pop #voice-toggle') and await vis('#main-menu-pop #fx-skip')
    for s in ['#main-rank','#main-gallery','#arcade-opts-btn','#main-logout','#main-tutorial']: assert not await vis(s), s
    assert await vis('#main-settings-open') and await vis('#main-howto')
    on=await pg.evaluate("TCG.voice.on"); await pg.click('#main-menu-pop #voice-toggle'); assert (await pg.evaluate("TCG.voice.on"))!=on
    assert await vis('#main-menu-pop .gm-card'),'stays open after toggle'
    await pg.click('#main-menu-pop #voice-toggle')
    await pg.screenshot(path=f'/workspace/shots/gear/{name}-4battle.png')
    await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
    assert await pg.evaluate("document.getElementById('bset-pop').parentNode.id==='top-bar' && document.getElementById('bset-pop').classList.contains('hidden') && document.getElementById('main-menu-pop').parentNode.id==='start-screen'")
    await pg.click('#bset-btn'); await pg.wait_for_timeout(200); await pg.click('#main-settings-open'); await pg.wait_for_timeout(300)
    assert await vis('#main-settings-pop .main-pop-card') and await vis('#main-voice-vol')
    await pg.screenshot(path=f'/workspace/shots/gear/{name}-5battle-settings.png')
    await pg.keyboard.press('Escape'); await pg.wait_for_timeout(200)
    await pg.click('#bset-btn'); await pg.wait_for_timeout(200); await pg.click('#main-menu-pop #help-btn'); await pg.wait_for_timeout(300)
    assert await vis('#help') and not await vis('#main-menu-pop .gm-card'),'help on top'
    assert await pg.evaluate("!TCG.S.over"), 'battle still running'
    assert not errs, errs
    await ctx.close(); print(name,'OK')
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(**({'executable_path':'/usr/bin/google-chrome','args':['--headless=new']} if __import__('os').path.exists('/usr/bin/google-chrome') else {}))
        await run(b,'desktop',{'width':1366,'height':860},False)
        await run(b,'mobile',{'width':390,'height':844},True)
        await b.close()
asyncio.run(main())

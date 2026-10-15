import asyncio, io, sys
from playwright.async_api import async_playwright
from PIL import Image
URL='http://localhost:8765/'
async def crops(b):
    pg=await b.new_page(viewport={'width':430,'height':900},device_scale_factor=2)
    await pg.add_init_script("localStorage.setItem('vrTutorialDone','1')")
    await pg.goto(URL); await pg.wait_for_function("window.TCG && TCG.POOL.length")
    await pg.evaluate("window.TCG_FAST=1;TCG.startGame()"); await pg.wait_for_timeout(800)
    await pg.wait_for_function("TCG.S.turn==='me'",timeout=20000)
    await pg.evaluate("""(()=>{const ids=TCG.POOL.filter(c=>c.grade!=='MYTHIC RARE'&&c.class!=='ABYSS').slice(0,6).map(c=>c.id);
      ids.slice(0,3).forEach(i=>TCG.put('me',i,3)); ids.slice(3,5).forEach(i=>TCG.put('ai',i,1)); TCG.S.me.field.forEach(u=>u.canAttack=true); TCG.render();})()""")
    await pg.wait_for_timeout(1200)
    for sel,name,w in [('#me-hero','hud',520),('#me-field','field',640),('#action-bar','shop',640)]:
        png=await pg.locator(sel).screenshot()
        im=Image.open(io.BytesIO(png)).convert('RGB'); im.thumbnail((w,400)); im.save(f'/workspace/vr-tcg/img/howto/{name}.webp','WEBP',quality=72)
    await pg.close()
async def run(b,name,vp,mobile,video=False):
    ctx=await b.new_context(viewport=vp,is_mobile=mobile,has_touch=mobile,**({'record_video_dir':'/tmp/vid','record_video_size':vp} if video else {}))
    pg=await ctx.new_page(); errs=[]
    pg.on('console',lambda m: m.type=='error' and errs.append(m.text)); pg.on('pageerror',lambda e: errs.append(str(e)))
    await pg.goto(URL); await pg.wait_for_function("window.TCG && TCG.POOL.length")
    assert await pg.locator('#tut-offer').is_visible(), 'offer'
    await pg.screenshot(path=f'/workspace/shots/howto-{name}-offer.png')
    await pg.click('#tut-offer [data-a=howto]'); await pg.wait_for_timeout(400)
    n=await pg.evaluate("HowTo.SLIDES.length")
    for i in range(n):
        assert await pg.evaluate("HowTo.index")==i
        await pg.screenshot(path=f'/workspace/shots/howto-{name}-slide{i+1:02d}.png')
        if i<n-1:
            if mobile or i%2==0:  # 스와이프
                box=await pg.locator('#howto .ht-view').bounding_box(); y=box['y']+box['height']/2
                await pg.mouse.move(box['x']+box['width']*0.85,y); await pg.mouse.down(); await pg.mouse.move(box['x']+box['width']*0.15,y,steps=8); await pg.mouse.up()
            else: await pg.click('#howto .ht-next')
            await pg.wait_for_timeout(450)
    await pg.click('#howto .ht-prev'); await pg.wait_for_timeout(350); assert await pg.evaluate("HowTo.index")==n-2
    await pg.click('#howto .ht-dots button >> nth=0'); await pg.wait_for_timeout(350); assert await pg.evaluate("HowTo.index")==0
    await pg.keyboard.press('Escape'); assert not await pg.locator('#howto').is_visible()
    await pg.click('#main-howto'); await pg.wait_for_timeout(200); await pg.mouse.click(3,3); assert not await pg.locator('#howto').is_visible(),'backdrop'
    # 튜토리얼 끝까지
    await pg.click('#main-howto'); await pg.click('#howto .ht-tut'); await pg.wait_for_timeout(1500)
    steps=await pg.evaluate("HowTo.STEPS.length")
    for i in range(steps):
        await pg.wait_for_timeout(700); await pg.screenshot(path=f'/workspace/shots/howto-{name}-tut{i+1}.png')
        await pg.click('#tut-box .tt-next')
    assert not await pg.locator('#tut-box').is_visible(); assert await pg.evaluate("localStorage.vrTutorialDone")=='1'
    # 게임 진행 확인: 내 턴에 카드 소환 → 턴 종료 → 다시 내 턴
    await pg.evaluate("window.TCG_FAST=1")
    await pg.wait_for_function("TCG.S.turn==='me' && !TCG.S.busy",timeout=30000)
    ok=await pg.evaluate("(()=>{const c=TCG.S.me.hand.find(c=>TCG.canSummon(c,TCG.S.me,TCG.S.ai).ok); return c?TCG.summon('me',c).ok:'none'})()")
    t0=await pg.evaluate("TCG.S.totalTurns"); await pg.evaluate("TCG.endTurn()")
    await pg.wait_for_function(f"TCG.S.over || (TCG.S.turn==='me' && TCG.S.totalTurns>{t0})",timeout=30000)
    # 다시 튜토리얼 → 중간 건너뛰기, 실제 클릭이 오버레이에 막히지 않는지
    await pg.evaluate("window.TCG_FAST=0; HowTo.Tutorial.start()"); await pg.wait_for_timeout(500)
    await pg.click('#tut-box .tt-next'); await pg.click('#tut-box .tt-next'); await pg.wait_for_timeout(600)
    if await pg.locator('#me-hand .hand-card').count():
        await pg.locator('#me-hand .hand-card').first.click(); await pg.wait_for_timeout(300)
        assert await pg.locator('#detail').is_visible(),'click-through'; assert not await pg.locator('#tut-box').is_visible()
        await pg.keyboard.press('Escape'); await pg.wait_for_timeout(500)
    await pg.screenshot(path=f'/workspace/shots/howto-{name}-midskip.png')
    await pg.click('#tut-box .tt-skip'); assert not await pg.locator('#tut-box').is_visible()
    # 게임 내 도움말 → How to Play
    await pg.click('#help-btn'); await pg.click('#help-howto'); await pg.wait_for_timeout(300); assert await pg.locator('#howto').is_visible(); await pg.keyboard.press('Escape')
    terr=await pg.evaluate("TCG.errors")
    print(name,'summon',ok,'errs',errs,'tcg',terr)
    await ctx.close()
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch()
        if 'crop' in sys.argv: await crops(b)
        else:
            await run(b,'desktop',{'width':1280,'height':800},False)
            await run(b,'mobile',{'width':390,'height':844},True,video=True)
        await b.close()
asyncio.run(main())

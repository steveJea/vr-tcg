import asyncio
from playwright.async_api import async_playwright
URL='http://localhost:8765/'
async def run(b,name,vp,mobile):
    ctx=await b.new_context(viewport=vp,is_mobile=mobile,has_touch=mobile)
    pg=await ctx.new_page(); errs=[]; reqs=[]
    pg.on('console',lambda m: m.type=='error' and errs.append(m.text)); pg.on('pageerror',lambda e: errs.append(str(e)))
    pg.on('request',lambda r: '/data/voice/' in r.url and reqs.append(r.url.split('/')[-1]))
    await pg.add_init_script("localStorage.setItem('vrTutorialDone','1')")
    await pg.goto(URL); await pg.wait_for_function("window.TCG && TCG.POOL.length && TCG.voice.set")
    await pg.evaluate("TCG.startGame()"); await pg.wait_for_function("TCG.S.turn==='me' && !TCG.S.busy",timeout=30000)
    await pg.mouse.click(5,vp['height']-5)  # 첫 탭 -> 오디오 잠금 해제
    await pg.evaluate("""(()=>{TCG.put('me','10311',5);TCG.put('ai','10325',5);const u=TCG.S.me.field.find(x=>x.card.id==='10311');u.mp=999;u.canAttack=true;TCG.render();window._u=u;})()""")
    print(await pg.evaluate("JSON.stringify(TCG.skillState(_u,_u.sk[0]))+_u.level"))
    await pg.evaluate("TCG.castSkill('me',_u,_u.sk[0])"); await pg.wait_for_timeout(700)
    v=await pg.evaluate("TCG.voice"); print(name,v,reqs)
    assert v['cur'] and '10311_1.mp3' in v['cur']['src'] and (not v['cur']['paused'] or v['cur']['t']>0)
    await pg.wait_for_function("!TCG.S.busy",timeout=10000)
    await pg.click('#voice-toggle'); assert (await pg.evaluate("TCG.voice"))['on']==False
    await pg.click('#voice-toggle')
    await pg.locator('#voice-toggle').scroll_into_view_if_needed()
    if name=='desktop':
        box=await pg.locator('#voice-toggle').bounding_box()
        await pg.screenshot(path='/workspace/shots/voice-toggle.png',clip={'x':max(0,box['x']-200),'y':max(0,box['y']-40),'width':520,'height':120})
    await pg.screenshot(path=f'/workspace/shots/voice-{name}.png')
    assert not errs, errs
    await ctx.close()
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(args=['--autoplay-policy=user-gesture-required'])
        await run(b,'desktop',{'width':1366,'height':860},False)
        await run(b,'mobile',{'width':390,'height':844},True)
        await b.close(); print('OK')
asyncio.run(main())

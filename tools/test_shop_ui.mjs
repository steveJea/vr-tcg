// 상점 페이지 (시트 68): 6탭(스킨 없음), 원화 = 테스트 지급(우편), 토스 결제창 안 씀, 심연석 상점 수량·장비 9칸, 인재 소환 이동, 팝업스토어, 운영 차단.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {parseHTML} from 'linkedom';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const {window}=parseHTML('<html><body><div id="start-screen"></div><div id="game" class="hidden"></div><button data-gnb="summon"></button></body></html>');
const document=window.document;
const calls=[];const checkouts=[];let summon=0;
const P=(sku,tab,name,price,extra={})=>({sku,tab,name,blurb:extra.blurb||'',price_krw:price,month_max:null,acct_max:null,month_used:0,acct_used:0,grant:extra.grant||{},first_open:false,...extra});
const products=[
 P('pass_1','pass','프리미엄 시즌패스',5500,{grant:{pass:true,days:30}}),P('pass_2','pass','스페셜 시즌패스',22000,{grant:{pass:true,days:30}}),P('pass_3','pass','럭셔리 시즌패스',44000,{grant:{pass:true,days:30},pass_until:'2026-12-16'}),
 P('gem_100','charge','심연석 100',1100,{grant:{gem_paid:100,gem_free:0,first_double:true},first_open:true}),P('gem_500','charge','심연석 525',5500,{grant:{gem_paid:500,gem_free:25,first_double:true}}),
 P('prem_10','pack','프리미엄 소환권 10',11000,{grant:{tickets:10},month_max:3}),P('prem_25','pack','프리미엄 소환권 25',33000,{grant:{tickets:25},month_max:3,month_used:3}),P('spec_45','pack','스페셜 소환권 45',66000,{grant:{special_tickets:45},month_max:2}),
 P('level_1','pack','레벨업 패키지',22000,{grant:{gold:150000},month_max:2}),
 P('popup_first','popup','첫 구매 혜택',1650,{acct_max:1,acct_used:1}),P('popup_special','popup','스페셜 구매 혜택',16500,{acct_max:1})];
const gear=Array.from({length:9},(_,i)=>({slot_no:i+1,slot:['weapon','armor','acc'][Math.floor(i/3)],grade:i===8?'UR':i===4?'SR':'HR',tier:i===8?6:i===4?5:4,def_id:`${['weapon','armor','acc'][Math.floor(i/3)]}_4_${i%3+1}`,name:'장비'+(i+1),price:i===8?5000:i===4?1000:500,bought:i===0}));
const status=()=>({ok:true,v:2,gem:10,free:4,paid:6,tickets:3,special_tickets:2,krw_test:true,products,passes:[],
 gem_items:[{sku:'gem_prem_ticket',name:'프리미엄 소환권',price:150,grant:{tickets:1},max_qty:99},{sku:'gem_spec_ticket',name:'스페셜 소환권',price:150,grant:{special_tickets:1},max_qty:99},{sku:'gem_drink',name:'유료 드링크',price:100,grant:{drink:1},max_qty:99}],
 gear,gear_rates:{HR:{weight:950},SR:{weight:49},UR:{weight:1}}});
window.__SHOP_MOCK=async(name,args)=>{calls.push({name,args});if(name==='shop_pass_days')return {today:'2026-11-17',via:'mail',mail_pending:0,passes:[]};if(name==='shop_buy')return {...status(),first_bonus:true,mailed:true};return status();};
window.VRAsk=async()=>true;window.VRPayments={enabled:true,checkout(p){checkouts.push(p);}};
const toasts=[];
window.VRGem={toast(t){toasts.push(t);},status:async()=>({}),buy:async()=>null,priceBtn:()=>'',open(){return window.VRShop.open();}};
window.VRDrink={status:async()=>null,html:()=>'<div class="drink-box">드링크</div>',bind(){}};
document.querySelector('[data-gnb="summon"]').addEventListener('click',()=>summon++);
const location={search:'',hash:'',pathname:'/',origin:'https://vr-tcg-staging.notcold.workers.dev'};
const history={pushState(){},replaceState(){},back(){},go(){}};
window.location=location;window.history=history;
const ctx=vm.createContext({window,document,console,setTimeout,clearTimeout,setInterval:()=>0,clearInterval(){},history,location,localStorage:{getItem:()=>null,setItem(){},removeItem(){}},matchMedia:()=>({matches:false}),addEventListener(){},getComputedStyle:()=>({display:'block'}),confirm:()=>true});
for(const file of ['js/pages.js','js/gem.js','js/drink.js','js/shop.js'])vm.runInContext(await read(file),ctx);
const wait=async f=>{for(let i=0;i<50&&!f();i++)await new Promise(r=>setTimeout(r,0));};
const tab=async id=>{document.querySelector(`[data-tab="${id}"]`).click();await wait(()=>true);};
window.VRGem.open();
await wait(()=>document.querySelector('.shop-tabs'));
const tabs=[...document.querySelectorAll('.shop-tabs [data-tab]')].map(b=>b.textContent.trim());
assert.deepEqual(tabs,['시즌패스','심연석 패키지','아이템 패키지','심연석 상점','인재 소환 ↗','팝업스토어']);
assert.doesNotMatch(document.body.textContent,/스킨/);
assert.match(document.body.textContent,/구매한 상품은 모두/);
// default = 심연석 패키지 (gem chip +): first ×2
assert.match(document.body.textContent,/첫 구매 ×2/);assert.match(document.body.textContent,/첫 구매 시 200개/);
assert.match(document.body.textContent,/1,100원 · 테스트 지급/);
document.querySelector('[data-sku="gem_100"]').click();await wait(()=>calls.some(c=>c.name==='shop_buy'));
assert.deepEqual(JSON.parse(JSON.stringify(calls.find(c=>c.name==='shop_buy').args)),{p_sku:'gem_100'});
assert.equal(checkouts.length,0,'shop never opens the Toss checkout');
await wait(()=>document.querySelector('.gem-toast'));assert.match([...document.querySelectorAll('.gem-toast')].map(e=>e.textContent).join(),/우편함/);
// pass: 30 days copy, active pass disabled
await tab('pass');
assert.match(document.body.textContent,/30일/);assert.doesNotMatch(document.body.textContent,/31일/);
assert.equal(document.querySelector('[data-sku="pass_3"]').disabled,true);assert.match(document.querySelector('[data-sku="pass_3"]').textContent,/이용 중/);
assert.ok(document.querySelector('.shop-banner img[src="img/ui/shop/pass_banner.webp"]'));
// pack: monthly limit
await tab('pack');
assert.equal(document.querySelector('[data-sku="prem_25"]').disabled,true);assert.match(document.body.textContent,/이번 달 3\/3/);
assert.ok(document.querySelector('[data-sp-rates]'));
// gem shop: qty stepper and gear grid
await tab('gem');
assert.equal(document.querySelectorAll('.shop-qrow').length,3);
document.querySelector('[data-q="gem_drink"][data-d="1"]').click();await wait(()=>true);
document.querySelector('[data-q="gem_drink"][data-d="1"]').click();await wait(()=>true);
assert.match(document.querySelector('[data-gem-item="gem_drink"]').textContent,/300/);
document.querySelector('[data-gem-item="gem_drink"]').click();await wait(()=>calls.some(c=>c.name==='shop_gem_buy'));
assert.deepEqual(JSON.parse(JSON.stringify(calls.find(c=>c.name==='shop_gem_buy').args)),{p_sku:'gem_drink',p_qty:3});
await wait(()=>document.querySelectorAll('.shop-gear').length===9);
assert.equal(document.querySelectorAll('.shop-gear').length,9);assert.equal(document.querySelector('[data-gear="1"]').disabled,true);
assert.match(document.body.textContent,/HR 95% · SR 4.9% · UR 0.1%/);
// paid drink = gold icon + gold label in gem shop
assert.ok(document.querySelector('.shop-qrow img[src="img/ui/cur_drink_paid.webp"]'),'paid drink icon');assert.ok(document.querySelector('.shop-qmeta .drk-name.paid'),'paid drink label');
document.querySelector('[data-gear="9"]').click();await wait(()=>calls.some(c=>c.name==='shop_gear_buy'));
assert.deepEqual(JSON.parse(JSON.stringify(calls.find(c=>c.name==='shop_gear_buy').args)),{p_slot:9});
// summon = outlink
await tab('gem');document.querySelector('[data-tab="summon"]').click();assert.equal(summon,1);
// popup: once per account
await tab('popup');
assert.equal(document.querySelector('[data-sku="popup_first"]').disabled,true);assert.match(document.body.textContent,/계정당 1회/);
assert.equal(document.querySelector('[data-sku="popup_special"]').disabled,false);
// drink/topnav go to the gem shop tab
for(const f of ['js/drink.js','js/topnav.js'])assert.match(await read(f),/VRShop\.open\('gem'\)/);
// mailbox shows new attachments
const gearSrc=await read('js/gear.js');for(const k of ['gem_paid','special_tickets','drink_bound','p.card'])assert.ok(gearSrc.includes(k),k);
// Production (no staging flag, no mock): the shop page never opens.
{const mock=window.__SHOP_MOCK;delete window.__SHOP_MOCK;const cloud=window.VRCloud;window.VRCloud={...(cloud||{}),isStaging:false,user:{id:'u'}};
 assert.equal(window.VRShop.enabled,false);assert.equal(window.VRShop.open(),null);
 window.VRCloud={...(cloud||{}),isStaging:true,user:{id:'u'}};assert.equal(window.VRShop.enabled,true);
 window.VRCloud=cloud;window.__SHOP_MOCK=mock;}
for(const f of ['js/gem.js','js/topnav.js'])assert.match(await read(f),/window\.VRShop\?\.enabled && window\.VRShop\.open/);
assert.match(await read('js/cloud.js'),/get isStaging\(\) \{ return config\.isStaging === true; \}/);
console.log('Shop UI: 6 tabs (no skins), KRW test grant via mail, no Toss, pass 30d, monthly/account limits, gem shop qty + 9 gear slots, summon outlink, popup, production gate OK');

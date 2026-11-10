// 상점 페이지: 탭, 스킨 자리, 테스트 지급, 결제 켜져 있으면 심연석만 기존 체크아웃.
import assert from 'node:assert/strict';
import vm from 'node:vm';
import {readFile} from 'node:fs/promises';
import {parseHTML} from 'linkedom';
const read=p=>readFile(new URL('../'+p,import.meta.url),'utf8');
const {window}=parseHTML('<html><body><div id="start-screen"></div><div id="game" class="hidden"></div></body></html>');
const document=window.document;
const calls=[];let payments=false;const checkouts=[];
const products=[
 {sku:'gem_100',tab:'charge',name:'심연석 100',blurb:'첫 구매 2배',price_krw:1100,month_max:null,month_used:0,grant:{gem_paid:100,gem_free:0,first_double:true},payment_sku:'gem_100',first_open:true},
 {sku:'ticket_10',tab:'pack',name:'스페셜 소환권 10장',blurb:'월 1회',price_krw:1100,month_max:1,month_used:0,grant:{tickets:10},payment_sku:null,first_open:false},
 {sku:'pass_1',tab:'pass',name:'시즌패스 1',blurb:'매일',price_krw:5500,month_max:null,month_used:0,grant:{pass:true},payment_sku:null,first_open:false}
];
const status=()=>({ok:true,gem:10,free:4,paid:6,products,passes:[]});
window.__SHOP_MOCK=async(name,args)=>{calls.push({name,args});if(name==='shop_buy')return {...status(),first_bonus:true,paid:206};return {...status(),claimed:[]};};
window.VRAsk=async()=>true;window.VRPayments={get enabled(){return payments;},checkout(p){checkouts.push(p);}};
window.VRGem={toast(){},status:async()=>({}),buy:async()=>null,priceBtn:()=>'<button data-gem-buy="stamina">충전</button>',open(){return window.VRShop.open();}};
window.VRDrink={status:async()=>null,html:()=>'<div class="drink-box">드링크</div>',bind(){}};
const location={search:'',hash:'',pathname:'/',origin:'https://vr-tcg-staging.notcold.workers.dev'};
const history={pushState(){},replaceState(){},back(){},go(){}};
window.location=location;window.history=history;
const ctx=vm.createContext({window,document,console,setTimeout,clearTimeout,setInterval:()=>0,clearInterval(){},history,location,localStorage:{getItem:()=>null,setItem(){},removeItem(){}},matchMedia:()=>({matches:false}),addEventListener(){},getComputedStyle:()=>({display:'block'}),confirm:()=>true});
for(const file of ['js/pages.js','js/gem.js','js/drink.js','js/shop.js'])vm.runInContext(await read(file),ctx);
window.VRGem.open();
await new Promise(r=>setTimeout(r,0));
const text=document.body.textContent;
for(const name of ['충전','패키지','패스','소모품','스킨'])assert.match(text,new RegExp(name));
document.querySelector('[data-tab="skin"]').click();
assert.match(document.body.textContent,/스킨 준비 중/);
document.querySelector('[data-tab="charge"]').click();
assert.match(document.body.textContent,/첫 구매 200/);
document.querySelector('[data-sku="gem_100"]').click();
await new Promise(r=>setTimeout(r,0));
assert.equal(checkouts.length,0);assert.equal(calls.at(-1).name,'shop_buy');assert.equal(calls.at(-1).args.p_sku,'gem_100');
payments=true;document.querySelector('[data-sku="gem_100"]').click();
await new Promise(r=>setTimeout(r,0));
assert.equal(checkouts.length,1);assert.equal(checkouts[0].id,'gem_100');
document.querySelector('[data-tab="consume"]').click();
await new Promise(r=>setTimeout(r,0));
assert.match(document.body.textContent,/무료 심연석을 먼저/);
assert.match(document.body.textContent,/행동력 최대 충전과는 다른/);
console.log('Shop UI: tabs, empty skins, 2x copy, test grant, Toss only for gems OK');

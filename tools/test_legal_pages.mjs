import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {execFileSync} from 'node:child_process';
import {parseHTML} from 'linkedom';
import {addLegalLinks} from './add_legal_links.mjs';
const root=new URL('../',import.meta.url),read=p=>readFile(new URL(p,root),'utf8');
const pages=await Promise.all(['terms.html','privacy.html'].map(read));
for(const [i,html]of pages.entries()) {
 const {document:d}=parseHTML(html);assert.equal(d.documentElement.lang,'ko');assert.equal(d.querySelectorAll('h1').length,1);assert(d.title.includes('VR: Abyss Gate'));
 assert.match(d.querySelector('.legal-draft').textContent,/검토용 초안/);assert.match(d.querySelector('.legal-draft').textContent,/동의한 것으로 보지/);
 assert(d.querySelectorAll('h2').length>=10);assert(d.querySelector('main'));assert(d.querySelector('[href="/css/legal.css"]'));assert(!d.querySelector('script,iframe,form,input'));
 assert.match(d.querySelector('meta[http-equiv="Content-Security-Policy"]').getAttribute('content'),/default-src 'none'/);assert.equal(d.querySelector('meta[name="referrer"]').getAttribute('content'),'no-referrer');
 for(const p of ['연령 확인 방식·절차 확정 필요'])assert(html.includes('['+p+']'));
 for(const p of ['시행일 입력 필요','사업장 주소 입력 필요','통신판매업 신고번호·신고기관 입력 필요','고객문의 전화번호 입력 필요'])assert(!html.includes('['+p+']'));
 for(const v of ['서울시 성북구 보국문로 95, 303호','2026년 11월 16일','070-5275-5361'])assert(html.includes(v),v);

 for(const a of d.querySelectorAll('a[target="_blank"]'))assert(a.rel.includes('noopener')&&a.rel.includes('noreferrer'));
 for(const a of d.querySelectorAll('a')){if(a.getAttribute('href').startsWith('mailto:'))assert.equal(a.getAttribute('href'),'mailto:contact@entincode.co.kr');assert(!/javascript:/i.test(a.href));}
 assert.equal(d.querySelector('nav [aria-current="page"]').textContent,i?'개인정보처리방침':'이용약관');
 assert(!/__\w+__|example\.com|test@example/i.test(html));
 for(const value of ['엔터인코드(ENT.INCODE)','장윤석','738-44-01302','contact@entincode.co.kr','만 19세 이상','등급분류 결과에 따라'])assert(d.body.textContent.includes(value),value);
 for(const stale of ['[법적 사업자명 입력 필요]','[대표자명 입력 필요]','[사업자등록번호 입력 필요]','[고객문의 이메일 입력 필요]','[개인정보 보호책임자 성명·직책 입력 필요]','[이용 가능 연령·확인 방식 확정 필요]','[만14세 미만 이용정책·법정대리인 동의절차 확정 필요]'])assert(!html.includes(stale),stale);
 assert(d.querySelector('a[href="mailto:contact@entincode.co.kr"]'));
 assert(d.querySelector('a[href="https://www.entincode.co.kr"]'));
}
assert.match(pages[0],/2026-서울성북-1401 \(서울특별시 성북구\)/);assert.match(pages[1],/장윤석 \(대표,/);
assert.match(pages[0],/7일/);assert.match(pages[0],/3영업일/);assert.match(pages[0],/가분적/);assert.match(pages[0],/법정대리인/);assert.match(pages[0],/청약철회를 이유로 위약금/);assert.match(pages[0],/현금 결제·심연석 충전은 준비 중/);
for(const name of ['Supabase','Cloudflare','Google','Kakao','X','Google Analytics','jsDelivr','GitHub Pages','localStorage','sessionStorage','법정대리인','국외','처리정지','계정삭제 버튼','공유 이미지','카카오에 업로드'])assert(pages[1].includes(name),name);
assert.match(pages[1],/동의 배너·거부 스위치는 구현되어 있지/);assert.match(pages[1],/백업 보유·삭제 반영기간 확정 필요/);
const index=await read('index.html'),{document:d}=parseHTML(index);
for(const id of ['intro-legal-links','settings-legal-links']){const nav=d.getElementById(id);assert(nav);assert.deepEqual([...nav.querySelectorAll('a')].map(a=>[a.textContent,a.getAttribute('href')]),[['이용약관','/terms.html'],['개인정보처리방침','/privacy.html'],['서비스 소개','/about.html'],['연령 확인 (19+)','/age.html']]);assert(!nav.querySelector('small'));}
assert.equal(addLegalLinks(index),index,'overlay idempotent');
const stripped=index.replace('  <link rel="stylesheet" href="css/legal.css">\n','').replace(/\s*<nav id="(?:intro|settings)-legal-links"[^>]*>[\s\S]*?<\/nav>/g,'');
assert.match(addLegalLinks(stripped),/intro-legal-links/);assert.throws(()=>addLegalLinks('<html></html>'));
assert.throws(()=>addLegalLinks(index.replace('id="intro-legal-links"','id="removed-nav"')));
assert.throws(()=>addLegalLinks(stripped.replace('<head>','<head><link rel="stylesheet" href="css/legal.css">')));
assert.throws(()=>addLegalLinks(index+'<nav id="intro-legal-links"></nav>'));
const css=await read('css/legal.css');assert.match(css,/font:600 16px/);assert.match(css,/flex-wrap:wrap/);assert.match(css,/focus-visible/);assert(!/@import|https?:|url\(/i.test(css));
for(const builder of ['tools/build_staging.mjs','tools/build_production_assets.mjs']){const s=await read(builder);for(const p of ['terms.html','privacy.html','about.html','age.html'])assert(s.includes("'"+p+"'"));}
for(const [flag,dir]of [['--staging-build','.staging-dist'],['--production-build','.production-dist']])if(process.argv.includes(flag))for(const p of ['terms.html','privacy.html','about.html','age.html','css/legal.css','index.html','js/age-page.js','js/footer.js'])assert.equal(await read(dir+'/'+p),await read(p),'actual static build includes '+p);
if(process.argv.includes('--production-build')) {
 // 운영 빌드 = 이번 출시 후보(staging 의 화면 그대로) + 기기 캐시. 예전 '법적 링크만' 기준(b0a8dbab)은 20261111 출시로 끝남.
 // 바뀌면 안 되는 운영 런타임 설정은 지금 운영(main) 기준으로 비교.
 const main=execFileSync('git',['rev-parse','origin/main'],{cwd:root,encoding:'utf8'}).trim();
 for(const p of ['wrangler.production.jsonc','worker/media-range.mjs'])assert.equal(await read(p),execFileSync('git',['show',main+':'+p],{cwd:root,encoding:'utf8'}),'production runtime unchanged '+p);
 const pidx=await read('.production-dist/index.html');
 for(const id of ['vr-boot','as-dl','as-sum','as-prog','as-cancel','as-clear','as-have','intro-legal-links'])assert.match(pidx,new RegExp('id="'+id+'"'),'production index has '+id);
 assert.match(pidx,/src="js\/asset-cache\.js"/);
 assert.equal(await read('.production-dist/sw.js'),await read('sw.js'),'production sw.js = repo sw.js');
 const man=JSON.parse(await read('.production-dist/asset-manifest.json'));assert(man.files['/js/asset-cache.js']&&man.files['/img/bt_img/10440.webp'],'production asset manifest lists js + card art');
 assert(!Object.keys(man.files).some(k=>/^\/(supabase|tools|docs)\//.test(k)),'no server files in manifest');
 const h=await read('.production-dist/_headers');
 assert.match(h,/^https:\/\/vr-tcg-prod\.notcold\.workers\.dev\/\*\n  X-Robots-Tag: noindex, nofollow\n/,'only workers.dev host noindex');
 for(const r of ['/data/fx/*','/data/event/*','/data/voice/*','/img/*'])assert(h.includes(r+'\n  Cache-Control: public, max-age=600, stale-while-revalidate=86400\n'),'media cache '+r);
 for(const r of ['/sw.js','/asset-manifest.json'])assert(h.includes(r+'\n  Cache-Control: no-cache\n'),'no-cache '+r);
 assert(!/^\/\*\n  X-Robots-Tag/m.test(h),'production domain stays indexable');
 for(const p of ['payment-return.html','admin-payments.html','age-verify-return.html'])assert(!existsSync(new URL('.production-dist/'+p,root)),'no payment pages in production');
}

const COMPANY={name:'엔터인코드',ceo:'장윤석',brn:'738-44-01302',address:'서울시 성북구 보국문로 95, 303호',phone:'070-5275-5361',mailOrderNo:'2026-서울성북-1401'};
const footerJs=await read('js/footer.js');
assert.match(footerJs,/mailOrderNo:\s*'2026-서울성북-1401'/);
assert.match(footerJs,/https:\/\/www\.entincode\.co\.kr/);
assert(!/href=\"https:\/\/www\.mbbs\.kr\/?\"/.test(footerJs),'Ent.INCODE copyright/home link is not mbbs.kr');

assert.match(footerJs,new RegExp(COMPANY.phone));
assert.match(footerJs,/신고 준비중/);
const publicPages=[['about.html','서비스 소개'],['age.html','연령 확인 (19+)']];
for(const [file,title] of publicPages){
  const html=await read(file); const {document:d}=parseHTML(html);
  assert.equal(d.documentElement.lang,'ko');
  assert(d.title.includes('Violence Royale : The Abyss Gate')||d.title.includes('VR: Abyss Gate'));
  assert(d.querySelector('h1').textContent.includes(title.split(' (')[0]));
  for(const v of [COMPANY.name,COMPANY.ceo,COMPANY.brn,COMPANY.address,COMPANY.phone,COMPANY.mailOrderNo])assert(html.includes(v),file+' '+v);
  assert(d.querySelector('a[href="/terms.html"]')&&d.querySelector('a[href="/privacy.html"]')&&d.querySelector('a[href="/about.html"]')&&d.querySelector('a[href="/age.html"]')&&d.querySelector('a[href="/"]'));
  assert(d.querySelector('a[href="https://www.entincode.co.kr"]'),file+' company site link');
  assert(d.querySelector('.site-biz'));
  assert.equal(d.querySelector('meta[name="referrer"]').getAttribute('content'),'no-referrer');
}
const about=await read('about.html');
assert.match(about,/스토리 카드 RPG/);
assert(!/script/i.test(about.replace(/Content-Security-Policy[^>]*>/,'').replace(/stylesheet[^>]*>/g,'')) || !/<script/i.test(about));
assert(!about.includes('<script'));
const age=await read('age.html');
assert.match(age,/만 19세 미만/);
assert.match(age,/휴대폰 본인인증/);
assert.match(age,/다날/);
assert.match(age,/포트원|PortOne/);
assert.match(age,/id="age-verify-btn"/);
assert.match(age,/연동은 준비 중/);
assert.match(age,/src="\/js\/age-page.js"/);
const ageJs=await read('js/age-page.js');
assert.match(ageJs,/age-verify-btn/);
assert(!/portone|PortOne|cdn\.portone|requestIdentityVerification/i.test(ageJs));
const indexHtml=await read('index.html');
assert.match(indexHtml,/id="intro-foot"/);
assert(!/id="lobby-foot"/.test(indexHtml),'no lobby-foot on the game lobby');
assert(!footerJs.includes('lobby-foot'),'footer.js does not render a lobby footer');
console.log('Legal pages: Korean draft/placeholders, current data/analytics/share/retention gaps, statutory refund/minors, accessible link-only UI, no trackers/forms, build allowlists/idempotent isolated overlay OK');

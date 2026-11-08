import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
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
 for(const p of ['시행일 입력 필요','사업장 주소 입력 필요','고객문의 전화번호 입력 필요','연령 확인 방식·절차 확정 필요'])assert(html.includes('['+p+']'));
 for(const a of d.querySelectorAll('a[target="_blank"]'))assert(a.rel.includes('noopener')&&a.rel.includes('noreferrer'));
 for(const a of d.querySelectorAll('a')){if(a.getAttribute('href').startsWith('mailto:'))assert.equal(a.getAttribute('href'),'mailto:contact@entincode.co.kr');assert(!/javascript:/i.test(a.href));}
 assert.equal(d.querySelector('nav [aria-current="page"]').textContent,i?'개인정보처리방침':'이용약관');
 assert(!/__\w+__|example\.com|test@example/i.test(html));
 for(const value of ['엔터인코드(ENT.INCODE)','장윤석','738-44-01302','contact@entincode.co.kr','만 15세 이상','등급분류 결과에 따라'])assert(d.body.textContent.includes(value),value);
 for(const stale of ['[법적 사업자명 입력 필요]','[대표자명 입력 필요]','[사업자등록번호 입력 필요]','[고객문의 이메일 입력 필요]','[개인정보 보호책임자 성명·직책 입력 필요]','[이용 가능 연령·확인 방식 확정 필요]','[만14세 미만 이용정책·법정대리인 동의절차 확정 필요]'])assert(!html.includes(stale),stale);
 assert(d.querySelector('a[href="mailto:contact@entincode.co.kr"]'));
}
assert.match(pages[0],/신고 완료 · 번호 발급 대기/);assert.match(pages[1],/장윤석 \(대표,/);
assert.match(pages[0],/7일/);assert.match(pages[0],/3영업일/);assert.match(pages[0],/가분적/);assert.match(pages[0],/법정대리인/);assert.match(pages[0],/청약철회를 이유로 위약금/);assert.match(pages[0],/현금 결제·심연석 충전은 준비 중/);
for(const name of ['Supabase','Cloudflare','Google','Kakao','X','Google Analytics','jsDelivr','GitHub Pages','localStorage','sessionStorage','법정대리인','국외','처리정지','계정삭제 버튼','공유 이미지','카카오에 업로드'])assert(pages[1].includes(name),name);
assert.match(pages[1],/동의 배너·거부 스위치는 구현되어 있지/);assert.match(pages[1],/백업 보유·삭제 반영기간 확정 필요/);
const index=await read('index.html'),{document:d}=parseHTML(index);
for(const id of ['intro-legal-links','settings-legal-links']){const nav=d.getElementById(id);assert(nav);assert.deepEqual([...nav.querySelectorAll('a')].map(a=>[a.textContent,a.getAttribute('href')]),[['이용약관','/terms.html'],['개인정보처리방침','/privacy.html']]);assert(!nav.querySelector('small'));}
assert.equal(addLegalLinks(index),index,'overlay idempotent');
const stripped=index.replace('  <link rel="stylesheet" href="css/legal.css">\n','').replace(/\s*<nav id="(?:intro|settings)-legal-links"[^>]*>[\s\S]*?<\/nav>/g,'');
assert.match(addLegalLinks(stripped),/intro-legal-links/);assert.throws(()=>addLegalLinks('<html></html>'));
assert.throws(()=>addLegalLinks(index.replace('id="intro-legal-links"','id="removed-nav"')));
assert.throws(()=>addLegalLinks(stripped.replace('<head>','<head><link rel="stylesheet" href="css/legal.css">')));
assert.throws(()=>addLegalLinks(index+'<nav id="intro-legal-links"></nav>'));
const css=await read('css/legal.css');assert.match(css,/font:600 16px/);assert.match(css,/flex-wrap:wrap/);assert.match(css,/focus-visible/);assert(!/@import|https?:|url\(/i.test(css));
for(const builder of ['tools/build_staging.mjs','tools/build_production_assets.mjs']){const s=await read(builder);for(const p of ['terms.html','privacy.html'])assert(s.includes("'"+p+"'"));}
for(const [flag,dir]of [['--staging-build','.staging-dist'],['--production-build','.production-dist']])if(process.argv.includes(flag))for(const p of ['terms.html','privacy.html','css/legal.css','index.html'])assert.equal(await read(dir+'/'+p),await read(p),'actual static build includes '+p);
if(process.argv.includes('--production-build')) {
 const base='b0a8dbab0f69f25b128bcf184bedcd0ffdaa271f';
 const baseline=execFileSync('git',['show',base+':index.html'],{cwd:root,encoding:'utf8'});assert.equal(index,addLegalLinks(baseline),'production index is ONLY the legal-link overlay');
 for(const p of ['js/cloud.js','js/config.js','js/main-menu.js','worker/media-range.mjs','worker/media-sizes.json','wrangler.production.jsonc'])assert.equal(await read(p),execFileSync('git',['show',base+':'+p],{cwd:root,encoding:'utf8'}),'production runtime unchanged '+p);
 const changed=execFileSync('git',['diff','--name-only',base,'--','js','css','data','img','audio','video','worker','index.html','admin.html','wrangler.production.jsonc'],{cwd:root,encoding:'utf8'}).trim().split('\n').filter(Boolean);assert(changed.every(p=>['index.html','css/legal.css'].includes(p)),'no staging game/auth/engine changes in production build');
}
console.log('Legal pages: Korean draft/placeholders, current data/analytics/share/retention gaps, statutory refund/minors, accessible link-only UI, no trackers/forms, build allowlists/idempotent isolated overlay OK');

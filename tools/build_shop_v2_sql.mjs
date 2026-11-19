// 상점 개편 SQL 운영본 생성: shop_v2_staging.sql → shop_v2_production.sql (+ 확인 SQL).
// 다른 점: DB 식별번호(운영 7692130048193495360) · 원화 '테스트 지급'은 운영에서 항상 막힘('payment not ready'). 나머지는 똑같음.
// 운영 실행은 형님 승인 후 다음 업데이트 때만. `node tools/build_shop_v2_sql.mjs` 로 재생성, `--check` 는 파일이 최신인지 확인.
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
const STAGE='7703759698107299042',PROD='7692130048193495360';
const root=new URL('../',import.meta.url),read=p=>readFile(new URL(p,root),'utf8');
export function productionSql(src){
 const krw=`'${STAGE}' /*krw*/`;
 if(src.split(krw).length!==3)throw new Error('krw markers changed');
 let s=src.replaceAll(krw,`'payment-not-ready' /*krw: 운영은 실결제(PG) 연결 전까지 원화 테스트 지급 금지*/`);
 s=s.replace(/^-- STAGING ONLY · 상점 개편[^\n]*\n/,'-- PRODUCTION (운영) · 상점 개편 (디버그 시트 68) — tools/build_shop_v2_sql.mjs 가 shop_v2_staging.sql 에서 생성. 직접 고치지 말 것.\n-- 형님 승인 후 다음 운영 업데이트 때만 실행. 원화 상품은 운영에서 구매 불가(payment not ready) — 심연석 상점·우편 확장만 동작.\n-- 운영 화면은 상점 페이지가 아직 꺼져 있음(js/shop.js 스테이징 전용). 실결제 연결 때 함께 켬.\n');
 s=s.replace(/^-- 선행 \(스테이징엔 이미 있음\)[^\n]*\n/m,'-- 선행 (운영): mail_v2 + gem·wallet·드링크 + special_summon_production. 없으면 STOP 으로 멈춤(아무것도 안 바뀜).\n');
 s=s.replace('STOP: shop v2 staging only','STOP: shop v2 production only');
 s=s.replaceAll(STAGE,PROD);
 if(s.includes(STAGE))throw new Error('staging id left');
 return s;
}
export const productionCheck=src=>src.replace(/^-- STAGING 확인[^\n]*\n/,'-- PRODUCTION 확인 (읽기 전용) · shop_v2_production.sql 적용 후 실행. ok = true 면 정상. missing 에 빠진 항목 이름이 나옴.\n');
if(process.argv[1]===fileURLToPath(import.meta.url)){
 const out={'supabase/shop_v2_production.sql':productionSql(await read('supabase/shop_v2_staging.sql')),'supabase/shop_v2_check_production.sql':productionCheck(await read('supabase/shop_v2_check_staging.sql'))};
 for(const [f,t] of Object.entries(out)){
  if(process.argv.includes('--check')){if(await read(f).catch(()=>null)!==t)throw new Error(f+' is stale: run node tools/build_shop_v2_sql.mjs');}
  else await writeFile(new URL(f,root),t);
 }
 console.log(process.argv.includes('--check')?'shop v2 production sql up to date':'shop v2 production sql written');
}

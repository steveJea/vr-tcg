import './seed_rng.mjs';   // 고정 시드 난수 (치명타·회피·속성 패시브 등 확률 결과 고정)
import fs from 'fs';
import { parseCSV, makeUnit, resolveAttack, RULES } from '../js/rules.js';
RULES.EVADE_ON = false;   // 유도 판정만 확인 (속성 회피 4~10%가 끼면 결과가 흔들림)
import { setSkillData, initPlayers, placeUnit, skillsOf, ACTIVE } from '../js/skills.js';
setSkillData(JSON.parse(fs.readFileSync('data/skills.json')), JSON.parse(fs.readFileSync('data/combos.json')));
const cards = parseCSV(fs.readFileSync('data/cards.csv','utf8')); const C = id => cards.find(c=>String(c.id)===id);
const mk=(c,uid)=>{const u=makeUnit(c,uid);u.sk=skillsOf(c.id);return u;};
const ok=(n,c)=>{console.log((c?'PASS ':'FAIL ')+n); if(!c) process.exitCode=1;};
const setup=()=>{const a={name:'A',field:[],hand:[],mana:99,hp:3000,turnsTaken:9},b={name:'B',field:[],hand:[],mana:99,hp:3000,turnsTaken:9};initPlayers(a,b);
 const yh=placeUnit(a,C('2000400088'),mk), hk=placeUnit(a,C('2000400097'),mk), other=placeUnit(a,C('2000100008'),mk);
 const m=placeUnit(b,C('1000200018'),mk), m2=placeUnit(b,C('1000100007'),mk), fem=placeUnit(b,C('2000600116'),mk); [yh,hk].forEach(u=>u.level=3); return {a,b,yh,hk,other,m,m2,fem};};
let t=setup(); ACTIVE['나 좀 내버려둬'](t.yh,t.a,t.b); ACTIVE['소녀의 거래'](t.hk,t.a,t.b);
let o=t.other.hp,y=t.yh.hp; let ev=resolveAttack(t.b,t.a,t.m,t.other);
ok('male attack on ally redirected to higher-cost 윤희, proxy hit, 윤희 unharmed', t.other.hp===o && t.yh.hp===y && ev[0].target!==t.other && t.b.field.includes(ev[0].target)||ev[0].target.hp<=0);
t.m2.canAttack=true; let h=t.a.hp; ev=resolveAttack(t.b,t.a,t.m2,null); ok('male hero attack redirected', t.a.hp===h && ev[0]?.type==='hit');
o=t.other.hp; t.fem.canAttack=true; resolveAttack(t.b,t.a,t.fem,t.other); ok('female attack not redirected', t.other.hp<o);
t=setup(); ACTIVE['나 좀 내버려둬'](t.yh,t.a,t.b); ACTIVE['소녀의 거래'](t.hk,t.a,t.b); t.yh.st.para={kind:'para',t:1};
o=t.other.hp; let k=t.hk.hp; ev=resolveAttack(t.b,t.a,t.m,t.other); ok('paralyzed 윤희 -> 혜경 takes over (proxy), other unharmed', t.other.hp===o && t.hk.hp===k);
t=setup(); o=t.other.hp; resolveAttack(t.b,t.a,t.m,t.other); ok('no cast -> no redirect', t.other.hp<o);

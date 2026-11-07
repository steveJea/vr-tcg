// UI-only selection rules. The server still validates ownership, pairs and frozen battle state.
export const WAR_DECKS = ['def1', 'def2', 'atk1', 'atk2'];
export const deckLabel = k => `${k.startsWith('def') ? '방어' : '공격'} 덱 ${k.slice(-1)}`;
export const pairedDeck = k => ({def1:'def2',def2:'def1',atk1:'atk2',atk2:'atk1'})[k];
export function deckLock(s, k, uid) {
 const roster = !!s.match?.me?.slot || s.roster?.some(r => uid && r.user_id === uid);
 if(k.startsWith('def') && roster && !['soon','signup','ended'].includes(s.phase)) return '시즌 중 방어 덱 잠김';
 if(k.startsWith('atk') && s.match && !s.match.ended && s.match.me?.atk?.[k.slice(-1)]) return '오늘 사용한 공격 덱 · HP 유지';
 return '';
}
export function pickPool(owned, selected, byId, query='', cap='', sort='power') {
 const chosen = new Set(selected), reps = new Map();
 for(const o of owned) { if(!o?.uid || !byId(o.id)) continue; const id=String(o.id), old=reps.get(id);
  if(!old || chosen.has(o.uid) || (!chosen.has(old.uid) && ((+o.power||0)>(+old.power||0) || (+o.power||0)===(+old.power||0) && (+o.level||0)>(+old.level||0)))) reps.set(id,o);
 }
 const name=o=>String(o.name||byId(o.id)?.name||o.id), cost=o=>+byId(o.id)?.cost||0, q=query.trim().toLocaleLowerCase('ko-KR');
 const max=cap===''?Infinity:Math.max(0,+cap||0);
 return [...reps.values()].filter(o=>name(o).toLocaleLowerCase('ko-KR').includes(q)&&cost(o)<=max).sort((a,b)=>(sort==='cost'?cost(a)-cost(b):sort==='level'?(+b.level||0)-(+a.level||0):sort==='name'?name(a).localeCompare(name(b),'ko'):(+b.power||0)-(+a.power||0))||name(a).localeCompare(name(b),'ko')||String(a.uid).localeCompare(String(b.uid)));
}
export function draftProblem(uids, owned, other=[]) {
 if(!uids.length || uids.length>5) return '인재 1~5명을 선택하세요';
 const by=new Map(owned.map(o=>[o.uid,o])), seen=new Set(), banned=new Set(other.map(o=>String(o.id)));
 for(const uid of uids) {const o=by.get(uid);if(!o)return '보유 인재를 다시 골라 주세요';const id=String(o.id);if(seen.has(id))return '같은 인재는 한 명만';if(banned.has(id))return '다른 덱에 사용 중인 인재예요';seen.add(id);}
 return '';
}

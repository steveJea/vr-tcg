/* mbbs.kr 공통 푸터 (독립 파일) */
(function(){
  /* ===== 사업자 정보 — 여기만 고치면 로그인 화면·로비·설정 푸터에 같이 반영됩니다. ===== */
  var COMPANY = {
    name: '엔터인코드',
    ceo: '장윤석',
    brn: '738-44-01302',
    address: '서울시 성북구 보국문로 95, 303호',
    phone: '070-5275-5361',
    /* 통신판매업신고번호: 신고증 확인 후 이 값만 바꾸면 됩니다. 빈 문자열이면 '신고 준비중'으로 표시합니다. */
    mailOrderNo: '2026-서울성북-1401'
  };
  var mailOrder = (COMPANY.mailOrderNo || '').trim() || '신고 준비중';
  if (typeof window !== 'undefined') window.VRCompany = COMPANY;

  var s=document.currentScript, cur=s.getAttribute('data-current')||'', mode=s.getAttribute('data-mode')||'flow', show=s.getAttribute('data-show');
  var games=[['tcg','Violence Royale : The Abyss Gate','https://ag.violenceroyale.com/'],['shoot','Shooting Masters','https://shoot.mbbs.kr/'],['wcup','이상형 월드컵','https://wcup.mbbs.kr/'],['battle','Battle Masters','https://battle.mbbs.kr/'],['home','Ent.INCODE','https://www.mbbs.kr/']];
  var css='#mbbs-footer{font:11px/1.55 system-ui,"Malgun Gothic","Noto Sans KR",sans-serif;color:rgba(255,255,255,.62);text-align:center;padding:8px 12px calc(8px + env(safe-area-inset-bottom));}'+
  '#mbbs-footer.mf-fixed{position:fixed;left:0;right:0;bottom:0;z-index:40;background:linear-gradient(transparent,rgba(0,0,0,.75) 45%);padding-top:22px;pointer-events:none}'+
  '#mbbs-footer.mf-fixed *{pointer-events:auto}#mbbs-footer.mf-flow{background:#111;border-top:1px solid rgba(255,255,255,.08)}'+
  '#mbbs-footer nav{display:flex;flex-wrap:wrap;justify-content:center;gap:2px 12px;margin-bottom:2px}'+
  '#mbbs-footer a{color:rgba(255,255,255,.78);text-decoration:none}#mbbs-footer a:hover{color:#fbbf24}'+
  '#mbbs-footer .mf-cur{color:#fbbf24;font-weight:700}#mbbs-footer .mf-copy{font-size:10px;opacity:.8;margin:4px 0 0}'+
  '#mbbs-footer .mf-biz{font-size:10px;line-height:1.55;opacity:.9;word-break:keep-all;margin:0 0 4px}'+
  '#mbbs-footer .mf-biz span{white-space:nowrap}#mbbs-footer .mf-biz span:not(:last-child)::after{content:" · ";white-space:pre;opacity:.7}'+
  '#mbbs-footer .mf-legal{margin:2px 0 4px}#mbbs-footer .mf-legal a{font-size:11px;text-decoration:underline;text-underline-offset:2px}'+
  '#mbbs-footer .mf-games{opacity:.85;font-size:10px}'+
  '#intro-foot,#lobby-foot{width:100%;font:10px/1.5 system-ui,"Malgun Gothic","Noto Sans KR",sans-serif;color:rgba(255,255,255,.7);text-align:center;padding:4px 10px;word-break:keep-all}'+
  '#intro-foot{position:relative;z-index:2;padding-bottom:calc(8px + env(safe-area-inset-bottom))}'+
  '#intro-foot .mf-biz,#lobby-foot .mf-biz{margin:0 0 2px}#intro-foot .mf-biz span,#lobby-foot .mf-biz span{white-space:nowrap}'+
  '#intro-foot .mf-biz span:not(:last-child)::after,#lobby-foot .mf-biz span:not(:last-child)::after{content:" · ";white-space:pre;opacity:.7}'+
  '#intro-foot .mf-legal,#lobby-foot .mf-legal{display:flex;flex-wrap:wrap;justify-content:center;gap:0 10px;margin:2px 0}'+
  '#intro-foot a,#lobby-foot a{color:rgba(255,232,180,.9);text-decoration:underline;text-underline-offset:2px}'+
  '#intro-foot .mf-copy,#lobby-foot .mf-copy{margin:2px 0 0;font-size:9px;opacity:.75}'+
  '#lobby-foot{position:absolute;left:0;right:0;bottom:calc(70px + env(safe-area-inset-bottom));z-index:25;padding:4px 10px 6px;background:linear-gradient(transparent,rgba(0,0,0,.72) 40%);pointer-events:none}'+
  '#lobby-foot *{pointer-events:auto}'+
  '@media (min-width:768px){#lobby-foot{left:50%;right:auto;transform:translateX(-50%);width:min(560px,100%);border-radius:10px 10px 0 0}}';
  var st=document.createElement('style');st.textContent=css+(s.getAttribute('data-css')||'');document.head.appendChild(st);

  function bizHtml(withGames){
    var biz='<div class="mf-biz">'+
      '<span>상호 '+COMPANY.name+'</span>'+
      '<span>대표자 '+COMPANY.ceo+'</span>'+
      '<span>사업자등록번호 '+COMPANY.brn+'</span>'+
      '<span>주소 '+COMPANY.address+'</span>'+
      '<span>전화 <a href="tel:'+COMPANY.phone+'">'+COMPANY.phone+'</a></span>'+
      '<span>통신판매업신고번호 '+mailOrder+'</span></div>';
    var legal='<nav class="mf-legal" aria-label="서비스 정책">'+
      '<a href="/terms.html" target="_blank" rel="noopener noreferrer">이용약관</a>'+
      '<a href="/privacy.html" target="_blank" rel="noopener noreferrer">개인정보처리방침</a>'+
      '<a href="/about.html" target="_blank" rel="noopener noreferrer">서비스 소개</a>'+
      '<a href="/age.html" target="_blank" rel="noopener noreferrer">연령 확인 (19+)</a></nav>';
    var copy='<div class="mf-copy">Copyright © '+new Date().getFullYear()+' <a href="https://www.mbbs.kr/">Ent.INCODE</a> All Rights Reserved.</div>';
    var nav=withGames?('<nav class="mf-games" aria-label="다른 게임">'+games.map(function(g){return g[0]===cur?'<span class="mf-cur" aria-current="page">'+g[1]+'</span>':'<a href="'+g[2]+'">'+g[1]+'</a>';}).join('')+'</nav>'):'';
    return biz+legal+nav+copy;
  }

  var f=document.createElement('footer');f.id='mbbs-footer';f.className='mf-'+mode;
  f.innerHTML=bizHtml(true);
  function vis(el){return el&&el.getClientRects().length>0&&getComputedStyle(el).visibility!=='hidden';}
  function fillSlot(id, html){
    var el=document.getElementById(id); if(!el) return;
    if(!el.getAttribute('data-filled')){ el.setAttribute('role','contentinfo'); el.setAttribute('aria-label','사업자 정보'); }
    el.innerHTML=html; el.setAttribute('data-filled','1');
  }
  function place(){
    fillSlot('intro-foot', bizHtml(false));
    fillSlot('lobby-foot', bizHtml(false));
    var intro=document.getElementById('intro');
    var introOn=intro&&!intro.classList.contains('hidden');
    var foot=document.getElementById('gm-foot');
    var lobby=document.getElementById('lobby-foot');
    if(lobby) lobby.hidden=!!introOn;
    if(foot&&f.parentNode!==foot) foot.appendChild(f);
  }
  function upd(){
    place();
    if(!show)return;
    var ok=show.split(',').some(function(q){return vis(document.querySelector(q.trim()));});
    f.style.display=ok?'':'none';
  }
  function init(){
    var foot=document.getElementById('gm-foot');
    (foot||document.body).appendChild(f);
    place();
    var intro=document.getElementById('intro');
    if(intro) new MutationObserver(upd).observe(intro,{attributes:true,attributeFilter:['class']});
    if(show){upd();new MutationObserver(upd).observe(document.body,{subtree:true,attributes:true,attributeFilter:['class','style','hidden']});}
  }
  document.readyState==='loading'?document.addEventListener('DOMContentLoaded',init):init();
})();

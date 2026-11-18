/* mbbs.kr 공통 푸터 (독립 파일) */
(function(){
  /* ===== 사업자 정보 — 여기만 고치면 로그인 화면 푸터에 반영됩니다. 설정 팝업에는 넣지 않습니다. ===== */
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

  var s=document.currentScript;
  var css='#intro-foot{width:100%;font:10px/1.5 system-ui,"Malgun Gothic","Noto Sans KR",sans-serif;color:rgba(255,255,255,.7);text-align:center;padding:4px 10px calc(8px + env(safe-area-inset-bottom));word-break:keep-all;position:relative;z-index:2}'+
  '#intro-foot .mf-biz{margin:0 0 2px}#intro-foot .mf-biz span{white-space:normal}'+
  '#intro-foot .mf-biz span:not(:last-child)::after{content:" · ";white-space:pre;opacity:.7}'+
  '#intro-foot .mf-legal{display:none}'+
  '#intro-foot a{color:rgba(255,232,180,.9);text-decoration:underline;text-underline-offset:2px}'+
  '#intro-foot .mf-copy{margin:2px 0 0;font-size:9px;opacity:.75}'+
  '@media (min-width:768px){#intro-foot .mf-biz span{white-space:nowrap}}';
  var st=document.createElement('style');st.textContent=css+(s&&s.getAttribute('data-css')||'');document.head.appendChild(st);

  function bizHtml(){
    return '<div class="mf-biz">'+
      '<span>상호 '+COMPANY.name+'</span>'+
      '<span>대표자 '+COMPANY.ceo+'</span>'+
      '<span>사업자등록번호 '+COMPANY.brn+'</span>'+
      '<span>주소 '+COMPANY.address+'</span>'+
      '<span>전화 <a href="tel:'+COMPANY.phone+'">'+COMPANY.phone+'</a></span>'+
      '<span>통신판매업신고번호 '+mailOrder+'</span></div>'+
      '<div class="mf-copy">Copyright © '+new Date().getFullYear()+' <a href="https://www.entincode.co.kr" target="_blank" rel="noopener noreferrer">Ent.INCODE</a> All Rights Reserved.</div>';
  }

  function fillSlot(id, html){
    var el=document.getElementById(id); if(!el) return;
    if(!el.getAttribute('data-filled')){ el.setAttribute('role','contentinfo'); el.setAttribute('aria-label','사업자 정보'); }
    el.innerHTML=html; el.setAttribute('data-filled','1');
  }
  function place(){
    fillSlot('intro-foot', bizHtml());
  }
  function init(){
    place();
    var intro=document.getElementById('intro');
    if(intro) new MutationObserver(place).observe(intro,{attributes:true,attributeFilter:['class']});
  }
  document.readyState==='loading'?document.addEventListener('DOMContentLoaded',init):init();
})();

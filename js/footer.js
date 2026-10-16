/* mbbs.kr 공통 푸터 (독립 파일) */
(function(){
  var s=document.currentScript, cur=s.getAttribute('data-current')||'', mode=s.getAttribute('data-mode')||'flow', show=s.getAttribute('data-show');
  var games=[['tcg','VR: Abyss Gate','https://tcg.mbbs.kr/'],['shoot','Shooting Masters','https://shoot.mbbs.kr/'],['wcup','이상형 월드컵','https://wcup.mbbs.kr/'],['battle','Battle Masters','https://battle.mbbs.kr/'],['home','mbbs.kr','https://www.mbbs.kr/']];
  var css='#mbbs-footer{font:12px/1.5 system-ui,"Malgun Gothic",sans-serif;color:rgba(255,255,255,.55);text-align:center;padding:10px 12px calc(10px + env(safe-area-inset-bottom));}'+
  '#mbbs-footer.mf-fixed{position:fixed;left:0;right:0;bottom:0;z-index:40;background:linear-gradient(transparent,rgba(0,0,0,.75) 45%);padding-top:22px;pointer-events:none}'+
  '#mbbs-footer.mf-fixed *{pointer-events:auto}#mbbs-footer.mf-flow{background:#111;border-top:1px solid rgba(255,255,255,.08)}'+
  '#mbbs-footer nav{display:flex;flex-wrap:wrap;justify-content:center;gap:4px 14px;margin-bottom:3px}'+
  '#mbbs-footer a{color:rgba(255,255,255,.75);text-decoration:none}#mbbs-footer a:hover{color:#fbbf24}'+
  '#mbbs-footer .mf-cur{color:#fbbf24;font-weight:700}#mbbs-footer .mf-copy{font-size:11px;opacity:.8}';
  var st=document.createElement('style');st.textContent=css+(s.getAttribute('data-css')||'');document.head.appendChild(st);
  var f=document.createElement('footer');f.id='mbbs-footer';f.className='mf-'+mode;
  var nav='<nav aria-label="다른 게임">'+games.map(function(g){return g[0]===cur?'<span class="mf-cur" aria-current="page">'+g[1]+'</span>':'<a href="'+g[2]+'">'+g[1]+'</a>';}).join('')+'</nav>';
  f.innerHTML=nav+'<div class="mf-copy">Copyright © '+new Date().getFullYear()+' <a href="https://www.mbbs.kr/">MBBS Inc.</a> All Rights Reserved.</div>';
  function vis(el){return el&&el.getClientRects().length>0&&getComputedStyle(el).visibility!=='hidden';}
  function upd(){if(!show)return;var ok=show.split(',').some(function(q){return vis(document.querySelector(q.trim()));});f.style.display=ok?'':'none';}
  function init(){document.body.appendChild(f);if(show){upd();new MutationObserver(upd).observe(document.body,{subtree:true,attributes:true,attributeFilter:['class','style','hidden']});}}
  document.readyState==='loading'?document.addEventListener('DOMContentLoaded',init):init();
})();

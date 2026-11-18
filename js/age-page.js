// 공개 연령 확인 페이지용. 실제 포트원/다날 연동은 계약 후 연결한다. SDK를 부르지 않는다.
(function () {
  var btn = document.getElementById('age-verify-btn');
  var msg = document.getElementById('age-verify-msg');
  if (!btn || !msg) return;
  btn.addEventListener('click', function () {
    msg.hidden = false;
    btn.setAttribute('aria-expanded', 'true');
  });
})();

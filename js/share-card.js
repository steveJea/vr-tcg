// ===== 카드 이미지 공유 (갤러리) =====
// 카드 상세를 canvas 로 PNG 로 그린 뒤, 지원하면 Web Share API(파일), 아니면 다운로드.
// 스킬 컷인 이미지는 비공개라 절대 그리지 않음: 이 파일은 프로필 이미지(bt_img) 하나만 불러옴.
(() => {
  const RC = { N: '#9ca3af', R: '#3b82f6', HR: '#22c55e', SR: '#a855f7', UR: '#f59e0b', MR: '#ef4444' };
  const W = 1080, H = 1500;
  /** 공유 이미지에 허용하는 이미지 주소인지 (프로필만). 스킬 이미지 data/fx/ 는 거부 */
  const allowedSrc = src => /\/img\/bt_img\/[^/]+\.webp$/.test(String(src)) && !/data\/fx\//.test(String(src));
  function loadImg(src) {
    return new Promise(res => {
      if (!allowedSrc(src)) return res(null);
      const im = new Image(); im.crossOrigin = 'anonymous';
      im.onload = () => res(im); im.onerror = () => res(null); im.src = src;
    });
  }
  function rr(g, x, y, w, h, r) { g.beginPath(); g.moveTo(x + r, y); g.arcTo(x + w, y, x + w, y + h, r); g.arcTo(x + w, y + h, x, y + h, r); g.arcTo(x, y + h, x, y, r); g.arcTo(x, y, x + w, y, r); g.closePath(); }
  /**
   * info: { name, short(N..MR), label, portrait, hp, atk, def, power, count, mvp, crown:{e,n}|null, first, site }
   * 반환: canvas (실패해도 이미지 없이 그림)
   */
  async function render(info) {
    const cv = document.createElement('canvas'); cv.width = W; cv.height = H;
    const g = cv.getContext('2d'), col = RC[info.short] || '#9ca3af';
    const bg = g.createLinearGradient(0, 0, 0, H); bg.addColorStop(0, '#0b1020'); bg.addColorStop(1, '#1e1b4b'); g.fillStyle = bg; g.fillRect(0, 0, W, H);
    g.lineWidth = 14; g.strokeStyle = col; rr(g, 20, 20, W - 40, H - 40, 36); g.stroke();
    // 프로필 (2:3) 영역
    const px = 150, py = 70, pw = 780, ph = 1000;
    g.save(); rr(g, px, py, pw, ph, 28); g.clip(); g.fillStyle = '#111827'; g.fillRect(px, py, pw, ph);
    const im = await loadImg(info.portrait);
    if (im) { const s = Math.max(pw / im.width, ph / im.height), iw = im.width * s, ih = im.height * s; g.drawImage(im, px + (pw - iw) / 2, py + (ph - ih) / 2, iw, ih); }
    const sh = g.createLinearGradient(0, py + ph - 260, 0, py + ph); sh.addColorStop(0, 'rgba(0,0,0,0)'); sh.addColorStop(1, 'rgba(0,0,0,.85)'); g.fillStyle = sh; g.fillRect(px, py + ph - 260, pw, 260);
    g.restore();
    g.lineWidth = 6; g.strokeStyle = col; rr(g, px, py, pw, ph, 28); g.stroke();
    // 등급 배지
    g.fillStyle = col; rr(g, px + 24, py + 24, 150, 72, 20); g.fill();
    g.fillStyle = '#fff'; g.font = '900 48px system-ui, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle'; g.fillText(info.short, px + 99, py + 62);
    if (info.crown) { g.font = '64px system-ui, sans-serif'; g.fillText('👑', px + pw - 70, py + 64); }
    // 이름 / 등급
    g.textAlign = 'left'; g.fillStyle = '#fff'; g.font = '900 76px system-ui, sans-serif'; g.fillText(String(info.name).slice(0, 14), px + 36, py + ph - 110);
    g.fillStyle = col; g.font = '700 38px system-ui, sans-serif'; g.fillText(`${info.label}${info.crown ? ` · ${info.crown.e} ${info.crown.n}` : ''}`, px + 36, py + ph - 44);
    // 스탯 줄
    const stats = [['HP', info.hp], ['ATK', info.atk], ['DEF', info.def], ['전투력', Number(info.power || 0).toLocaleString('ko-KR')]];
    const sw = (W - 120) / 4;
    stats.forEach(([k, v], i) => {
      const x = 60 + i * sw;
      g.fillStyle = 'rgba(255,255,255,.08)'; rr(g, x + 8, 1110, sw - 16, 150, 20); g.fill();
      g.textAlign = 'center'; g.fillStyle = '#cbd5e1'; g.font = '700 32px system-ui, sans-serif'; g.fillText(k, x + sw / 2, 1155);
      g.fillStyle = '#fff'; g.font = '900 52px system-ui, sans-serif'; g.fillText(String(v ?? '-'), x + sw / 2, 1215);
    });
    g.fillStyle = '#e2e8f0'; g.font = '600 34px system-ui, sans-serif'; g.textAlign = 'center';
    g.fillText(`수집 ${info.count ?? 0}회 · MVP ${info.mvp ?? 0}회${info.first ? ` · 처음 수집 ${info.first}` : ''}`, W / 2, 1320);
    g.fillStyle = '#94a3b8'; g.font = '700 34px system-ui, sans-serif'; g.fillText(`VR: Abyss Gate  ·  ${info.site || 'tcg.mbbs.kr'}`, W / 2, 1420);
    return cv;
  }
  const toBlob = cv => new Promise((res, rej) => cv.toBlob(b => b ? res(b) : rej(new Error('toBlob failed')), 'image/png'));
  const GAME_URL = 'https://tcg.mbbs.kr/';
  /** 링크 복사 (실패해도 조용히 false) */
  async function copyLink(t) { try { await navigator.clipboard.writeText(t); return true; } catch { return false; } }
  /** 공유 (가능하면 Web Share 파일 + 문구 + 게임 링크, 아니면 다운로드).
   *  일부 앱(카카오톡·인스타 등)은 파일과 함께 보낸 text/url 을 버리므로 문구 안에도 링크를 넣고, 링크는 클립보드에도 복사해 둠.
   *  반환 { r: 'shared' | 'downloaded' | 'cancelled', copied } */
  async function share(cv, fileName, text, url = GAME_URL) {
    const blob = await toBlob(cv), file = new File([blob], fileName, { type: 'image/png' });
    const body = `${text}\n${url}`;
    if (navigator.canShare && navigator.share && navigator.canShare({ files: [file] })) {
      // url 은 파일과 함께 못 받는 브라우저가 있어 text 안에만 넣고, 지원하면 url 도 함께
      const data = navigator.canShare({ files: [file], text: body, url }) ? { files: [file], title: 'VR: Abyss Gate', text: body, url } : { files: [file], title: 'VR: Abyss Gate', text: body };
      try { await navigator.share(data); return { r: 'shared', copied: await copyLink(url) }; }
      catch (e) { if (e?.name === 'AbortError') return { r: 'cancelled', copied: false }; }
    }
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = fileName;
    document.body.appendChild(a); a.click(); a.remove(); setTimeout(() => URL.revokeObjectURL(a.href), 4000);
    return { r: 'downloaded', copied: await copyLink(body) };
  }
  window.VRShareCard = { render, share, allowedSrc, GAME_URL };
})();

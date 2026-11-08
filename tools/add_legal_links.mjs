// Deterministic HTML-only overlay, usable on the deployed prod base without staging JS.
import {readFile,writeFile} from 'node:fs/promises';
import {fileURLToPath} from 'node:url';
export function addLegalLinks(html) {
  const ids=['intro-legal-links','settings-legal-links'];
  if(ids.some(id=>html.includes(`id="${id}"`))||html.includes('href="css/legal.css"')){
    if(!ids.every(id=>html.split(`id="${id}"`).length===2)||html.split('href="css/legal.css"').length!==2)throw Error('partial/duplicate policy links');
    return html;
  }
  const anchors=['<link rel="stylesheet" href="css/main-screen.css">','<div id="gm-foot" class="gm-foot"></div>'];
  if(!anchors.every(a=>html.split(a).length===2)||!/<button id="intro-guest"[^>]*>[^<]*<\/button>/.test(html))throw Error('unexpected index anchors; review before editing');
  const nav=id=>`<nav id="${id}" class="legal-links" aria-label="서비스 정책"><a href="/terms.html" target="_blank" rel="noopener noreferrer">이용약관</a><a href="/privacy.html" target="_blank" rel="noopener noreferrer">개인정보처리방침</a></nav>`;
  return html.replace(anchors[0],anchors[0]+'\n  <link rel="stylesheet" href="css/legal.css">')
    .replace(/(<button id="intro-guest"[^>]*>[^<]*<\/button>)/,'$1\n      '+nav(ids[0]))
    .replace(anchors[1],nav(ids[1])+'\n      '+anchors[1]);
}
if(process.argv[1]===fileURLToPath(import.meta.url)) {
  const path=process.argv[2]||new URL('../index.html',import.meta.url);
  const html=await readFile(path,'utf8');await writeFile(path,addLegalLinks(html));
}

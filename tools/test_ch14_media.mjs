// Exact sheet placements + media identity/encoding, without network or story/gameplay edits.
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import vm from 'node:vm';
const root=new URL('../',import.meta.url);
const context={window:{STORY_DATA:{chapters:[]}}};
vm.runInNewContext(readFileSync(new URL('js/story-data-ch14.js',root),'utf8'),context);
const chapter=context.window.STORY_DATA.chapters[0];
const manifest=JSON.parse(readFileSync(new URL('tools/ch14_media_manifest.json',root),'utf8'));
assert.equal(chapter.id,14);assert.equal(chapter.phases.length,18);assert.equal(chapter.endingVideo,'FzaL3RXwWNU');
const all=[...chapter.start,...chapter.phases.flatMap(p=>[...p.lines.default,...(p.after||[])])];
const placed=all.filter(l=>l.image||l.video);
assert.equal(placed.length,10);assert.equal(manifest.entries.length,10);
const expectedScenes=['start','4:pre','6:after','6:after','7:after','8:pre','13:pre','13:after','13:after','18:after'];
for(const [i,item] of manifest.entries.entries()) {
 assert.equal(item.n,i+1);assert.equal(item.scene,expectedScenes[i]);
 const isVideo=[2,3].includes(item.n), field=isVideo?'video':'image';
 const expected=`${isVideo?'video':'img'}/story/ch14-${String(item.n).padStart(2,'0')}.${isVideo?'mp4':'webp'}`;
 assert.equal(item.path,expected);assert.equal(placed[i][field],expected,'assets must appear in original 1–10 order');
 const [phase,where]=item.scene.split(':');
 const lines=phase==='start'?chapter.start:where==='pre'?chapter.phases[+phase-1].lines.default:chapter.phases[+phase-1].after;
 const line=lines[item.line-1];assert.equal(line.text,item.text);assert.equal(line.speaker,item.speaker);assert.equal(line[field],expected);
 const file=new URL(item.path,root);assert(existsSync(file));const bytes=readFileSync(file);
 assert.equal(bytes.length,item.bytes);assert.equal(createHash('sha256').update(bytes).digest('hex'),item.sha256);
 const info=JSON.parse(execFileSync('ffprobe',['-v','error','-show_entries','stream=codec_name,codec_type,width,height,pix_fmt:format=duration','-of','json',file.pathname],{encoding:'utf8'}));
 const video=info.streams.find(s=>s.codec_type==='video');assert(video);
 assert.equal(video.width,isVideo?752:1280);assert.equal(video.height,isVideo?416:720);
 assert.equal(video.codec_name,isVideo?'h264':'webp');
 if(isVideo) {
  assert.equal(video.pix_fmt,'yuv420p');assert.equal(info.streams.filter(s=>s.codec_type==='video').length,1,'no embedded cover-art stream');
  assert(info.streams.filter(s=>s.codec_type==='audio').every(s=>s.codec_name==='aac'));
  assert(Math.abs(+info.format.duration-item.duration)<0.01);
  assert(bytes.indexOf(Buffer.from('moov'))<bytes.indexOf(Buffer.from('mdat')),'faststart moov must precede media');
 }
}
console.log('CH14 media: ten exact sheet cues/order, paths, SHA-256 identities, CH13 image/video encoding and faststart OK');

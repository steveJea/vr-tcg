import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import vm from 'node:vm';
import {build} from 'esbuild';
import {parseHTML} from 'linkedom';
import {OAUTH_PROVIDERS,profileSeed,hasIdentity,oauthRequest,discoverKakao,cleanOAuthCallback} from '../js/auth-oauth.js';
const root = new URL('../',import.meta.url);
const source = await readFile(new URL('js/cloud.js',root),'utf8');
const html = await readFile(new URL('index.html',root),'utf8');
const bundle = (await build({stdin:{contents:source.replace('import(SDK)','Promise.resolve(window.__authSdk)'),resolveDir:new URL('js/',root).pathname},bundle:true,write:false,format:'iife',logLevel:'silent'})).outputFiles[0].text;
const tick=()=>new Promise(r=>setImmediate(r));
const plain=o=>JSON.parse(JSON.stringify(o));
function fixture({u=null,enabled=true,profiles={},authError=null,linkError=null,fetchError=false,href='https://vr-tcg-staging.notcold.workers.dev/',deferredProfile=null}={}) {
 const {window}=parseHTML(html),document=window.document;
 const location=new URL(href),calls=[],messages=[],replaces=[],timers=new Map();let seq=0,listener;
 class Storage { constructor(){this.data=new Map();} getItem(k){return this.data.get(k)??null;} setItem(k,v){this.data.set(k,String(v));} removeItem(k){this.data.delete(k);} }
 const localStorage=new Storage();localStorage.setItem('vrTcgIntroSeen','1');
 const sb={auth:{
  getSession:async()=>({data:{session:u?{user:u}:null},error:null}),
  onAuthStateChange:fn=>{listener=fn;return {data:{subscription:{unsubscribe(){}}}};},
  signInWithOAuth:async req=>{calls.push(['signInWithOAuth',plain(req)]);return {error:authError};},
  linkIdentity:async req=>{calls.push(['linkIdentity',plain(req)]);return {error:linkError};},
  signOut:async()=>{listener('SIGNED_OUT',null);return {error:null};}
 },from:table=>({
   select:()=>({eq:(key,id)=>({maybeSingle:async()=>{
     calls.push(['select',table,key,id]);
     if(table==='profiles'&&deferredProfile&&id===deferredProfile.id)return deferredProfile.promise;
     return {data:table==='profiles'?(profiles[id]??null):null,error:null};
   }})}),
   upsert:async row=>{calls.push(['upsert',table,plain(row)]);return {error:null};}
 }),rpc:async(name,args)=>{calls.push(['rpc',name,plain(args??{})]);return {data:name==='arcade_record_v5'?{wins:0,losses:0,draws:0}:null,error:null};}};
 window.__authSdk={createClient:(url,key,options)=>{calls.push(['createClient',url,key,plain(options)]);return sb;}};
 window.VRGem={toast:m=>messages.push(m)};window.VRConfirm=async()=>true;
 const context=vm.createContext({window,document,location,history:{replaceState:(...a)=>replaces.push(a)},Storage,localStorage,console,URL,URLSearchParams,AbortController,CustomEvent:window.CustomEvent,alert:m=>messages.push(m),atob,
 setTimeout:(fn,ms)=>{timers.set(++seq,{fn,ms});return seq;},clearTimeout:id=>timers.delete(id),
 fetch:async(url,options)=>{calls.push(['fetch',url,plain({headers:options.headers,cache:options.cache})]);if(fetchError)throw Error('offline');return {ok:true,json:async()=>({external:{google:true,kakao:enabled}})};}
 });
 vm.runInContext(bundle,context);
 return {window,document,calls,messages,replaces,timers,localStorage,settle:async()=>{for(let i=0;i<5;i++)await tick();},emit:(event,next)=>listener(event,next?{user:next}:null),fireTimer:ms=>{for(const[id,t]of timers)if(t.ms===ms){timers.delete(id);t.fn();}}};
}
assert.deepEqual(Object.keys(OAUTH_PROVIDERS),['google','kakao']);
for(const u of [null,{}, {email:null}, {email:''}, {email:{bad:1},user_metadata:{name:{bad:1},avatar_url:123}}, {email:'   ',user_metadata:{name:'  '}}])assert.equal(profileSeed(u).nickname,'플레이어');
assert.deepEqual(profileSeed({user_metadata:{name:' 카카오형 ',picture:'https://example.com/p.png'}}),{nickname:'카카오형',avatar_url:'https://example.com/p.png'});
assert.equal(profileSeed({user_metadata:{name:'가'.repeat(40)}}).nickname.length,20);
assert(hasIdentity({identities:[{provider:'kakao'}]},'kakao'));assert(!hasIdentity({},'kakao'));
assert.throws(()=>oauthRequest('x','https://example.com/'));
const cfg={enabled:true,supabaseUrl:'https://example.supabase.co',anonKey:'PUBLIC_ANON'};
assert.equal(await discoverKakao({...cfg,enabled:false},()=>{throw Error('must not fetch')}),false);
assert.equal(await discoverKakao(cfg,async()=>({ok:true,json:async()=>({external:{kakao:'true'}})})),false);
assert.equal(await discoverKakao(cfg,async()=>({ok:false,json:async()=>({external:{kakao:true}})})),false);
assert.equal(await discoverKakao(cfg,()=>new Promise(()=>{}),5),false,'even a fetch that ignores abort is bounded');
for(const input of ['https://example.com/?vrEnv=staging&code=secret#normal','https://example.com/?foo=1#error=access_denied&error_description=private','https://example.com/#access_token=secret&refresh_token=secret&token_type=bearer']){
 let out;const loc=new URL(input);cleanOAuthCallback(loc,{replaceState:(_a,_b,url)=>out=url});assert(out);assert.doesNotMatch(out,/secret|private|error|access_token|refresh_token/);
 if(input.includes('vrEnv'))assert.equal(out,'/?vrEnv=staging#normal');
}
for(const provider of ['google','kakao']){
 const f=fixture();await f.settle();assert(f.window.VRCloud.ready);assert.equal(f.document.getElementById('intro-login-kakao').hidden,false);
 await f.window.VRCloud.login(provider);await f.window.VRCloud.login(provider);
 const auth=f.calls.filter(c=>c[0]==='signInWithOAuth');assert.equal(auth.length,1,'PKCE double click guarded');
 assert.deepEqual(auth[0][1],{provider,options:{redirectTo:'https://vr-tcg-staging.notcold.workers.dev/'}});
 assert.equal(f.calls[0][3].auth.flowType,'pkce');
 f.fireTimer(10000);await f.window.VRCloud.login(provider);assert.equal(f.calls.filter(c=>c[0]==='signInWithOAuth').length,2,'blocked navigation can be retried');
}
for(const opts of [{enabled:false},{fetchError:true}]){
 const f=fixture(opts);await f.settle();assert.equal(f.document.getElementById('acct-login-kakao').hidden,true);assert.equal(f.document.getElementById('intro-login-kakao').hidden,true);
 await f.window.VRCloud.login('kakao');assert.equal(f.calls.filter(c=>c[0]==='signInWithOAuth').length,0);await f.window.VRCloud.login();assert.equal(f.calls.find(c=>c[0]==='signInWithOAuth')[1].provider,'google');
}
{
 const f=fixture();await f.settle();await f.window.VRCloud.login();assert(f.document.getElementById('oauth-choose'));
 f.document.querySelector('#oauth-choose [data-oauth-provider="kakao"]').click();await f.settle();assert.equal(f.calls.find(c=>c[0]==='signInWithOAuth')[1].provider,'kakao');assert(!f.document.getElementById('oauth-choose'));
}
{
 const f=fixture({authError:{code:'provider_disabled'}});await f.settle();await f.window.VRCloud.login('kakao');await f.window.VRCloud.login('google');assert.equal(f.calls.filter(c=>c[0]==='signInWithOAuth').length,2);assert.equal(f.messages.length,2);
}
{
 const f=fixture({u:{id:'missing-profile',email:'',identities:[{provider:'kakao'}]}});await f.settle();assert(f.document.getElementById('nick-ov'));assert(f.calls.some(c=>c[0]==='upsert'&&c[1]==='profiles'&&c[2].nickname==='플레이어'));
}
const kakao={id:'kakao-no-email',email:'',identities:[{provider:'kakao'}],user_metadata:{}};
{
 const f=fixture({u:kakao,profiles:{[kakao.id]:{nickname:'플레이어',nick_set:false,avatar_url:null}}});await f.settle();
 assert.equal(f.window.VRCloud.user.id,kakao.id);assert(f.document.getElementById('nick-ov'),'same first-login nickname onboarding');
 assert.equal(f.document.getElementById('main-link-kakao').hidden,true);assert.equal(f.document.getElementById('main-link-google').hidden,false);
 assert(f.calls.some(c=>c[0]==='select'&&c[1]==='profiles'&&c[3]===kakao.id));assert(!f.calls.some(c=>JSON.stringify(c).includes('"email",')),'never query identity by email');
 await f.window.VRCloud.login('google');assert(!f.calls.some(c=>c[0]==='signInWithOAuth'),'signed-in account cannot be replaced');
 await f.window.VRCloud.linkProvider('google');assert.equal(f.calls.find(c=>c[0]==='linkIdentity')[1].provider,'google');assert.equal(f.window.VRCloud.user.id,kakao.id);
}
{
 const google={id:'existing-google',email:'a@example.com',identities:[{provider:'google'}]};
 const f=fixture({u:google,profiles:{[google.id]:{nickname:'기존형',nick_set:true}}});await f.settle();await f.window.VRCloud.linkProvider('kakao');
 assert.deepEqual(f.calls.find(c=>c[0]==='linkIdentity')[1],{provider:'kakao',options:{redirectTo:'https://vr-tcg-staging.notcold.workers.dev/'}});
 assert(!f.calls.some(c=>c[0]==='signInWithOAuth'));f.emit('USER_UPDATED',{...google,identities:[...google.identities,{provider:'kakao'}]});await f.settle();assert(f.document.getElementById('main-link-kakao').hidden);assert.equal(f.window.VRCloud.user.id,google.id);
}
for(const error of [{code:'manual_linking_disabled'},{code:'identity_already_exists'}]){
 const f=fixture({u:kakao,profiles:{[kakao.id]:{nickname:'카카오형',nick_set:true}},linkError:error});await f.settle();await f.window.VRCloud.linkProvider('google');assert(f.messages.length);assert.equal(f.window.VRCloud.user.id,kakao.id);assert(!f.calls.some(c=>c[0]==='signInWithOAuth'));
}
{
 const f=fixture({u:kakao,profiles:{[kakao.id]:{nickname:'카카오형',nick_set:true}}});await f.settle();f.window.VRConfirm=async()=>false;await f.window.VRCloud.linkProvider('google');assert(!f.calls.some(c=>c[0]==='linkIdentity'));
 f.window.VRConfirm=async()=>{f.emit('SIGNED_OUT',null);await f.settle();return true;};await f.window.VRCloud.linkProvider('google');assert(!f.calls.some(c=>c[0]==='linkIdentity'),'account change during confirmation cancels linking');
}
{
 let resolve;const promise=new Promise(r=>resolve=r);const old={id:'old',identities:[{provider:'google'}]};
 const f=fixture({u:old,deferredProfile:{id:'old',promise},profiles:{[kakao.id]:{nickname:'새계정',nick_set:true}}});await f.settle();f.emit('SIGNED_IN',kakao);await f.settle();resolve({data:{nickname:'옛계정',nick_set:false},error:null});await f.settle();assert.equal(f.window.VRCloud.profile.nickname,'새계정');assert(!f.document.getElementById('nick-ov'));assert(!f.document.getElementById('acct-box').textContent.includes('옛계정'));
}
{
 const f=fixture({href:'https://vr-tcg-staging.notcold.workers.dev/?error=access_denied&error_description=PRIVATE'});await f.settle();assert(f.window.VRCloud.ready);assert(f.messages[0].includes('취소'));assert.equal(f.replaces[0][2],'/');
}
{
 const f=fixture({href:'https://unknown.example/'});await f.settle();assert.equal(f.window.VRCloud.ready,false);assert.equal(f.calls.length,0,'unregistered hostname cannot start discovery/SDK');
}
// Existing story enrollment/starter RPCs are provider agnostic and UUID-keyed.
const story=await readFile(new URL('js/story.js',root),'utf8');
assert.match(story,/story_choose_starter/);assert.match(story,/vrTcgStory\.v1/);assert.doesNotMatch(story,/user_metadata.*(?:google|kakao)|\.email/);
for(const f of ['js/story.js','js/mypage.js','js/quest.js','js/ranking.js'])assert.doesNotMatch(await readFile(new URL(f,root),'utf8'),/구글(?:로)? 로그인/,'generic entry must not force Google');
console.log('Kakao auth: provider gating, shared PKCE/redirect, no-email onboarding, secure linking, cancellation/account-switch regressions OK');

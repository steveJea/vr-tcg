import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {discoverOAuthProviders,oauthRequest,oauthFailureMessage,hasIdentity} from '../js/auth-oauth.js';

// Reuse the Kakao/X browser fixture by evaluating the same test file's patterns via a thin local fixture.
import {build} from 'esbuild';
import {parseHTML} from 'linkedom';
import vm from 'node:vm';

const root=new URL('../',import.meta.url);
const source=await readFile(new URL('js/cloud.js',root),'utf8');
const html=await readFile(new URL('index.html',root),'utf8');
const bundle=(await build({stdin:{contents:source.replace('import(SDK)','Promise.resolve(window.__authSdk)'),resolveDir:new URL('js/',root).pathname},bundle:true,write:false,format:'iife',logLevel:'silent'})).outputFiles[0].text;
const tick=()=>new Promise(r=>setImmediate(r));
const plain=o=>JSON.parse(JSON.stringify(o));
function fixture({u=null,profiles={},authError=null,linkError=null,href='https://vr-tcg-staging.notcold.workers.dev/',linkIntent=null,serverUser=u,naver=true,naverError=false,fetchError=false}={}) {
 const {window}=parseHTML(html),document=window.document;
 const location=new URL(href),calls=[],messages=[],replaces=[],timers=new Map();let seq=0,listener;
 class Storage { constructor(){this.data=new Map();} getItem(k){return this.data.get(k)??null;} setItem(k,v){this.data.set(k,String(v));} removeItem(k){this.data.delete(k);} }
 const localStorage=new Storage(),sessionStorage=new Storage();if(linkIntent)sessionStorage.setItem('vrTcgOAuthLink.v1:https://cuyqchmdcnsgzkwyclji.supabase.co',JSON.stringify({...linkIntent,startedAt:Date.now()}));localStorage.setItem('vrTcgIntroSeen','1');
 const sb={auth:{
  initialize:async()=>({error:null}),
  getUser:async()=>{calls.push(['getUser']);return {data:{user:serverUser},error:null};},
  getSession:async()=>({data:{session:u?{user:u}:null},error:null}),
  onAuthStateChange:fn=>{listener=fn;return {data:{subscription:{unsubscribe(){}}}};},
  signInWithOAuth:async req=>{calls.push(['signInWithOAuth',plain(req)]);return {error:authError};},
  linkIdentity:async req=>{calls.push(['linkIdentity',plain(req)]);return {error:linkError};},
  signOut:async()=>{listener('SIGNED_OUT',null);return {error:null};}
 },from:table=>({
   select:()=>({eq:(key,id)=>({maybeSingle:async()=>{calls.push(['select',table,key,id]);return {data:table==='profiles'?(profiles[id]??null):null,error:null};}})}),
   upsert:async row=>{calls.push(['upsert',table,plain(row)]);return {error:null};}
 }),rpc:async(name,args)=>{calls.push(['rpc',name,plain(args??{})]);return {data:name==='consent_status'?{current:true,record:{terms_version:'2026-11-draft',privacy_version:'2026-11-draft',age14:true,marketing:false,agreed_at:'2026-11-12'}}:null,error:null};}};
 window.__authSdk={createClient:(url,key,options)=>{calls.push(['createClient',url,key,plain(options)]);return sb;}};
 window.VRGem={toast:m=>messages.push(m)};window.VRConfirm=async()=>true;
 const context=vm.createContext({window,document,location,history:{replaceState:(...a)=>{replaces.push(a);location.href=new URL(a[2],location).href;}},Storage,localStorage,sessionStorage,console,URL,URLSearchParams,AbortController,CustomEvent:window.CustomEvent,alert:m=>messages.push(m),atob,
 setTimeout:(fn,ms)=>{timers.set(++seq,{fn,ms});return seq;},clearTimeout:id=>timers.delete(id),
 fetch:async(url,options)=>{
  calls.push(['fetch',url,plain({headers:options.headers,cache:options.cache})]);
  if(fetchError)throw Error('offline');
  if(url.includes('/authorize?')){
   const provider=new URL(url).searchParams.get('provider');
   if(provider==='custom:naver'){
    if(naverError)throw Error('naver probe offline');
    return {status:400,json:async()=>({error_code:'validation_failed',msg:naver?'PKCE flow requires code_challenge_method and code_challenge':'Unsupported provider: custom provider custom:naver not found'})};
   }
   return {status:400,json:async()=>({error_code:'validation_failed',msg:'Unsupported provider: provider is not enabled'})};
  }
  return {ok:true,json:async()=>({external:{google:true,kakao:true,x:false,twitter:false}})};
 }
 });
 vm.runInContext(bundle,context);
 return {window,document,calls,messages,replaces,sessionStorage,settle:async()=>{for(let i=0;i<5;i++)await tick();},emit:(event,next)=>listener(event,next?{user:next}:null)};
}

const cfg={enabled:true,supabaseUrl:'https://staging.example.supabase.co',anonKey:'PUBLIC_ONLY'};
assert.deepEqual(await discoverOAuthProviders({...cfg,enabled:false},()=>{throw Error('must not fetch')}),{google:false,kakao:false,x:null,naver:false});
{
 const calls=[];
 const value=await discoverOAuthProviders(cfg,async(url,options)=>{
  calls.push(url);assert.equal(options.redirect,'manual');assert.equal(options.credentials,'omit');
  if(url.endsWith('/settings'))return {ok:true,json:async()=>({external:{google:true,kakao:true}})};
  const u=new URL(url);assert.equal(u.searchParams.get('provider'),'custom:naver');assert.equal(u.searchParams.get('code_challenge_method'),'S256');assert(!u.searchParams.has('code_challenge'));
  return {status:400,json:async()=>({error_code:'validation_failed',msg:'PKCE flow requires code_challenge_method and code_challenge'})};
 });
 assert.deepEqual(value,{google:true,kakao:true,x:null,naver:true});
 assert.equal(calls.filter(u=>u.includes('provider=custom%3Anaver')||u.includes('provider=custom:naver')).length,1);
}
assert.equal((await discoverOAuthProviders(cfg,async url=>{
 if(url.endsWith('/settings'))return {ok:true,json:async()=>({external:{google:true,kakao:true,'custom:naver':true}})};
 throw Error('must not probe when settings lists custom:naver');
})).naver,true);
assert.equal((await discoverOAuthProviders(cfg,async url=>{
 if(url.endsWith('/settings'))return {ok:true,json:async()=>({external:{google:true,naver:false}})};
 throw Error('explicit naver false must not be probed');
})).naver,false);
assert.equal((await discoverOAuthProviders(cfg,async url=>{
 if(url.endsWith('/settings'))return {ok:true,json:async()=>({external:{google:true}})};
 return {status:400,json:async()=>({error_code:'validation_failed',msg:'Unsupported provider: custom provider custom:naver not found'})};
})).naver,false);
assert.equal(oauthRequest('custom:naver','https://example.com/').provider,'custom:naver');
assert.equal(oauthFailureMessage('identity_already_exists',{provider:'naver'}),'이미 다른 계정에 연결된 네이버 계정이에요.');
assert.equal(oauthFailureMessage('identity_already_exists',{provider:'custom:naver'}),'이미 다른 계정에 연결된 네이버 계정이에요.');
assert(hasIdentity({identities:[{provider:'custom:naver'}]},'custom:naver'));
assert(!hasIdentity({identities:[{provider:'naver'}]},'custom:naver'));

{
 const f=fixture({naver:false});await f.settle();
 assert(f.document.getElementById('intro-login-naver').hidden);
 assert.equal(f.document.getElementById('acct-login-naver'),null);
 await f.window.VRCloud.login('naver');assert(!f.calls.some(c=>c[0]==='signInWithOAuth'));
 await f.window.VRCloud.login();assert(f.document.querySelector('#oauth-choose [data-oauth-provider="naver"]').hidden);
}
{
 const f=fixture({naverError:true});await f.settle();
 assert(f.document.getElementById('intro-login-naver').hidden,'probe failure hides Naver');
}
{
 const f=fixture();await f.settle();
 assert.equal(f.document.getElementById('intro-login-naver').hidden,false);
 assert.equal(f.document.getElementById('intro-login-x').hidden,true);
 await f.window.VRCloud.login();assert(f.document.getElementById('oauth-choose'));
 f.document.querySelector('#oauth-choose [data-oauth-provider="naver"]').click();await f.settle();
 assert.deepEqual(f.calls.find(c=>c[0]==='signInWithOAuth')[1],{provider:'custom:naver',options:{redirectTo:'https://vr-tcg-staging.notcold.workers.dev/'}});
}
{
 const f=fixture();await f.settle();
 await f.window.VRCloud.login('naver');await f.window.VRCloud.login('naver');
 assert.equal(f.calls.filter(c=>c[0]==='signInWithOAuth').length,1,'PKCE double click guarded');
}
{
 const google={id:'existing-google',identities:[{provider:'google'}]};
 const f=fixture({u:google,profiles:{[google.id]:{nickname:'유지',nick_set:true}}});await f.settle();
 assert.equal(f.document.getElementById('main-link-naver').hidden,false);
 await f.window.VRCloud.linkProvider('naver');
 assert.deepEqual(f.calls.find(c=>c[0]==='linkIdentity')[1],{provider:'custom:naver',options:{redirectTo:'https://vr-tcg-staging.notcold.workers.dev/'}});
 assert.equal(JSON.parse(f.sessionStorage.getItem('vrTcgOAuthLink.v1:https://cuyqchmdcnsgzkwyclji.supabase.co')).provider,'custom:naver');
 const linked={...google,identities:[...google.identities,{provider:'custom:naver'}]};
 f.emit('USER_UPDATED',linked);await f.settle();assert(f.document.getElementById('main-link-naver').hidden);
}
{
 const google={id:'existing-google',identities:[{provider:'google'}]};
 const linked={...google,identities:[...google.identities,{provider:'custom:naver'}]};
 const back=fixture({u:google,serverUser:linked,linkIntent:{uid:google.id,provider:'custom:naver'},profiles:{[google.id]:{nickname:'유지',nick_set:true}},href:'https://vr-tcg-staging.notcold.workers.dev/?code=FAKE_NAVER_CODE'});
 await back.settle();assert.equal(back.messages[0],'네이버 계정이 연결되었어요.');assert(back.document.getElementById('main-link-naver').hidden);
 const conflict=fixture({u:google,linkIntent:{uid:google.id,provider:'custom:naver'},profiles:{[google.id]:{nickname:'유지',nick_set:true}},href:'https://vr-tcg-staging.notcold.workers.dev/#error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked+to+another+user'});
 await conflict.settle();assert.equal(conflict.messages[0],'이미 다른 계정에 연결된 네이버 계정이에요.');assert.equal(conflict.window.VRCloud.user.id,google.id);
}
{
 const naver={id:'naver-no-email',email:'',identities:[{provider:'custom:naver'}],user_metadata:{nickname:'네이버형'}};
 const f=fixture({u:naver});await f.settle();
 assert(f.document.getElementById('nick-ov'));
 assert(f.document.getElementById('main-link-naver').hidden);
 assert.equal(f.window.VRCloud.user.id,naver.id);
 await f.window.VRCloud.login('google');assert(!f.calls.some(c=>c[0]==='signInWithOAuth'),'signed-in account cannot be replaced');
}
for(const error of [{code:'identity_already_exists'},{code:'manual_linking_disabled'}]){
 const google={id:'existing-google',identities:[{provider:'google'}]};
 const f=fixture({u:google,profiles:{[google.id]:{nickname:'유지',nick_set:true}},linkError:error});await f.settle();
 await f.window.VRCloud.linkProvider('naver');assert(f.messages.length);assert.equal(f.window.VRCloud.user.id,google.id);
}

const mainMenu=await readFile(new URL('js/main-menu.js',root),'utf8');
assert.match(mainMenu,/intro-login-naver.*login\('naver'\)/);
const css=await readFile(new URL('css/main-screen.css',root),'utf8');
assert.match(css,/#main-link-naver\[hidden\]/);
assert.match(css,/\.oauth-naver[^}]*#03C75A/);
const symbol=await readFile(new URL('img/ui/naver-symbol.svg',root),'utf8');
assert.match(symbol,/developers\.naver\.com\/docs\/login\/bi/);
const fn=await readFile(new URL('supabase/functions/naver-userinfo/handler.mjs',root),'utf8');
assert.doesNotMatch(fn,/service_role|CLIENT_SECRET|eyJ[A-Za-z0-9_-]{20,}/);
const dash=await readFile(new URL('supabase/functions/naver-userinfo/dashboard_single_file.ts',root),'utf8');
assert.match(dash,/JWT verification: OFF/);
assert.match(dash,/cuyqchmdcnsgzkwyclji/);
assert.doesNotMatch(dash,/service_role|CLIENT_SECRET/);
console.log('Naver OAuth UI: discovery probe, official button, hidden when off, custom:naver identity, link/conflict OK');

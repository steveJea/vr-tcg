// Exercise the SAME auth-js version used by CDN supabase-js 2.45.4, offline.
import assert from 'node:assert/strict';
import {createRequire}from'node:module';
import {readOAuthCallback,cleanOAuthCallback,saveLinkIntent,takeLinkIntent,resolveOAuthReturn,oauthFailureMessage,oauthErrorCode}from'../js/auth-oauth.js';
const require=createRequire(import.meta.url);
assert.equal(require('@supabase/auth-js/package.json').version,'2.65.0');
const {GoTrueClient}=require('@supabase/auth-js');
const uid='11111111-1111-4111-8111-111111111111',key='FIXTURE_AUTH';
const oldUser={id:uid,identities:[{provider:'kakao'}]},linkedUser={...oldUser,identities:[...oldUser.identities,{provider:'google'}]};
const session=user=>({access_token:'FAKE_ACCESS_NOT_A_CREDENTIAL',refresh_token:'FAKE_REFRESH_NOT_A_CREDENTIAL',expires_at:Math.floor(Date.now()/1000)+3600,expires_in:3600,token_type:'bearer',user});
const conflict='https://fixture.invalid/#error=server_error&error_code=identity_already_exists&error_description=Identity+is+already+linked+to+another+user';
async function sdk(href,{sanitize=false,code=false,serverUser=oldUser,tokenError=false}={}){
 const loc=new URL(href),calls=[],values=new Map([[key,JSON.stringify(session(oldUser))]]);
 if(code)values.set(key+'-code-verifier',JSON.stringify('FAKE_VERIFIER_FOR_OFFLINE_TEST'));
 const storage={getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),removeItem:k=>values.delete(k)};
 const previous={window:globalThis.window,document:globalThis.document};
 const win={location:loc,document:{visibilityState:'hidden'},history:{state:null,replaceState:(_a,_b,url)=>{loc.href=new URL(url,loc).href;}},addEventListener(){},removeEventListener(){}};
 globalThis.window=win;globalThis.document=win.document;
 const callback=readOAuthCallback(loc);if(sanitize&&callback.failed)cleanOAuthCallback(loc,win.history);
 const client=new GoTrueClient({url:'https://fixture.invalid/auth/v1',storageKey:key,storage,persistSession:true,autoRefreshToken:false,detectSessionInUrl:true,flowType:'pkce',fetch:async(url,opts={})=>{
  calls.push({url,body:opts.body});
  if(String(url).includes('/token?grant_type=pkce'))return new Response(JSON.stringify(tokenError?{code:'bad_code_verifier',msg:'test verifier mismatch'}:session(serverUser)),{status:tokenError?400:200,headers:{'content-type':'application/json'}});
  if(String(url).endsWith('/user'))return new Response(JSON.stringify(serverUser),{status:200,headers:{'content-type':'application/json'}});
  throw Error('unexpected external request '+url);
 }});
 const initialized=await client.initialize();const {data}=await client.getSession();
 // All client I/O is complete before restoring globals.
 return {client,callback,initialized,data,calls,loc,values,close:async()=>{await new Promise(resolve=>setTimeout(resolve,0));await client.stopAutoRefresh();client.broadcastChannel?.close();globalThis.window=previous.window;globalThis.document=previous.document;}};
}
{
 const f=await sdk(conflict);assert(f.initialized.error,'old SDK rejects error-only PKCE callback');assert.equal(f.data.session,null,'baseline reproduces destructive existing-session removal');await f.close();
}
{
 const f=await sdk(conflict,{sanitize:true});assert.equal(f.initialized.error,null);assert.equal(f.data.session.user.id,uid,'error sanitizing BEFORE constructor keeps original signed-in session');
 const verdict=await resolveOAuthReturn(f.client,f.callback,{uid,provider:'google'},f.data.session.user);
 assert.equal(verdict.message,'이미 다른 계정에 연결된 구글 계정이에요.');assert.equal(verdict.user.id,uid);assert.equal(f.calls.filter(c=>c.url.includes('/token')).length,0);await f.close();
}
{
 const f=await sdk('https://fixture.invalid/?code=FAKE_CODE',{sanitize:true,code:true,serverUser:linkedUser});assert.equal(f.initialized.error,null);
 const verdict=await resolveOAuthReturn(f.client,f.callback,{uid,provider:'google'},f.data.session.user);
 assert.equal(verdict.message,'구글 계정이 연결되었어요.');assert.equal(verdict.user.id,uid);assert.equal(f.calls.filter(c=>c.url.includes('/token?grant_type=pkce')).length,1,'SDK owns exchange: no second manual exchange');assert(!f.loc.searchParams.has('code'));await f.close();
}
{
 const f=await sdk('https://fixture.invalid/?code=FAKE_CODE',{code:true,tokenError:true});assert(f.initialized.error);const verdict=await resolveOAuthReturn(f.client,f.callback,null,null,f.initialized.error);assert(verdict.message);await f.close();
}
// Old pinned JS runtime has no runtime provider-enum restriction: X keeps PKCE.
for(const provider of ['x','twitter']) {
 const f=await sdk('https://fixture.invalid/');
 const {data,error}=await f.client.signInWithOAuth({provider,options:{redirectTo:'https://fixture.invalid/',skipBrowserRedirect:true}});
 assert.equal(error,null);const url=new URL(data.url);assert.equal(url.searchParams.get('provider'),provider);assert.equal(url.searchParams.get('code_challenge_method'),'s256');assert(url.searchParams.get('code_challenge').length>=43);await f.close();
}
const memory=new Map(),storage={getItem:k=>memory.get(k),setItem:(k,v)=>memory.set(k,v),removeItem:k=>memory.delete(k)};
saveLinkIntent(storage,'staging',{uid,provider:'google'},100);assert.equal(takeLinkIntent(storage,'production',200),null);assert.deepEqual(takeLinkIntent(storage,'staging',200),{uid,provider:'google',startedAt:100});assert.equal(takeLinkIntent(storage,'staging',200),null);
saveLinkIntent(storage,'staging',{uid,provider:'google'},100);assert.equal(takeLinkIntent(storage,'staging',100+20*60*1000+1),null);assert.throws(()=>saveLinkIntent(storage,'staging',{uid,provider:'github'}));
for(const place of ['?','#']){
 const c=readOAuthCallback(new URL('https://fixture.invalid/'+place+'error_code=identity_already_exists&error_description=Identity+is+already+linked'));
 assert(c.failed);assert.equal(c.errorCode,'identity_already_exists');
}
assert.equal(oauthErrorCode({details:{code:'identity_already_exists'}}),'identity_already_exists');assert.equal(oauthErrorCode({message:'Identity is already linked to another user'}),'identity_already_exists');
assert.equal(oauthFailureMessage('manual_linking_disabled',{provider:'google'}),'계정 연결 기능이 아직 꺼져 있어요.');
assert.equal(oauthFailureMessage('access_denied',{provider:'google'}),'계정 연결을 취소했어요.');
const cb={attempted:true,failed:true,errorCode:'identity_already_exists'};
const auth=u=>({getUser:async()=>({data:{user:u},error:null})});
assert((await resolveOAuthReturn(auth(linkedUser),cb,{uid,provider:'google'},oldUser)).message.includes('연결되었어요'),'server state wins when actually linked');
assert((await resolveOAuthReturn(auth({...linkedUser,id:'different-account'}),cb,{uid,provider:'google'},oldUser)).message.includes('달라졌어요'),'other UUID can never count as link success');
const timed=await resolveOAuthReturn({getUser:()=>new Promise(()=>{})},{attempted:true}, {uid,provider:'google'},oldUser,null,5);assert(timed.retry);assert(timed.message.includes('확인하지 못'));
console.log('OAuth callback: actual pinned SDK conflict/session-loss reproduced; fixed preservation, exactly-one PKCE exchange, authoritative linked-state/UUID check, specific conflict/setting/cancel errors and deadlines OK');

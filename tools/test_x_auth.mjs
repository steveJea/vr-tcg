import assert from 'node:assert/strict';
import {discoverOAuthProviders,profileSeed,oauthRequest,oauthFailureMessage} from '../js/auth-oauth.js';
const cfg={enabled:true,supabaseUrl:'https://staging.example.supabase.co',anonKey:'PUBLIC_ONLY'};
async function discover(external,{enabled=false,error=false,status=400,msg='PKCE flow requires code_challenge_method and code_challenge'}={}) {
 const calls=[];
 const value=await discoverOAuthProviders(cfg,async(url,options)=>{
  calls.push({url,options});assert.equal(options.credentials,'omit');assert.equal(options.redirect,'manual');assert.equal(options.headers.apikey,cfg.anonKey);
  if(url.endsWith('/settings'))return {ok:true,json:async()=>({external})};
  const u=new URL(url);assert.equal(u.searchParams.get('provider'),'x');assert.equal(u.searchParams.get('code_challenge_method'),'S256');assert(!u.searchParams.has('code_challenge'),'missing challenge guarantees rejection BEFORE flow-state writes');
  assert(!u.searchParams.has('redirect_to'));assert(!u.searchParams.has('state'));if(error)throw Error('offline');
  return {status,json:async()=>({error_code:'validation_failed',msg:enabled?msg:'Unsupported provider: provider is not enabled'})};
 });return {value,calls};
}
assert.deepEqual((await discover({google:true,kakao:true,x:true,twitter:true})).value,{google:true,kakao:true,x:'x'});
assert.equal((await discover({x:true,twitter:true})).calls.length,1,'no probe when settings has authoritative x flag');
assert.equal((await discover({x:false,twitter:true},{enabled:true})).value.x,'twitter','explicit x OFF must not be probed/overridden');
assert.equal((await discover({twitter:true},{enabled:true})).value.x,'x','settings omission must not hide enabled OAuth2 X');
assert.equal((await discover({twitter:true})).value.x,'twitter');
assert.equal((await discover({twitter:true},{error:true})).value.x,null,'unknown X status must NEVER silently switch to another identity namespace');
assert.equal((await discover({google:true,kakao:true,twitter:false})).value.x,null);
assert.equal((await discover({x:'true',twitter:'true',google:1,kakao:1})).value.x,null);
for(const opts of [{status:302,enabled:true},{status:200,enabled:true},{enabled:true,msg:'Unknown error'},{enabled:false}])assert.equal((await discover({twitter:false},opts)).value.x,null,'unknown/redirect responses fail closed');
for(const opts of [{status:302,enabled:true},{status:200,enabled:true},{enabled:true,msg:'Unknown error'},{error:true}])assert.equal((await discover({twitter:true},opts)).value.x,null,'ambiguous probes cannot fall back to a different identity');
assert.deepEqual((await discover(null)).value,{google:false,kakao:false,x:null});
assert.deepEqual(await discoverOAuthProviders({...cfg,enabled:false},()=>{throw Error('must not fetch')}),{google:false,kakao:false,x:null});
assert.deepEqual(await discoverOAuthProviders(cfg,async()=>({ok:false,json:async()=>({external:{x:true}})})),{google:false,kakao:false,x:null});
assert.deepEqual(await discoverOAuthProviders(cfg,()=>new Promise(()=>{}),5),{google:false,kakao:false,x:null});
assert.deepEqual(await discoverOAuthProviders(cfg,async url=>url.endsWith('/settings')?{ok:true,json:async()=>({external:{google:true,kakao:true,twitter:true}})}:new Promise(()=>{}),5),{google:true,kakao:true,x:null},'bounded probe preserves Google/Kakao, not an ambiguous X/Twitter namespace');
assert.deepEqual(profileSeed({email:null,user_metadata:{preferred_username:'X형',picture:'https://example.com/a.png'}}),{nickname:'X형',avatar_url:'https://example.com/a.png'});
for(const provider of ['x','twitter']){assert.equal(oauthRequest(provider,'https://example.com/').provider,provider);assert.equal(oauthFailureMessage('identity_already_exists',{provider}),'이미 다른 계정에 연결된 X 계정이에요.');}
assert.throws(()=>oauthRequest('../admin','https://example.com/'));
console.log('X discovery: OAuth2 preference, v2.197 settings omission, pre-write PKCE validation-only probe, no cookies/redirects, legacy fallback, fail-closed/timeout/strict flags OK');

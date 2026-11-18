import assert from 'node:assert/strict';
import {flattenNaverProfile,createHandler,NAVER_USERINFO_URL} from '../supabase/functions/naver-userinfo/handler.mjs';

assert.equal(flattenNaverProfile(null),null);
assert.equal(flattenNaverProfile({resultcode:'00',response:{}}),null);
assert.equal(flattenNaverProfile({resultcode:'024',message:'error',response:{id:'abc'}}),null);
assert.deepEqual(flattenNaverProfile({resultcode:'00',message:'success',response:{id:'  abc123  '}}),{sub:'abc123'});
assert.deepEqual(flattenNaverProfile({resultcode:'00',response:{
  id:'abc123',name:'홍길동',nickname:'길동이',profile_image:'https://example.com/p.png',email:'user@example.com',age:'20-29'
}}),{sub:'abc123',name:'홍길동',nickname:'길동이',picture:'https://example.com/p.png'});
assert.deepEqual(flattenNaverProfile({resultcode:'00',response:{id:'abc',name:'  ',nickname:'',profile_image:null,email:'not-an-email'}}),{sub:'abc'});
{
  const profile=flattenNaverProfile({resultcode:'00',response:{id:'abc',email:'user@example.com'}});
  assert.deepEqual(profile,{sub:'abc'});
  assert.equal('email' in profile,false);
  assert.equal('email_verified' in profile,false);
  assert(!JSON.stringify(profile).includes('@'),'must not invent a placeholder email');
}
assert.equal(flattenNaverProfile({resultcode:'00',response:{id:0}}).sub,'0');

const calls=[];
const handler=createHandler({timeout:20,fetchImpl:async(url,options)=>{
  calls.push({url,authorization:options.headers.Authorization,redirect:options.redirect});
  assert.equal(url,NAVER_USERINFO_URL);
  assert.equal(options.redirect,'error');
  if(options.headers.Authorization==='Bearer timeout')return new Promise(()=>{});
  if(options.headers.Authorization==='Bearer deny')return {ok:false,status:401,json:async()=>({resultcode:'024'})};
  if(options.headers.Authorization==='Bearer badjson')return {ok:true,status:200,json:async()=>{throw Error('no json')}};
  if(options.headers.Authorization==='Bearer empty')return {ok:true,status:200,json:async()=>({resultcode:'00',response:{}})};
  return {ok:true,status:200,json:async()=>({resultcode:'00',message:'success',response:{id:'id1',nickname:'닉'}})};
}});

const json=async res=>({status:res.status,body:await res.json()});
assert.equal((await handler(new Request('https://example.com/',{method:'OPTIONS'}))).status,204);
assert.deepEqual(await json(await handler(new Request('https://example.com/',{method:'PUT'}))),{status:405,body:{error:'Method not allowed'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/'))),{status:401,body:{error:'Missing Authorization header'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/',{headers:{Authorization:'Bearer'}}))),{status:401,body:{error:'Missing Authorization header'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/',{headers:{Authorization:'Bearer deny'}}))),{status:401,body:{error:'Failed to fetch user info from Naver'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/',{headers:{Authorization:'Bearer badjson'}}))),{status:502,body:{error:'Invalid Naver profile'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/',{headers:{Authorization:'Bearer empty'}}))),{status:502,body:{error:'Invalid Naver profile'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/',{method:'POST',headers:{Authorization:'Bearer ok'}}))),{status:200,body:{sub:'id1',nickname:'닉'}});
assert.deepEqual(await json(await handler(new Request('https://example.com/',{headers:{Authorization:'Bearer timeout'}}))),{status:502,body:{error:'Failed to fetch user info from Naver'}});
assert.equal(calls[0].authorization,'Bearer deny');
assert(!JSON.stringify(calls).includes('secret'),'handler must not be given a reason to echo tokens in tests either');
console.log('Naver userinfo proxy: flatten, auth header, Naver errors, timeout, no secrets OK');

const http=require('http'),crypto=require('crypto'),{execFileSync}=require('child_process');
// Servidor de teste: imita a API de login do Supabase (/auth/v1) e repassa /rest/v1 ao PostgREST.
// Só para testes locais. Aceita as senhas gravadas na coluna auth.users.senha.
const SECRET="super-secret-jwt-token-with-at-least-32-characters-long";
const b64=o=>Buffer.from(typeof o==='string'?o:JSON.stringify(o)).toString('base64url');
const sign=p=>{const h=b64({alg:'HS256',typ:'JWT'}),b=b64(p);return h+'.'+b+'.'+crypto.createHmac('sha256',SECRET).update(h+'.'+b).digest('base64url')};
const verify=t=>{try{const[h,b,s]=t.split('.');if(crypto.createHmac('sha256',SECRET).update(h+'.'+b).digest('base64url')!==s)return null;const p=JSON.parse(Buffer.from(b,'base64url'));return p.exp&&p.exp<Date.now()/1000?null:p}catch{return null}};
const PSQL=process.env.PSQL||'psql';
const psql=sql=>execFileSync(PSQL,['-h','127.0.0.1','-p',process.env.PGPORT||'5544','-U','postgres','-d','t','-tAF','|','-c',sql]).toString().trim();
const userObj=r=>({id:r[0],aud:'authenticated',role:'authenticated',email:r[1],email_confirmed_at:'2026-01-01T00:00:00Z',app_metadata:{provider:'email'},user_metadata:{nome:r[2]},created_at:'2026-01-01T00:00:00Z'});
const find=email=>{const o=psql(`select id,email,coalesce(raw_user_meta_data->>'nome',''),senha from auth.users where email='${email.replace(/'/g,'')}'`);return o?o.split('|'):null};
const session=r=>{const now=Math.floor(Date.now()/1000);const at=sign({sub:r[0],email:r[1],role:'authenticated',aud:'authenticated',iat:now,exp:now+3600});return{access_token:at,token_type:'bearer',expires_in:3600,expires_at:now+3600,refresh_token:b64({sub:r[0]}),user:userObj(r)}};
const send=(res,c,o)=>{res.writeHead(c,{'content-type':'application/json'});res.end(JSON.stringify(o))};
http.createServer((req,res)=>{
 res.setHeader('access-control-allow-origin',req.headers.origin||'*');res.setHeader('access-control-allow-headers','*');res.setHeader('access-control-allow-methods','*');res.setHeader('access-control-expose-headers','*');
 if(req.method==='OPTIONS'){res.writeHead(204);return res.end()}
 const u=new URL(req.url,'http://x');
 if(u.pathname.startsWith('/auth/v1/')){
  let body='';req.on('data',d=>body+=d);req.on('end',()=>{
   const j=body?JSON.parse(body):{};const p=u.pathname.slice(9);
   if(p==='token'&&u.searchParams.get('grant_type')==='password'){const r=find(j.email||'');if(!r||r[3]!==j.password)return send(res,400,{error:'invalid_grant',error_description:'Invalid login credentials',msg:'Invalid login credentials',code:400});return send(res,200,session(r))}
   if(p==='token'&&u.searchParams.get('grant_type')==='refresh_token'){try{const id=JSON.parse(Buffer.from(j.refresh_token,'base64url')).sub;const o=psql(`select id,email,coalesce(raw_user_meta_data->>'nome',''),senha from auth.users where id='${id}'`).split('|');return send(res,200,session(o))}catch{return send(res,400,{error:'invalid_grant'})}}
   if(p==='user'){const t=(req.headers.authorization||'').replace('Bearer ','');const c=verify(t);if(!c)return send(res,401,{msg:'invalid JWT',code:401});const o=psql(`select id,email,coalesce(raw_user_meta_data->>'nome',''),senha from auth.users where id='${c.sub}'`).split('|');return send(res,200,userObj(o))}
   if(p==='logout'){res.writeHead(204);return res.end()}
   if(p==='signup'){if(find(j.email))return send(res,422,{msg:'User already registered',code:422});const nome=(j.data&&j.data.nome)||'';psql(`insert into auth.users(email,raw_user_meta_data,senha) values ('${j.email.replace(/'/g,'')}','${JSON.stringify({nome}).replace(/'/g,'')}','${(j.password||'').replace(/'/g,'')}')`);const r=find(j.email);return send(res,200,session(r))}
   send(res,404,{msg:'nao implementado '+p});
  });return}
 if(u.pathname.startsWith('/rest/v1/')){
  const pr=http.request({host:'127.0.0.1',port:3300,path:req.url.replace('/rest/v1',''),method:req.method,headers:{...req.headers,host:'127.0.0.1:3300'}},r=>{res.writeHead(r.statusCode,r.headers);r.pipe(res)});
  pr.on('error',e=>send(res,502,{msg:String(e)}));req.pipe(pr);return}
 send(res,404,{});
}).listen(54321,()=>console.log('proxy ok'));

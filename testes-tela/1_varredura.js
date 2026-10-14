const L=require('./lib');
(async()=>{const b=await L.launch();
const menus={ 'admin@x.com':['/','/movimentar','/transferencias','/solicitacoes','/dedicados','/historico','/cadastros','/usuarios'],
 'nl@x.com':['/','/movimentar','/transferencias','/solicitacoes','/dedicados','/historico'],
 'tec@x.com':['/transferencias','/solicitacoes'],
 'cons@x.com':['/','/transferencias','/solicitacoes','/dedicados','/historico','/movimentar'],
 'ag@x.com':['/','/transferencias','/solicitacoes','/dedicados','/historico','/movimentar']};
for(const [email,paths] of Object.entries(menus)){const p=await L.novo(b);await L.login(p,email);
 const menu=await p.locator('nav a, header a').allInnerTexts();
 console.log('\n== '+email+' menu: '+menu.join(' | '));
 for(const path of paths){const e=await L.nav(p,path);L.log(!e&&!p.errs.length,email+' '+path+(e?' ERRO: '+e:'')+(p.errs.length?' '+p.errs.join(';'):''));}
 await p.context().close();}
// técnico não acessa Estoque, Registrar, Dedicados nem Histórico: volta para Transferências
{const p=await L.novo(b);await L.login(p,'tec@x.com');
 for(const path of ['/','/movimentar','/dedicados','/historico']){await L.nav(p,path);L.log(p.url().endsWith('/transferencias'),'tec@x.com '+path+' redireciona para /transferencias');}
 L.log(!(await p.locator('header nav').innerText()).match(/Estoque|Registrar|Dedicados|Hist/),'menu do técnico só tem Transferências e Solicitações');
 await p.context().close();}
await b.close()})().catch(e=>{console.error(e);process.exit(1)});

const H=require('./h');const {L,sql,busca,check,msgForm}=H;
(async()=>{const b=await L.launch();
const p=await L.novo(b);await L.login(p,'admin@x.com');await L.nav(p,'/movimentar');
const f=p.locator('form').first();
await f.getByLabel('Tipo').selectOption('ENTRADA_COMPRA');await f.getByLabel('Local').selectOption({label:'Nova Lima'});
const antes=sql("select count(*) from movimentacao");
await f.getByRole('button',{name:'Registrar'}).click();await p.waitForTimeout(800);
check(sql("select count(*) from movimentacao")===antes,'X1 enviar sem escolher item não registra nada (validação do campo Item)');
// busca: acentos e dropdown fecha
const inp=f.getByPlaceholder('Digite para buscar o item');await inp.click();await inp.fill('camera');
const ops=await p.locator('ul li').allInnerTexts();check(ops.length>0&&ops.every(o=>/c[aâ]mera|cam/i.test(o)),'X2 busca "camera" (sem acento) acha itens: '+ops.slice(0,3).join(', '));
check([...ops].map(o=>o.toLowerCase()).join()===[...ops].map(o=>o.toLowerCase()).sort((a,b)=>a.localeCompare(b,'pt-BR')).join(),'X3 opções em ordem alfabética');
await p.keyboard.press('Escape');
// mobile
const m=await b.newContext({viewport:{width:390,height:800}});const mp=await m.newPage();mp.errs=[];await L.login(mp,'admin@x.com');await L.nav(mp,'/movimentar');
await mp.screenshot({path:'d_mobile_registrar.png',fullPage:true});
const w=await mp.evaluate(()=>document.documentElement.scrollWidth);check(w<=392,'X4 Registrar no celular sem rolagem horizontal (largura '+w+')');
await L.nav(mp,'/');const w2=await mp.evaluate(()=>document.documentElement.scrollWidth);console.log('   largura /estoque no celular:',w2);
await b.close()})().catch(e=>{console.error(e);process.exit(1)});

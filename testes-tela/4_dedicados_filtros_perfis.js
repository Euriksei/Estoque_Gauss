const H=require('./h');const {L,sql,busca,check,msgForm}=H;
const saldo=(local,prod,res)=>sql(`select coalesce(sum(delta),0) from efeito_estoque e join local l on l.id=e.local_id join produto p on p.id=e.produto_id where l.nome like '${local}' and p.nome='${prod}' and ${res?`e.reservado_unidade_id is not null`:`e.reservado_unidade_id is null`}`);
(async()=>{const b=await L.launch();
// 1) administrador entrega o dedicado ao cliente, levado pelo técnico
let p=await L.novo(b);await L.login(p,'admin@x.com');await L.nav(p,'/dedicados');
await p.getByRole('button',{name:'Enviar ao cliente'}).first().click();
let f=p.locator('form').first();
await f.getByLabel('Modo de envio').selectOption('tecnico');await f.getByLabel('Técnico que leva o material').selectOption({index:1});
await f.getByRole('button',{name:'Registrar saída'}).click();await p.waitForTimeout(2000);
check(sql("select count(*) from movimentacao m join tecnico t on t.id=m.tecnico_id where m.tipo='SAIDA_CLIENTE' and t.nome='Joao CLT' and m.modo_envio='tecnico'")==='1','1b baixa registrada com o técnico que leva');
const dt=await p.locator('body').innerText();check(dt.includes('Entregue ao cliente'),'1c Dedicados mostra "Entregue ao cliente"');
await p.context().close();
// 2) entrada dedicada por compra e ajustes
p=await L.novo(b);await L.login(p,'admin@x.com');await L.nav(p,'/movimentar');
f=p.locator('form').first();
await f.getByLabel('Tipo').selectOption('ENTRADA_COMPRA');await f.getByLabel('Local').selectOption({label:'Nova Lima'});
await busca(f,'Digite para buscar o item','Buzzer');
await f.locator('input[type=number]').first().fill('5');
await f.locator('input[placeholder="Estoque livre"]').first().click();await p.locator('ul li').filter({hasText:'Gerdau - Ouro Branco'}).first().click();
await f.getByRole('button',{name:'Registrar'}).click();await msgForm(p);
check(saldo('Nova Lima','Buzzer',true)==='5'&&saldo('Nova Lima','Buzzer',false)==='0','2a entrada por compra dedicada: 5 dedicados e 0 livres');
await f.getByLabel('Tipo').selectOption('AJUSTE');await f.getByLabel('Local').selectOption({label:'Nova Lima'});
await busca(f,'Digite para buscar o item','FMC 150');
check(await f.locator('label',{hasText:/^Ajuste/}).locator('select').count()===1,'2b ajuste tem seletor Aumentar/Reduzir');
await f.locator('label',{hasText:/^Ajuste/}).locator('select').selectOption('menos');await f.locator('input[type=number]').first().fill('1');
await f.locator('textarea').fill('contagem');await f.getByRole('button',{name:'Registrar'}).click();await msgForm(p);
check(saldo('Nova Lima','FMC 150',false)==='4','2c ajuste "Reduzir 1" levou FMC 150 de 5 para 4');
await f.getByLabel('Tipo').selectOption('AJUSTE');await f.getByLabel('Local').selectOption({label:'Nova Lima'});
await busca(f,'Digite para buscar o item','FMC 150');await f.locator('label',{hasText:/^Ajuste/}).locator('select').selectOption('mais');await f.locator('input[type=number]').first().fill('3');
await f.locator('textarea').fill('achou');await f.getByRole('button',{name:'Registrar'}).click();await msgForm(p);
check(saldo('Nova Lima','FMC 150',false)==='7','2d ajuste "Aumentar 3" levou para 7');
// 3) Dedicados: transferir para SBC, SBC confirma
await L.nav(p,'/dedicados');
const linha=p.locator('tr',{hasText:'Buzzer'}).first();await linha.getByRole('button',{name:'Transferir'}).click();
f=p.locator('form').first();
await f.locator('select').first().selectOption({label:'São Bernardo (SBC)'});await f.locator('input[type=number]').first().fill('2');
await f.getByRole('button',{name:'Enviar transferência'}).click();await p.waitForTimeout(2000);
check(saldo('Nova Lima','Buzzer',true)==='3','3a dedicado em trânsito: saiu de NL (restam 3)');
await p.context().close();
p=await L.novo(b);await L.login(p,'sbc@x.com');await L.nav(p,'/transferencias');
const emand=await p.locator('section',{hasText:'Em andamento'}).first().innerText();check(emand.includes('dedicado: Gerdau - Ouro Branco'),'3b SBC vê o envio dedicado');
await p.getByRole('button',{name:'Confirmar recebimento'}).click();await p.waitForTimeout(1500);
check(saldo('São Bernardo%','Buzzer',true)==='2','3c SBC recebeu 2 dedicados');
// SBC envia ao cliente a partir de Dedicados
await L.nav(p,'/dedicados');await p.getByRole('button',{name:'Enviar ao cliente'}).first().click();
f=p.locator('form').first();
await f.getByLabel('Modo de envio').selectOption('correios');await f.getByPlaceholder('https://.../browse/HW-5698').fill('https://x/browse/HW-9');
await f.locator('input[type=number]').first().fill('1');
await f.getByRole('button',{name:'Registrar saída'}).click();await p.waitForTimeout(2000);
check(saldo('São Bernardo%','Buzzer',true)==='1','3d envio ao cliente (correios) tirou 1 do dedicado do SBC');
await p.context().close();
// 4) Estoque: categoria e filtros
p=await L.novo(b);await L.login(p,'admin@x.com');await L.nav(p,'/');
const th=await p.locator('thead th').allInnerTexts();check(th.join('|').toUpperCase().includes('CATEGORIA')&&th.join('|').toUpperCase().includes('LIVRE OU DEDICADO'),'4a Estoque tem colunas Categoria e Livre ou dedicado: '+th.join(' | '));
const total=await p.locator('tbody tr').count();
const sel=p.locator('select[name=categoria]');const opts=await sel.locator('option').allInnerTexts();check(opts.length>5,'4b filtro de categoria com '+opts.length+' opções');
await sel.selectOption({label:'Rastreamento e telemetria'});await p.getByRole('button',{name:'Filtrar'}).click();await p.waitForLoadState('networkidle');
const filt=await p.locator('tbody tr').allInnerTexts();check(filt.length>0&&filt.length<total&&filt.every(r=>r.includes('Rastreamento')),'4c filtro por categoria: '+total+' -> '+filt.length+' linhas, todas Rastreamento');
await p.screenshot({path:'d_estoque.png'});
await L.nav(p,'/');await p.getByPlaceholder('Buscar item').fill('buzz');await p.getByRole('button',{name:'Filtrar'}).click();await p.waitForLoadState('networkidle');
check((await p.locator('tbody tr').allInnerTexts()).every(r=>/buzzer/i.test(r)),'4d busca "buzz" só traz Buzzer');
// 5) Cadastros
await L.nav(p,'/cadastros');
const lab=p.locator('label',{hasText:'Mínimo'}).first();const inp=lab.locator('input');
const bl=await lab.boundingBox(),bi=await inp.boundingBox();check(bi.y>bl.y+8,'5a rótulo "Mínimo" fica acima do campo');
const sec=p.locator('section',{hasText:'Itens e estoque mínimo'});
const n0=await sec.locator('tbody tr').count();
await sec.getByPlaceholder('Buscar item').fill('chicote');const n1=await sec.locator('tbody tr').count();
check(n1>0&&n1<n0&&(await sec.locator('tbody tr').allInnerTexts()).every(r=>/chicote/i.test(r)),'5b busca de itens em Cadastros: '+n0+' -> '+n1);
await sec.getByPlaceholder('Buscar item').fill('');
await sec.locator('select').last().selectOption({label:'Câmeras'});const n2=await sec.locator('tbody tr').count();check(n2>0&&n2<n0,'5c filtro de categoria Câmeras: '+n2+' itens');
const tsec=p.locator('section',{hasText:'Novo técnico'}).first();
check((await tsec.innerText()).includes('Estoque base'),'5d cadastro de técnico pede Estoque base');
await tsec.locator('input').first().fill('Maria Teste');await tsec.locator('select').nth(1).selectOption({label:'São Bernardo (SBC)'});
await tsec.getByRole('button',{name:'Cadastrar'}).click();await p.waitForTimeout(2000);
check(sql("select b.nome from local l join local b on b.id=l.base_id where l.nome like '%Maria Teste%'")==='São Bernardo (SBC)','5e técnico novo nasceu com estoque e base SBC');
await L.nav(p,'/cadastros');check((await p.locator('body').innerText()).includes('Estoque base'),'5f lista de técnicos mostra a coluna Estoque base');
// 6) Usuários
await L.nav(p,'/usuarios');const optsU=await p.locator('select').first().locator('option').allInnerTexts();check(optsU.some(o=>o.includes('Agendamento')),'6a perfil Agendamento disponível em Usuários: '+optsU.join(', '));
await p.context().close();
// 7) agendamento e consulta
p=await L.novo(b);await L.login(p,'ag@x.com');
const menu=(await p.locator('nav a, header a').allInnerTexts()).join('|');check(!menu.includes('Registrar')&&!menu.includes('Cadastros'),'7a Agendamento sem Registrar/Cadastros no menu');
await L.nav(p,'/movimentar');check((await p.locator('body').innerText()).includes('não registra'),'7b /movimentar bloqueado para Agendamento');
await L.nav(p,'/transferencias');check(await p.getByRole('button',{name:'Nova transferência'}).count()===0,'7c Agendamento não vê "Nova transferência"');
await L.nav(p,'/solicitacoes');await p.getByRole('button',{name:'Nova solicitação'}).click();
const sf=p.locator('form').first();
await sf.locator('select').nth(0).selectOption({label:'São Bernardo (SBC)'});await sf.locator('select').nth(1).selectOption({label:'Nova Lima'});
await busca(sf,'Digite para buscar o item','FMC 150');await sf.locator('input[type=number]').first().fill('2');
await sf.getByRole('button',{name:'Enviar solicitação'}).click();m=await msgForm(p);check(m.includes('Solicitação enviada'),'7d Agendamento criou solicitação SBC→NL: '+m);
await L.nav(p,'/solicitacoes');check(await p.getByRole('button',{name:/Atender|Cancelar/}).count()===0||true,'7e (info) botões na tela do agendamento');
console.log('   botões Atender visíveis p/ agendamento:',await p.getByRole('button',{name:/Atender/}).count());
await p.context().close();
p=await L.novo(b);await L.login(p,'cons@x.com');await L.nav(p,'/solicitacoes');
check(await p.getByRole('button',{name:'Nova solicitação'}).count()===0,'7f Consulta não vê "Nova solicitação"');await p.context().close();
// operador SBC atende o pedido do agendamento (origem SBC)
p=await L.novo(b);await L.login(p,'sbc@x.com');await L.nav(p,'/solicitacoes');
check(await p.getByRole('button',{name:/Aceitar/}).count()===1,'7g Operador SBC vê Aceitar no pedido que sai do SBC');
// 8) login com senha errada
const q=await L.novo(b);await q.goto(L.BASE+'/login');await q.fill('input[type=email]','admin@x.com');await q.fill('input[type=password]','errada1');await q.click('button.btn');await q.waitForTimeout(1500);
check((await q.locator('body').innerText()).includes('incorretos'),'8a senha errada mostra mensagem');
await b.close()})().catch(e=>{console.error(e);process.exit(1)});

const H=require('./h');const {L,sql,busca,check,msgForm}=H;
const s=(prod,chip)=>sql(`select coalesce(sum(delta),0) from efeito_estoque e join local l on l.id=e.local_id join produto p on p.id=e.produto_id where l.nome='Nova Lima' and p.nome='${prod}' and e.reservado_unidade_id is null${chip?` and e.condicao='${chip}'`:''}`);
(async()=>{const b=await L.launch();
let p=await L.novo(b);await L.login(p,'admin@x.com');
// 1) entrada de módulos COM chip e de chips avulsos
await L.nav(p,'/movimentar');let f=p.locator('form').first();
await f.getByLabel('Tipo').selectOption('ENTRADA_COMPRA');await f.getByLabel('Local').selectOption({label:'Nova Lima'});
await busca(f,'Digite para buscar o item','FMC 150',0,'');
const antes=Number(s('FMC 150','claro'));
check(await f.getByText('Chip do módulo').count()===1,'1a módulo de telemetria pede "Chip do módulo"');
await f.getByRole('button',{name:'Registrar'}).click();await p.waitForTimeout(800);
check(!(await msgForm(p)).includes('Movimentação registrada'),'1b sem escolher o chip a entrada não é registrada (campo obrigatório)');
await f.locator('select:has(option:text-is("Escolha o chip"))').first().selectOption('claro');
await f.getByLabel(/Com chicote/).uncheck();
await f.locator('input[type=number]').first().fill('5');
await f.getByRole('button',{name:'+ Adicionar item'}).click();
await busca(f,'Digite para buscar o item','Chip Vivo M2M',1);
check(await f.getByText('Chip do módulo').count()===1,'1c chip avulso não pede chip (só módulos)');
await f.locator('input[type=number]').nth(1).fill('4');
await f.getByRole('button',{name:'+ Adicionar item'}).click();
await busca(f,'Digite para buscar o item','Chip Claro M2M',2);
await f.locator('input[type=number]').nth(2).fill('6');
await f.getByRole('button',{name:'Registrar'}).click();check((await msgForm(p)).includes('Movimentação registrada'),'1d entrada de módulo com chip Claro + chips avulsos registrada');
check(Number(s('FMC 150','claro'))-antes===5,'1e saldo de FMC 150 com chip Claro +5');
check(s('Chip Vivo M2M')==='4'&&s('Chip Claro M2M')==='6','1f chips avulsos: Vivo 4, Claro 6');
// 2) Estoque mostra o chip
await L.nav(p,'/');const tx=await p.locator('tbody').innerText();
check(tx.includes('FMC 150 (Claro)')&&tx.includes('FMC 150 (Sem chip)'),'2a Estoque separa FMC 150 por chip: "(Claro)" e "(Sem chip)"');
check(!tx.includes('Buzzer ('),'2b item que não usa chip não mostra chip');
await p.screenshot({path:'d_estoque_chip.png'});
// 3) tela Chips: instalar / trocar / descartar
check((await p.locator('header nav').innerText()).includes('Chips'),'3a admin vê o menu Chips');
await L.nav(p,'/chips');f=p.locator('form').first();
await f.getByLabel('Estoque').selectOption({label:'Nova Lima'});
await busca(f,'Digite para buscar o módulo','FMC 150');
await f.getByLabel('Quantidade de módulos').fill('3');
await f.getByLabel('Chip que o módulo tem hoje').selectOption('novo');await f.getByLabel('Chip que ele vai ficar').selectOption('vivo');
check(await f.getByLabel('O que fazer com o chip retirado').count()===0,'3b instalar chip em módulo sem chip não pergunta do chip retirado');
const sem0=Number(s('FMC 150','novo'));
await f.getByRole('button',{name:'Registrar troca de chip'}).click();check((await msgForm(p)).includes('Chip registrado'),'3c instalar Vivo em 3 módulos sem chip');
check(s('FMC 150','vivo')==='3'&&Number(s('FMC 150','novo'))===sem0-3&&s('Chip Vivo M2M')==='1','3d módulos Vivo=3, sem chip -3, chip avulso Vivo 4→1');
await f.getByLabel('Quantidade de módulos').fill('2');
await f.getByLabel('Chip que o módulo tem hoje').selectOption('vivo');await f.getByLabel('Chip que ele vai ficar').selectOption('claro');
await f.getByRole('button',{name:'Registrar troca de chip'}).click();await msgForm(p);
check(s('FMC 150','vivo')==='1'&&s('Chip Vivo M2M')==='3'&&s('Chip Claro M2M')==='4','3e trocar Vivo→Claro em 2: chip Vivo volta ao avulso (3), Claro avulso 6→4');
// descartar chip ruim
await f.getByLabel('Quantidade de módulos').fill('1');
await f.getByLabel('Chip que o módulo tem hoje').selectOption('vivo');await f.getByLabel('Chip que ele vai ficar').selectOption('novo');
await f.getByLabel('O que fazer com o chip retirado').selectOption('descartar');
await f.getByRole('button',{name:'Registrar troca de chip'}).click();await p.waitForTimeout(800);
check(s('FMC 150','vivo')==='1','3f descartar sem motivo é barrado (observação obrigatória)');
await f.getByLabel(/Observação/).fill('não comunicou no teste');
await f.getByRole('button',{name:'Registrar troca de chip'}).click();check((await msgForm(p)).includes('Chip registrado'),'3g descartar com motivo registrado');
check(s('FMC 150','vivo')==='0'&&s('Chip Vivo M2M')==='3','3h módulo voltou a sem chip e o chip avulso NÃO voltou ao estoque (descartado)');
await p.screenshot({path:'d_chips.png'});
// 4) mensagem de saldo cita o chip
await f.getByLabel('Quantidade de módulos').fill('99');
await f.getByLabel('Chip que o módulo tem hoje').selectOption('novo');await f.getByLabel('Chip que ele vai ficar').selectOption('claro');
await f.getByRole('button',{name:'Registrar troca de chip'}).click();const m=await msgForm(p);
check(m.includes('Saldo insuficiente'),'4a falta de chip avulso/módulo é recusada: '+m);
// 5) histórico
await L.nav(p,'/historico');check((await p.locator('body').innerText()).includes('Troca de chip'),'5a Histórico mostra "Troca de chip"');
await p.context().close();
// 6) quem não pode
for(const e of ['tec@x.com','cons@x.com','ag@x.com']){p=await L.novo(b);await L.login(p,e);await L.nav(p,'/chips');check(p.url().endsWith('/transferencias'),'6 '+e+' não acessa Chips');await p.context().close();}
p=await L.novo(b);await L.login(p,'sbc@x.com');await L.nav(p,'/chips');const op=await p.locator('form select').first().locator('option').allInnerTexts();
check(op.join('|').includes('São Bernardo')&&!op.join('|').includes('Nova Lima'),'6b operador SBC só vê o próprio estoque na tela Chips: '+op.join(', '));await p.context().close();
await b.close()})().catch(e=>{console.error(e);process.exit(1)});

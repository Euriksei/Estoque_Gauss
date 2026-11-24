// Tela Registrar: operador de um local só (local travado), "Disponível" por item + chip nas saídas,
// saída acima do saldo barrada na tela sem gravar nada, saída no limite registrada.
const H=require('./h');const {L,sql,busca,check}=H;
const PROD='Módulo FMC 650';
const s=chip=>Number(sql(`select coalesce(sum(delta),0) from efeito_estoque e join local l on l.id=e.local_id join produto p on p.id=e.produto_id where l.nome='Nova Lima' and p.nome='${PROD}' and e.reservado_unidade_id is null and e.condicao='${chip}'`));
const nMov=()=>sql('select count(*) from movimentacao');
const msg=async p=>{await p.waitForTimeout(1500);return (await p.locator('form p.text-sm.text-green-700, form p.text-sm.text-marca-700').allInnerTexts()).join(' / ')};
const disp=async(f,i=0)=>{const d=f.locator('p[data-disponivel]').nth(i);return {n:Number(await d.getAttribute('data-disponivel')),t:await d.innerText(),cls:await d.getAttribute('class')}};
(async()=>{const b=await L.launch();
// 0) admin põe FMC 650 com chip Vivo (3) e Claro (2) em Nova Lima
let p=await L.novo(b);await L.login(p,'admin@x.com');await L.nav(p,'/movimentar');let f=p.locator('form').first();
await f.getByLabel('Tipo').selectOption('ENTRADA_COMPRA');await f.getByLabel('Local').selectOption({label:'Nova Lima'});
// sem chicote: assim só sobram os campos de quantidade das linhas (o de chicote some)
const semChicote=async()=>{for(const c of await f.getByLabel(/Com chicote/).all())await c.uncheck();};
await busca(f,'Digite para buscar o item',PROD,0,'vivo');await semChicote();await f.locator('input[type=number]').first().fill('3');
await f.getByRole('button',{name:'+ Adicionar item'}).click();
await busca(f,'Digite para buscar o item',PROD,1,'claro');await semChicote();await f.locator('input[type=number]').nth(1).fill('2');
await f.getByRole('button',{name:'Registrar'}).click();check((await msg(p)).includes('Movimentação registrada'),'S0 entrada de FMC 650 Vivo 3 + Claro 2 em Nova Lima');
await p.context().close();
const vivo=s('vivo'),claro=s('claro');
check(vivo>=3&&claro>=2&&vivo!==claro,`S0b saldo livre em Nova Lima: Vivo ${vivo}, Claro ${claro}`);
// 1) operador de um local só: local já escolhido e travado
p=await L.novo(b);await L.login(p,'nl@x.com');await L.nav(p,'/movimentar');f=p.locator('form').first();
const loc=f.getByLabel('Local');const ops=await loc.locator('option').allInnerTexts();
check(await loc.isDisabled()&&ops.length===1&&ops[0]==='Nova Lima'&&(await loc.inputValue())!=='','S1 operador de 1 local vê só Nova Lima, já selecionado e travado: '+ops.join(', '));
// 2) Disponível por chip numa saída
await f.getByLabel('Tipo').selectOption('CONSUMO_INTERNO');
await busca(f,'Digite para buscar o item',PROD,0,'vivo');
let d=await disp(f);check(d.n===vivo&&d.t.includes('Disponível: '+vivo),`S2 Disponível do FMC 650 Vivo = ${vivo} (tela: ${d.t})`);
const chipSel=f.locator('select:has(option:text-is("Escolha o chip"))').first();
await chipSel.selectOption('claro');d=await disp(f);check(d.n===claro,`S3 trocando o chip para Claro o Disponível vira ${claro} (tela: ${d.t})`);
await chipSel.selectOption('vivo');
// 3) acima do saldo: linha vermelha e Registrar barrado sem gravar nada
const mov0=nMov();
await f.locator('input[type=number]').first().fill(String(vivo+2));d=await disp(f);
check(d.cls.includes('text-marca-700')&&d.t.includes('passa do disponível'),'S4 quantidade acima do disponível deixa a linha em vermelho: '+d.t);
await f.getByRole('button',{name:'Registrar'}).click();let m=await msg(p);
const esperado=`Só há ${vivo} ${PROD} (Vivo) livre(s) em Nova Lima (você está tirando ${vivo+2}).`;
check(m.includes(esperado),'S5 Registrar barrado com a mensagem do saldo: '+m);
check(nMov()===mov0&&s('vivo')===vivo,'S6 nada foi gravado (movimentações e saldo iguais)');
// 3b) duas linhas do mesmo item/chip somam
await f.locator('input[type=number]').first().fill(String(vivo));
await f.getByRole('button',{name:'+ Adicionar item'}).click();
await busca(f,'Digite para buscar o item',PROD,1,'vivo');await f.locator('input[type=number]').nth(1).fill('1');
await f.getByRole('button',{name:'Registrar'}).click();m=await msg(p);
check(m.includes(`(você está tirando ${vivo+1})`)&&nMov()===mov0,'S7 duas linhas do mesmo módulo/chip somam e passam do saldo: barrado: '+m);
await f.getByRole('button',{name:'Tirar'}).nth(1).click();
// 4) no limite passa
d=await disp(f);check(!d.cls.includes('text-marca-700'),'S8 quantidade igual ao disponível não fica vermelha: '+d.t);
await f.getByRole('button',{name:'Registrar'}).click();m=await msg(p);
check(m.includes('Movimentação registrada')&&s('vivo')===0&&s('claro')===claro,`S9 saída no limite (${vivo}) registrada: Vivo 0, Claro continua ${claro}: `+m);
if(p.errs.length)console.log('   erros na página: '+p.errs.join(' | '));
await p.context().close();
await b.close()})().catch(e=>{console.error(e);process.exit(1)});

const L=require('./lib');const {execFileSync}=require('child_process');
exports.L=L;
exports.sql=q=>execFileSync(process.env.PSQL||'psql',['-h','127.0.0.1','-p',process.env.PGPORT||'5544','-U','postgres','-d','t','-tAF','|','-c',q]).toString().trim();
// escolhe uma opção num campo Busca (pelo placeholder) dentro de um escopo
exports.busca=async(scope,placeholder,texto,idx=0,chip='novo')=>{const inp=scope.locator(`input[placeholder="${placeholder}"]`).nth(idx);await inp.click();await inp.fill(texto);await scope.page().locator('ul li').filter({hasText:texto}).first().click();
 // módulos de telemetria pedem a escolha do chip; por padrão os testes antigos usam "Sem chip"
 const sels=scope.locator('select:has(option:text-is("Escolha o chip"))');for(let k=0;k<await sels.count();k++){if(!(await sels.nth(k).inputValue()))await sels.nth(k).selectOption(chip);}};
exports.check=(ok,msg)=>{L.log(ok,msg);if(!ok)process.exitCode=1;return ok};
exports.msgForm=async p=>{await p.waitForTimeout(1500);return (await p.locator('form p.text-green-700, form p.text-marca-700').allInnerTexts()).join(' / ')};

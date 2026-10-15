const { chromium } = require('playwright-core');
const BASE=process.env.APP_URL||'http://127.0.0.1:3100';
exports.BASE=BASE;
exports.launch=async()=>chromium.launch({executablePath:process.env.CHROMIUM||undefined,args:['--no-sandbox']});
exports.novo=async(b)=>{const c=await b.newContext({viewport:{width:1280,height:900}});const p=await c.newPage();p.errs=[];p.on('pageerror',e=>p.errs.push('pageerror: '+e.message));p.on('console',m=>{if(m.type()==='error'&&!m.text().includes('Failed to fetch RSC payload'))p.errs.push('console: '+m.text().slice(0,200))});p.on('dialog',d=>d.accept());return p};
exports.login=async(p,email)=>{await p.goto(BASE+'/login');await p.fill('input[type=email]',email);await p.fill('input[type=password]','teste123');await p.click('button.btn');await p.waitForURL(u=>!u.pathname.startsWith('/login'),{timeout:15000})};
exports.erroTela=async p=>{const t=await p.locator('body').innerText();if(/Unhandled Runtime Error|Application error|Internal Server Error|This page could not be found/.test(t))return t.slice(0,300);return null};
exports.nav=async(p,path)=>{p.errs.length=0;await p.goto(BASE+path,{waitUntil:'networkidle'});return exports.erroTela(p)};
exports.log=(ok,msg)=>{if(!ok)process.exitCode=1;console.log((ok?'✔ ':'✘ ')+msg)};

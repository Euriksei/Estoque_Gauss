"use client";
import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useRef, useState } from "react";
import { supabaseBrowser } from "@/lib/supabase/client";

// Engrenagem do topo (Configurações): abre um menu com o nome e o perfil no topo, "Mudar senha",
// "Ver como" (só administrador de verdade) e, por último e separado, "Sair". Funciona por teclado:
// Enter/Espaço/seta para baixo abre e foca o primeiro item, setas para cima/baixo andam entre os itens,
// Esc fecha e devolve o foco ao botão. "Ver como" só aparece para quem é administrador de verdade.
export function ConfigMenu({ verComo = false, quem }: { verComo?: boolean; quem: string }) {
  const router = useRouter();
  const [aberto, setAberto] = useState(false);
  const caixa = useRef<HTMLDivElement>(null);
  const botao = useRef<HTMLButtonElement>(null);
  const primeiro = useRef<HTMLAnchorElement>(null);

  useEffect(() => {
    if (!aberto) return;
    primeiro.current?.focus();
    const fora = (e: MouseEvent) => { if (!caixa.current?.contains(e.target as Node)) setAberto(false); };
    document.addEventListener("mousedown", fora);
    return () => document.removeEventListener("mousedown", fora);
  }, [aberto]);

  const fechar = () => { setAberto(false); botao.current?.focus(); };

  return (
    <div ref={caixa} className="relative" onKeyDown={(e) => {
      if (e.key === "Escape" && aberto) { e.preventDefault(); fechar(); return; }
      if (aberto && (e.key === "ArrowDown" || e.key === "ArrowUp") && e.target !== botao.current) {
        const itens = [...(caixa.current?.querySelectorAll<HTMLElement>('[role="menuitem"]') ?? [])];
        const i = itens.indexOf(document.activeElement as HTMLElement);
        e.preventDefault();
        itens[(i + (e.key === "ArrowDown" ? 1 : itens.length - 1)) % itens.length]?.focus();
      }
    }}
      onBlur={(e) => { if (!caixa.current?.contains(e.relatedTarget as Node)) setAberto(false); }}>
      <button ref={botao} type="button" aria-label="Configurações" title="Configurações" aria-haspopup="menu" aria-expanded={aberto} aria-controls="menu-config"
        onClick={() => setAberto(!aberto)} onKeyDown={(e) => { if (e.key === "ArrowDown") { e.preventDefault(); setAberto(true); } }}
        className="rounded-lg border border-white/25 p-1.5 text-white transition hover:bg-white/10 focus:outline-none focus-visible:ring-2 focus-visible:ring-white/60">
        <svg aria-hidden="true" viewBox="0 0 24 24" className="h-5 w-5" fill="none" stroke="currentColor" strokeWidth={1.8} strokeLinecap="round" strokeLinejoin="round">
          <path d="M10.3 4.3c.4-1.8 3-1.8 3.4 0a1.7 1.7 0 0 0 2.6 1.1c1.6-1 3.4.8 2.4 2.4a1.7 1.7 0 0 0 1.1 2.6c1.8.4 1.8 3 0 3.4a1.7 1.7 0 0 0-1.1 2.6c1 1.6-.8 3.4-2.4 2.4a1.7 1.7 0 0 0-2.6 1.1c-.4 1.8-3 1.8-3.4 0a1.7 1.7 0 0 0-2.6-1.1c-1.6 1-3.4-.8-2.4-2.4a1.7 1.7 0 0 0-1.1-2.6c-1.8-.4-1.8-3 0-3.4a1.7 1.7 0 0 0 1.1-2.6c-1-1.6.8-3.4 2.4-2.4a1.7 1.7 0 0 0 2.6-1.1Z" />
          <circle cx="12" cy="12" r="3" />
        </svg>
      </button>
      {aberto && (
        <div id="menu-config" role="menu" aria-label="Configurações" className="absolute right-0 z-20 mt-2 w-56 rounded-lg border border-slate-200 bg-white py-1 text-sm shadow-lg">
          <p className="truncate border-b border-slate-100 px-3 pb-2 pt-1 text-xs text-slate-500" title={quem}>{quem}</p>
          <Link ref={primeiro} role="menuitem" href="/senha" onClick={() => setAberto(false)}
            className="block px-3 py-2 text-slate-700 hover:bg-slate-100 focus:bg-slate-100 focus:outline-none">
            Mudar senha
          </Link>
          {verComo && (
            <Link role="menuitem" href="/ver-como" onClick={() => setAberto(false)}
              className="block px-3 py-2 text-slate-700 hover:bg-slate-100 focus:bg-slate-100 focus:outline-none">
              Ver como
            </Link>
          )}
          <button role="menuitem" type="button" className="mt-1 block w-full border-t border-slate-100 px-3 py-2 text-left text-slate-700 hover:bg-slate-100 focus:bg-slate-100 focus:outline-none"
            onClick={async () => { setAberto(false); await supabaseBrowser().auth.signOut(); router.push("/login"); router.refresh(); }}>
            Sair
          </button>
        </div>
      )}
    </div>
  );
}

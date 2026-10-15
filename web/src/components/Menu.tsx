"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";

export function Menu({ itens }: { itens: { href: string; nome: string }[] }) {
  const caminho = usePathname();
  // Destaca a aba assim que é clicada, sem esperar a página nova carregar.
  const [clicado, setClicado] = useState<string | null>(null);
  useEffect(() => setClicado(null), [caminho]);
  const atual = clicado ?? caminho;
  return (
    <nav className="flex flex-wrap gap-1 text-sm">
      {itens.map((m) => {
        const ativo = m.href === "/" ? atual === "/" : atual.startsWith(m.href);
        return (
          <Link
            key={m.href}
            href={m.href}
            onClick={() => setClicado(m.href)}
            className={`rounded-lg px-3 py-1.5 font-medium transition ${ativo ? "bg-marca-600 text-white" : "text-slate-300 hover:bg-white/10 hover:text-white"}`}
          >
            {m.nome}
          </Link>
        );
      })}
    </nav>
  );
}

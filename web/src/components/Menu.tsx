"use client";
import Link from "next/link";
import { usePathname } from "next/navigation";

export function Menu({ itens }: { itens: { href: string; nome: string }[] }) {
  const atual = usePathname();
  return (
    <nav className="flex flex-wrap gap-1 text-sm">
      {itens.map((m) => {
        const ativo = m.href === "/" ? atual === "/" : atual.startsWith(m.href);
        return (
          <Link
            key={m.href}
            href={m.href}
            className={`rounded-lg px-3 py-1.5 font-medium transition ${ativo ? "bg-marca-600 text-white" : "text-slate-300 hover:bg-white/10 hover:text-white"}`}
          >
            {m.nome}
          </Link>
        );
      })}
    </nav>
  );
}

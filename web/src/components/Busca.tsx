"use client";
import { useEffect, useMemo, useRef, useState } from "react";

export type Opcao = { value: number; label: string };

const norm = (t: string) => t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();

// Seletor com busca: lista em ordem alfabética e filtra enquanto se digita (ignora acentos e maiúsculas).
export function Busca({ opcoes, value, onChange, placeholder = "Digite para buscar", vazio, required }: {
  opcoes: Opcao[]; value: number | ""; onChange: (v: number | "") => void;
  placeholder?: string; vazio?: string; required?: boolean; // vazio: texto da opção "nenhum" (ex.: "Estoque livre")
}) {
  const ordenadas = useMemo(() => [...opcoes].sort((a, b) => a.label.localeCompare(b.label, "pt-BR", { sensitivity: "base" })), [opcoes]);
  const atual = ordenadas.find((o) => o.value === value);
  const [aberto, setAberto] = useState(false);
  const [texto, setTexto] = useState("");
  const raiz = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const fora = (e: MouseEvent) => { if (!raiz.current?.contains(e.target as Node)) setAberto(false); };
    document.addEventListener("mousedown", fora);
    return () => document.removeEventListener("mousedown", fora);
  }, []);

  const filtradas = ordenadas.filter((o) => norm(o.label).includes(norm(texto)));
  const escolher = (v: number | "") => { onChange(v); setAberto(false); setTexto(""); };

  return (
    <div ref={raiz} className="relative">
      <input className="campo" value={aberto ? texto : atual?.label ?? (value === "" ? vazio ?? "" : "")}
        placeholder={placeholder} autoComplete="off"
        onFocus={() => { setAberto(true); setTexto(""); }}
        onChange={(e) => { setTexto(e.target.value); setAberto(true); }}
        onKeyDown={(e) => {
          if (e.key === "Escape") setAberto(false);
          if (e.key === "Enter" && aberto) { e.preventDefault(); if (filtradas[0]) escolher(filtradas[0].value); }
        }} />
      {required && <input tabIndex={-1} aria-hidden required value={value} onChange={() => {}} className="pointer-events-none absolute inset-0 opacity-0" />}
      {aberto && (
        <ul className="absolute z-20 mt-1 max-h-60 w-full overflow-auto rounded border border-slate-300 bg-white text-sm shadow">
          {vazio && <li className="cursor-pointer px-2 py-1 text-slate-500 hover:bg-slate-100" onMouseDown={() => escolher("")}>{vazio}</li>}
          {filtradas.map((o) => (
            <li key={o.value} className={`cursor-pointer px-2 py-1 hover:bg-slate-100 ${o.value === value ? "bg-slate-50 font-medium" : ""}`} onMouseDown={() => escolher(o.value)}>{o.label}</li>
          ))}
          {filtradas.length === 0 && <li className="px-2 py-1 text-slate-500">Nada encontrado</li>}
        </ul>
      )}
    </div>
  );
}

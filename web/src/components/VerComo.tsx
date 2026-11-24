"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { PERFIS, VINCULOS, type Perfil, type Tecnico } from "@/lib/types";

// Aplica (ou desfaz, com perfil null) o "Ver como" e recarrega o app com os menus e telas do perfil efetivo.
async function aplicar(router: ReturnType<typeof useRouter>, p: { perfil: Perfil | null; local_id?: number | null; tecnico_id?: number | null }) {
  const { error } = await supabaseBrowser().rpc("definir_visualizacao", { p });
  if (error) return error.message;
  router.push("/");
  router.refresh();
  return "";
}

// Formulário do administrador: perfil, estoque fixo (operador, agendamento, consulta) e técnico (perfil Técnico).
export function VerComoForm({ estoques, tecnicos, atual }: {
  estoques: { id: number; nome: string }[]; tecnicos: (Tecnico & { carro: string })[];
  atual: { perfil: Perfil; local_id: number | null; tecnico_id: number | null };
}) {
  const router = useRouter();
  const [perfil, setPerfil] = useState<Perfil>(atual.perfil);
  const [local, setLocal] = useState<number | "">(atual.local_id ?? "");
  const [tecnico, setTecnico] = useState<number | "">(atual.tecnico_id ?? "");
  const [erro, setErro] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const pedeLocal = perfil === "operador" || perfil === "agendamento" || perfil === "consulta";

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setErro("");
    const msg = await aplicar(router, perfil === "admin" ? { perfil: null }
      : { perfil, local_id: pedeLocal ? local || null : null, tecnico_id: perfil === "tecnico" ? tecnico || null : null });
    setOcupado(false);
    setErro(msg);
  }

  return (
    <form onSubmit={enviar} className="card max-w-xl space-y-3">
      <label className="block text-sm">Perfil
        <select className="campo mt-1" value={perfil} onChange={(e) => setPerfil(e.target.value as Perfil)}>
          {(Object.keys(PERFIS) as Perfil[]).map((p) => <option key={p} value={p}>{PERFIS[p]}</option>)}
        </select>
      </label>
      {pedeLocal && (
        <label className="block text-sm">Estoque fixo{perfil === "consulta" ? " (opcional, só informativo)" : ""}
          <select className="campo mt-1" value={local} onChange={(e) => setLocal(e.target.value ? Number(e.target.value) : "")} required={perfil !== "consulta"}>
            <option value="">{perfil === "consulta" ? "Nenhum" : "Selecione"}</option>
            {estoques.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
      )}
      {perfil === "tecnico" && (
        <label className="block text-sm">Técnico
          <select className="campo mt-1" value={tecnico} onChange={(e) => setTecnico(e.target.value ? Number(e.target.value) : "")} required>
            <option value="">Selecione</option>
            {tecnicos.map((t) => <option key={t.id} value={t.id}>{t.nome} ({VINCULOS[t.vinculo]}) · {t.carro}</option>)}
          </select>
          <span className="mt-1 block text-xs text-slate-500">Só aparecem técnicos com estoque (carro). A base é a do carro dele.</span>
        </label>
      )}
      <p className="text-xs text-slate-500">Você passa a ter exatamente os acessos desse perfil, no banco e nas telas. Para voltar, use &quot;Voltar a administrador&quot; na faixa do topo.</p>
      {erro && <p className="text-sm text-marca-700">{erro}</p>}
      <button className="btn" disabled={ocupado}>{perfil === "admin" ? "Voltar a administrador" : "Ver como este perfil"}</button>
    </form>
  );
}

// Faixa do topo enquanto o administrador simula outro perfil (aparece em todas as telas, inclusive para técnico).
export function FaixaVerComo({ texto }: { texto: string }) {
  const router = useRouter();
  const [erro, setErro] = useState("");
  const [ocupado, setOcupado] = useState(false);
  return (
    <div role="status" className="bg-amber-400 text-marinho-950">
      <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-3 gap-y-1 px-4 py-1.5 text-sm">
        <span className="font-medium">{texto}</span>
        <button type="button" className="rounded-lg border border-marinho-950/40 bg-white/70 px-3 py-1 text-sm font-medium hover:bg-white" disabled={ocupado}
          onClick={async () => { setOcupado(true); setErro(await aplicar(router, { perfil: null })); setOcupado(false); }}>
          Voltar a administrador
        </button>
        {erro && <span className="text-xs text-marca-700">{erro}</span>}
      </div>
    </div>
  );
}

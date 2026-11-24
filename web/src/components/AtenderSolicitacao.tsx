"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { CHIPS, MODOS, MODOS_COM_RASTREIO, VINCULOS, hojeSP, type Tecnico } from "@/lib/types";

// Atender um pedido (atender_solicitacao). O que se pede depende do tipo:
//  - "transferencia": preparar e enviar (data, meio, rastreio, prazo de chegada) -> transferência em trânsito;
//  - "cliente": enviar ao cliente (data, meio, técnico, rastreio) -> saída para cliente na hora;
//  - "chegada": retirar dedicado chegou (data) -> devolução de cliente já dedicada.
// Módulos do pedido sem chip definido pedem o chip (chave = solicitacao_item.id).
export function AtenderSolicitacao({ id, tipo, modulos, tecnicos = [] }: {
  id: number; tipo: "transferencia" | "cliente" | "chegada"; modulos: { id: number; nome: string }[]; tecnicos?: Tecnico[];
}) {
  const router = useRouter();
  const [aberto, setAberto] = useState(false);
  const [data, setData] = useState(hojeSP);
  const [modo, setModo] = useState("");
  const [tecnicoId, setTecnicoId] = useState<number | "">("");
  const [rastreio, setRastreio] = useState("");
  const [prazo, setPrazo] = useState("");
  const [obs, setObs] = useState("");
  const [chips, setChips] = useState<Record<string, string>>({});
  const [erro, setErro] = useState("");
  const [ocupado, setOcupado] = useState(false);
  const rotulo = tipo === "transferencia" ? "Preparar e enviar" : tipo === "cliente" ? "Enviar ao cliente" : "Registrar chegada";

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setErro("");
    const p = tipo === "chegada"
      ? { data, observacao: obs, chips }
      : { data, modo_envio: modo, codigo_rastreio: rastreio, observacao: obs, chips,
          ...(tipo === "transferencia" ? { prazo_chegada: prazo } : { tecnico_id: modo === "tecnico" ? tecnicoId || null : null }) };
    const { error } = await supabaseBrowser().rpc("atender_solicitacao", { p_id: id, p });
    setOcupado(false);
    if (error) return setErro(error.message);
    setAberto(false);
    router.refresh();
  }

  if (!aberto) return <button type="button" className="btn" onClick={() => setAberto(true)}>{rotulo}</button>;
  return (
    <form onSubmit={enviar} className="grid gap-2 rounded border border-slate-200 p-3 sm:grid-cols-4">
      <label className="text-xs">{tipo === "chegada" ? "Data da chegada" : "Data de envio"}
        <input type="date" className="campo" value={data} max={hojeSP()} onChange={(e) => setData(e.target.value)} required />
      </label>
      {tipo !== "chegada" && (
        <label className="text-xs">Meio de envio
          <select className="campo" value={modo} onChange={(e) => { setModo(e.target.value); setTecnicoId(""); }} required>
            <option value="">Selecione</option>
            {Object.entries(MODOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
          </select>
        </label>
      )}
      {tipo === "cliente" && modo === "tecnico" && (
        <label className="text-xs sm:col-span-2">Técnico que leva o material
          <select className="campo" value={tecnicoId} onChange={(e) => setTecnicoId(e.target.value ? Number(e.target.value) : "")} required>
            <option value="">Selecione</option>
            {tecnicos.map((t) => <option key={t.id} value={t.id}>{t.nome} ({VINCULOS[t.vinculo]})</option>)}
          </select>
        </label>
      )}
      {tipo !== "chegada" && MODOS_COM_RASTREIO.includes(modo) && (
        <label className="text-xs">Código de rastreio
          <input className="campo" value={rastreio} onChange={(e) => setRastreio(e.target.value)} />
        </label>
      )}
      {tipo === "transferencia" && (
        <label className="text-xs">Prazo de chegada
          <input type="date" className="campo" value={prazo} onChange={(e) => setPrazo(e.target.value)} />
        </label>
      )}
      {modulos.map((m) => (
        <label key={m.id} className="text-xs sm:col-span-2">Chip de {m.nome}
          <select className="campo" value={chips[m.id] ?? ""} onChange={(e) => setChips({ ...chips, [m.id]: e.target.value })} required>
            <option value="">Escolha o chip</option>
            {Object.entries(CHIPS).map(([v, n]) => <option key={v} value={v}>{n}</option>)}
          </select>
        </label>
      ))}
      <label className="text-xs sm:col-span-4">Observação
        <input className="campo" value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      <div className="flex flex-wrap items-center gap-2 sm:col-span-4">
        <button className="btn" disabled={ocupado}>{rotulo}</button>
        <button type="button" className="btn-sec" onClick={() => setAberto(false)}>Fechar</button>
        {erro && <span className="text-xs text-marca-700">{erro}</span>}
      </div>
    </form>
  );
}

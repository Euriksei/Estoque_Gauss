"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { MODOS, MODOS_COM_RASTREIO, VINCULOS, type Local, type Tecnico } from "@/lib/types";

type Props = {
  unidadeId: number; produtoId: number; chip: string; localId: number; max: number;
  destinos: Local[]; tecnicos: Tecnico[]; ehTecnico: boolean; podeTransferir: boolean;
};

// Único lugar onde um item dedicado é movimentado: transferir para outro estoque ou enviar ao cliente.
export function DedicadoAcoes({ unidadeId, produtoId, chip, localId, max, destinos, tecnicos, ehTecnico, podeTransferir }: Props) {
  const router = useRouter();
  const [aberto, setAberto] = useState<"" | "transferir" | "cliente">("");
  const [qtd, setQtd] = useState(max);
  const [destino, setDestino] = useState<number | "">("");
  const [modo, setModo] = useState("");
  const [tecnicoId, setTecnicoId] = useState<number | "">("");
  const [rastreio, setRastreio] = useState("");
  const [prazo, setPrazo] = useState("");
  const [chamado, setChamado] = useState("");
  const [finalidade, setFinalidade] = useState("");
  const [msg, setMsg] = useState("");
  const [ocupado, setOcupado] = useState(false);

  const item = [{ produto_id: produtoId, quantidade: qtd, reservado_unidade_id: unidadeId, condicao: chip }];
  const hoje = new Date().toISOString().slice(0, 10);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setMsg("");
    const sb = supabaseBrowser();
    const { error } = aberto === "transferir"
      ? await sb.rpc("criar_transferencia", { p: { origem_id: localId, destino_id: destino, data: hoje, modo_envio: modo, codigo_rastreio: rastreio, prazo_chegada: prazo, itens: item } })
      : await sb.rpc("registrar_movimentacao", { p: { tipo: "SAIDA_CLIENTE", local_id: localId, unidade_id: unidadeId, data: hoje, finalidade, chamado_url: chamado, modo_envio: modo, codigo_rastreio: rastreio, tecnico_id: tecnicoId || null, itens: item } });
    setOcupado(false);
    if (error) return setMsg(error.message);
    setAberto("");
    router.refresh();
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        {podeTransferir && <button type="button" className="btn-sec" onClick={() => setAberto(aberto === "transferir" ? "" : "transferir")}>Transferir</button>}
        <button type="button" className="btn-sec" onClick={() => setAberto(aberto === "cliente" ? "" : "cliente")}>Enviar ao cliente</button>
      </div>
      {aberto && (
        <form onSubmit={enviar} className="grid gap-2 rounded border border-slate-200 p-3 sm:grid-cols-4">
          <label className="text-xs">Quantidade (máx. {max})
            <input type="number" className="campo" min={1} max={max} value={qtd} onChange={(e) => setQtd(Number(e.target.value))} required />
          </label>
          {aberto === "transferir" && (
            <label className="text-xs sm:col-span-2">Para o estoque
              <select className="campo" value={destino} onChange={(e) => setDestino(Number(e.target.value))} required>
                <option value="">Selecione</option>
                {destinos.filter((l) => l.id !== localId).map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
              </select>
            </label>
          )}
          {aberto === "cliente" && (
            <label className="text-xs">Finalidade
              <select className="campo" value={finalidade} onChange={(e) => setFinalidade(e.target.value)}>
                <option value="">-</option><option value="mobilizacao">Mobilização</option><option value="manutencao">Manutenção</option>
              </select>
            </label>
          )}
          {aberto === "cliente" && ehTecnico && <p className="text-xs text-slate-600 sm:col-span-4">Envio por técnico: você é registrado como o técnico que levou o material.</p>}
          {!(aberto === "cliente" && ehTecnico) && (
            <label className="text-xs">{aberto === "cliente" ? "Modo de envio" : "Meio de envio"}
              <select className="campo" value={modo} onChange={(e) => { setModo(e.target.value); setTecnicoId(""); }} required={aberto === "cliente"}>
                <option value="">{aberto === "cliente" ? "Selecione" : "-"}</option>
                {Object.entries(MODOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
              </select>
            </label>
          )}
          {aberto === "cliente" && !ehTecnico && modo === "tecnico" && (
            <label className="text-xs sm:col-span-2">Técnico que leva o material
              <select className="campo" value={tecnicoId} onChange={(e) => setTecnicoId(Number(e.target.value))} required>
                <option value="">Selecione</option>
                {tecnicos.map((t) => <option key={t.id} value={t.id}>{t.nome} ({VINCULOS[t.vinculo]})</option>)}
              </select>
            </label>
          )}
          {MODOS_COM_RASTREIO.includes(modo) && (
            <label className="text-xs sm:col-span-2">Código de rastreio
              <input className="campo" value={rastreio} onChange={(e) => setRastreio(e.target.value)} />
            </label>
          )}
          {aberto === "transferir" && (
            <label className="text-xs">Prazo de chegada
              <input type="date" className="campo" value={prazo} onChange={(e) => setPrazo(e.target.value)} />
            </label>
          )}
          {aberto === "cliente" && (
            <label className="text-xs sm:col-span-4">Link do chamado no Jira (opcional)
              <input className="campo" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
            </label>
          )}
          <div className="sm:col-span-4">
            <button className="btn" disabled={ocupado}>{aberto === "transferir" ? "Enviar transferência" : "Registrar saída"}</button>
            {msg && <span className="ml-2 text-xs text-marca-700">{msg}</span>}
          </div>
        </form>
      )}
    </div>
  );
}

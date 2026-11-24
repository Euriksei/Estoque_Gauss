"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { MODOS, MODOS_COM_RASTREIO, VINCULOS, hojeSP, type Local, type Tecnico } from "@/lib/types";

type Props = {
  unidadeId: number; localId: number;
  // Todo o dedicado da unidade guardado neste local (cada item/chip com a quantidade inteira) e o nome para mostrar.
  itens: { produto_id: number; condicao: string; quantidade: number; nome: string }[];
  destinos: Local[]; tecnicos: Tecnico[]; ehTecnico: boolean; podeTransferir: boolean;
};

// Único lugar onde o dedicado é movimentado: transferir para outro estoque ou enviar ao cliente.
// Vai sempre o dedicado INTEIRO da unidade naquele local, sem quantidade parcial (o banco também exige).
export function DedicadoAcoes({ unidadeId, localId, itens, destinos, tecnicos, ehTecnico, podeTransferir }: Props) {
  const router = useRouter();
  const [aberto, setAberto] = useState<"" | "transferir" | "cliente">("");
  const [destino, setDestino] = useState<number | "">("");
  const [modo, setModo] = useState("");
  const [tecnicoId, setTecnicoId] = useState<number | "">("");
  const [rastreio, setRastreio] = useState("");
  const [chamado, setChamado] = useState("");
  const [finalidade, setFinalidade] = useState("");
  const [msg, setMsg] = useState("");
  const [ocupado, setOcupado] = useState(false);

  const item = itens.map((i) => ({ produto_id: i.produto_id, quantidade: i.quantidade, reservado_unidade_id: unidadeId, condicao: i.condicao }));
  const hoje = hojeSP();

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setMsg("");
    const sb = supabaseBrowser();
    // Transferir = pedido de transferência com o dedicado inteiro (a origem aceita e envia em Transferências).
    const { error } = aberto === "transferir"
      ? await sb.rpc("criar_pedido_transferencia", { p: { origem_id: localId, destino_id: destino, chamado_url: chamado, dedicados: [unidadeId] } })
      : await sb.rpc("registrar_movimentacao", { p: { tipo: "SAIDA_CLIENTE", local_id: localId, unidade_id: unidadeId, data: hoje, finalidade, chamado_url: chamado, modo_envio: modo, codigo_rastreio: rastreio, tecnico_id: tecnicoId || null, itens: item } });
    setOcupado(false);
    if (error) return setMsg(error.message);
    if (aberto === "transferir") window.alert("Pedido de transferência criado. Ele aparece em Transferências até a origem aceitar e enviar.");
    setAberto("");
    router.refresh();
  }

  return (
    <div className="space-y-2">
      <div className="flex gap-2">
        {podeTransferir && <button type="button" className="btn-sec" onClick={() => setAberto(aberto === "transferir" ? "" : "transferir")}>Transferir tudo</button>}
        <button type="button" className="btn-sec" onClick={() => setAberto(aberto === "cliente" ? "" : "cliente")}>Enviar tudo ao cliente</button>
      </div>
      {aberto && (
        <form onSubmit={enviar} className="grid gap-2 rounded border border-slate-200 p-3 sm:grid-cols-4">
          <div className="text-xs sm:col-span-4">Vai junto (todo o dedicado deste local):
            <ul className="mt-1 list-inside list-disc text-sm" data-vai-junto>
              {itens.map((i, k) => <li key={k}>{i.quantidade}× {i.nome}</li>)}
            </ul>
          </div>
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
          {aberto === "cliente" && !ehTecnico && (
            <label className="text-xs">Modo de envio
              <select className="campo" value={modo} onChange={(e) => { setModo(e.target.value); setTecnicoId(""); }} required>
                <option value="">Selecione</option>
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
          {aberto === "cliente" && MODOS_COM_RASTREIO.includes(modo) && (
            <label className="text-xs sm:col-span-2">Código de rastreio
              <input className="campo" value={rastreio} onChange={(e) => setRastreio(e.target.value)} />
            </label>
          )}
          <label className="text-xs sm:col-span-4">Link do chamado no Jira (opcional)
            <input className="campo" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
          </label>
          <div className="sm:col-span-4">
            <button className="btn" disabled={ocupado}>{aberto === "transferir" ? "Criar pedido de transferência" : "Registrar saída"}</button>
            {msg && <span className="ml-2 text-xs text-marca-700">{msg}</span>}
          </div>
        </form>
      )}
    </div>
  );
}

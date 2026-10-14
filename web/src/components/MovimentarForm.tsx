"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import { TIPOS, nomeUnidade, type Associado, type ItemForm, type Local, type Produto, type Unidade } from "@/lib/types";

type Props = { tipos: string[]; locais: Local[]; produtos: Produto[]; unidades: Unidade[]; associados: Associado[]; fornecedores: { id: number; nome: string }[] };

export function MovimentarForm({ tipos, locais, produtos, unidades, associados, fornecedores }: Props) {
  const router = useRouter();
  const [tipo, setTipo] = useState(tipos[0]);
  const [localId, setLocalId] = useState<number | "">(locais.length === 1 ? locais[0].id : "");
  const [data, setData] = useState(new Date().toISOString().slice(0, 10));
  const [unidadeId, setUnidadeId] = useState<number | "">("");
  const [fornecedorId, setFornecedorId] = useState<number | "">("");
  const [nf, setNf] = useState("");
  const [finalidade, setFinalidade] = useState("");
  const [chamado, setChamado] = useState("");
  const [obs, setObs] = useState("");
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [enviando, setEnviando] = useState(false);

  const cliente = tipo === "SAIDA_CLIENTE" || tipo === "DEVOLUCAO_CLIENTE";

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setMsg(null);
    const { error } = await supabaseBrowser().rpc("registrar_movimentacao", {
      p: {
        tipo, data, local_id: localId, unidade_id: unidadeId || null, fornecedor_id: fornecedorId || null,
        numero_nf: nf, finalidade, chamado_url: chamado, observacao: obs, itens: itensParaRpc(itens),
      },
    });
    setEnviando(false);
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Movimentação registrada." });
    setItens([itemVazio()]);
    setObs("");
    setChamado("");
    setNf("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="text-sm">Tipo
          <select className="campo mt-1" value={tipo} onChange={(e) => setTipo(e.target.value)}>
            {tipos.map((t) => <option key={t} value={t}>{TIPOS[t]}</option>)}
          </select>
        </label>
        <label className="text-sm">Local
          <select className="campo mt-1" value={localId} onChange={(e) => setLocalId(Number(e.target.value))} required>
            <option value="">Selecione</option>
            {locais.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
        <label className="text-sm">Data
          <input type="date" className="campo mt-1" value={data} onChange={(e) => setData(e.target.value)} required />
        </label>
      </div>

      {cliente && (
        <div className="grid gap-3 sm:grid-cols-3">
          <label className="text-sm sm:col-span-2">Cliente / unidade
            <select className="campo mt-1" value={unidadeId} onChange={(e) => setUnidadeId(Number(e.target.value))} required>
              <option value="">Selecione</option>
              {unidades.map((u) => <option key={u.id} value={u.id}>{nomeUnidade(u)}</option>)}
            </select>
          </label>
          {tipo === "SAIDA_CLIENTE" && (
            <label className="text-sm">Finalidade
              <select className="campo mt-1" value={finalidade} onChange={(e) => setFinalidade(e.target.value)}>
                <option value="">-</option>
                <option value="mobilizacao">Mobilização</option>
                <option value="manutencao">Manutenção</option>
              </select>
            </label>
          )}
          <label className="text-sm sm:col-span-3">Link do chamado no Jira (opcional)
            <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
          </label>
        </div>
      )}

      {tipo === "ENTRADA_COMPRA" && (
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="text-sm">Fornecedor
            <select className="campo mt-1" value={fornecedorId} onChange={(e) => setFornecedorId(Number(e.target.value))}>
              <option value="">-</option>
              {fornecedores.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
            </select>
          </label>
          <label className="text-sm">NF de entrada
            <input className="campo mt-1" value={nf} onChange={(e) => setNf(e.target.value)} />
          </label>
        </div>
      )}

      <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={tipo === "SAIDA_CLIENTE" ? associados : []}
        unidades={unidades} reserva={tipo === "SAIDA_CLIENTE" ? "reservado" : "nenhuma"} permiteNegativo={tipo === "AJUSTE"} />

      <label className="block text-sm">{tipo === "AJUSTE" ? "Justificativa (obrigatória; use quantidade negativa para baixar)" : "Observação"}
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} required={tipo === "AJUSTE"} />
      </label>

      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-red-700"}`}>{msg.texto}</p>}
      <button className="btn" disabled={enviando}>Registrar</button>
    </form>
  );
}

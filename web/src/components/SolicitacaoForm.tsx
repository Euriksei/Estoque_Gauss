"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Busca } from "@/components/Busca";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import type { DedicadoNoLocal } from "@/components/TransferenciaForm";
import { nomeItem, nomeUnidade, type Associado, type ItemForm, type Local, type Produto, type Unidade } from "@/lib/types";

const TIPOS = {
  enviar_cliente: "Enviar ao cliente",
  enviar_dedicado: "Enviar dedicado",
  retirar_dedicado: "Retirar dedicado",
} as const;
type Tipo = keyof typeof TIPOS;

// Nova solicitação (só o agendamento):
//  - Enviar ao cliente: itens do estoque livre de uma origem para o cliente/unidade;
//  - Enviar dedicado: o dedicado inteiro do cliente/unidade guardado num estoque;
//  - Retirar dedicado: buscar itens no cliente e trazer para um estoque, onde chegam já dedicados à unidade.
export function SolicitacaoForm({ produtos, associados, unidades, estoques, dedicados }: {
  produtos: Produto[]; associados: Associado[]; unidades: Unidade[]; estoques: Local[]; dedicados: DedicadoNoLocal[];
}) {
  const router = useRouter();
  const [tipo, setTipo] = useState<Tipo>("enviar_cliente");
  const [unidade, setUnidade] = useState<number | "">("");
  const [local, setLocal] = useState<number | "">("");
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [chamado, setChamado] = useState("");
  const [obs, setObs] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const prod = new Map(produtos.map((p) => [p.id, p]));
  const nomeLocal = new Map(estoques.map((l) => [l.id, l.nome]));
  const daUnidade = dedicados.filter((d) => d.unidade_id === unidade && d.quantidade > 0);
  // Enviar dedicado: só os estoques onde a unidade tem dedicado guardado.
  const locaisDed = [...new Set(daUnidade.map((d) => d.local_id))];
  const opcoesLocal = tipo === "enviar_dedicado" ? estoques.filter((l) => locaisDed.includes(l.id)) : estoques;
  const vaiJunto = daUnidade.filter((d) => d.local_id === local);
  const chamadoObrigatorio = tipo === "enviar_dedicado" || tipo === "retirar_dedicado";

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    // Enviar dedicado e Retirar dedicado exigem o link do chamado (o banco tem a mesma regra).
    if (chamadoObrigatorio && !/^https?:\/\/\S+$/i.test(chamado.trim()))
      return setMsg({ ok: false, texto: "Informe o link do chamado no Jira, começando com http:// ou https:// (obrigatório em Enviar dedicado e Retirar dedicado)." });
    const linhas = itensParaRpc(itens, associados).map((i) => ({ produto_id: i.produto_id, quantidade: i.quantidade }));
    const base = { tipo, unidade_id: unidade, chamado_url: chamado.trim(), observacao: obs };
    const p = tipo === "enviar_cliente" ? { ...base, origem_id: local, itens: linhas }
      : tipo === "enviar_dedicado" ? { ...base, origem_id: local }
      : { ...base, destino_id: local, itens: linhas };
    setOcupado(true); setMsg(null);
    const { error } = await supabaseBrowser().rpc("criar_solicitacao", { p });
    setOcupado(false);
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Solicitação enviada. Ela fica pendente até o estoque aceitar." });
    setItens([itemVazio()]); setObs(""); setChamado("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-3">
      <h2 className="font-medium">Nova solicitação</h2>
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="text-sm">Tipo
          <select className="campo mt-1" value={tipo} onChange={(e) => { setTipo(e.target.value as Tipo); setLocal(""); }}>
            {Object.entries(TIPOS).map(([v, n]) => <option key={v} value={v}>{n}</option>)}
          </select>
        </label>
        <div className="text-sm">Cliente / unidade
          <div className="mt-1"><Busca required value={unidade} onChange={(v) => { setUnidade(v); if (tipo === "enviar_dedicado") setLocal(""); }} placeholder="Digite para buscar o cliente"
            opcoes={unidades.map((u) => ({ value: u.id, label: nomeUnidade(u) }))} /></div>
        </div>
        <label className="text-sm">{tipo === "retirar_dedicado" ? "Estoque que recebe" : tipo === "enviar_dedicado" ? "Estoque onde está o dedicado" : "Sai do estoque"}
          <select className="campo mt-1" value={local} onChange={(e) => setLocal(e.target.value ? Number(e.target.value) : "")} required>
            <option value="">{tipo === "enviar_dedicado" && unidade !== "" && opcoesLocal.length === 0 ? "Sem dedicado desta unidade" : "Selecione"}</option>
            {opcoesLocal.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
      </div>

      {tipo === "enviar_dedicado" ? (
        local !== "" && (
          <div className="text-sm" data-vai-junto>Vai junto (todo o dedicado em {nomeLocal.get(local)}):
            <ul className="mt-1 list-inside list-disc">
              {vaiJunto.map((d, k) => <li key={k}>{d.quantidade}× {nomeItem(prod.get(d.produto_id)?.nome, prod.get(d.produto_id)?.usa_chip, d.condicao)}</li>)}
            </ul>
          </div>
        )
      ) : (
        <div className="space-y-1">
          <p className="text-sm font-medium">{tipo === "retirar_dedicado" ? "Itens a buscar no cliente" : "Itens (estoque livre)"}</p>
          <ItensEditor key={tipo} itens={itens} onChange={setItens} produtos={produtos} associados={associados} unidades={unidades} chicote="sim" chip="nenhum" />
          <p className="text-xs text-slate-500">O chip dos módulos é escolhido por quem atende.</p>
        </div>
      )}

      <label className="block text-sm">Link do chamado no Jira {chamadoObrigatorio ? <span className="text-marca-700" aria-hidden="true">*</span> : "(opcional)"}
        <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698"
          required={chamadoObrigatorio} aria-required={chamadoObrigatorio} pattern={chamadoObrigatorio ? String.raw`\s*https?://\S+\s*` : undefined}
          title={chamadoObrigatorio ? "Link começando com http:// ou https://" : undefined} />
      </label>
      <label className="block text-sm">Observação
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-marca-700"}`}>{msg.texto}</p>}
      <button className="btn" disabled={ocupado}>Enviar solicitação</button>
    </form>
  );
}

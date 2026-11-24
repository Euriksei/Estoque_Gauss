"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import { nomeItem, nomeUnidade, type Associado, type ItemForm, type Local, type Produto, type Unidade } from "@/lib/types";

export type DedicadoNoLocal = { unidade_id: number; local_id: number; produto_id: number; condicao: string; quantidade: number };

// Novo pedido de transferência (admin e operador). Não sai saldo agora: a origem aceita, prepara e envia.
// Itens saem do estoque livre (com "Dedicado para" opcional no destino); dedicados vão inteiros.
export function TransferenciaForm({ origens, destinos, produtos, unidades, associados, dedicados }: {
  origens: Local[]; destinos: Local[]; produtos: Produto[]; unidades: Unidade[]; associados: Associado[]; dedicados: DedicadoNoLocal[];
}) {
  const router = useRouter();
  const [origem, setOrigem] = useState<number | "">(origens.length === 1 ? origens[0].id : "");
  const [destino, setDestino] = useState<number | "">("");
  const [chamado, setChamado] = useState("");
  const [obs, setObs] = useState("");
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [unidadesDed, setUnidadesDed] = useState<number[]>([]);
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [ocupado, setOcupado] = useState(false);

  const prod = new Map(produtos.map((p) => [p.id, p]));
  const nomeUn = new Map(unidades.map((u) => [u.id, nomeUnidade(u)]));
  const naOrigem = dedicados.filter((d) => d.local_id === origem && d.quantidade > 0);
  const unidadesNaOrigem = [...new Set(naOrigem.map((d) => d.unidade_id))].sort((a, b) => (nomeUn.get(a) ?? "").localeCompare(nomeUn.get(b) ?? "", "pt-BR"));

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const linhas = itensParaRpc(itens.filter((i) => i.produto_id !== ""), associados)
      .map((i) => ({ produto_id: i.produto_id, quantidade: i.quantidade, reservar_para_unidade_id: i.reservar_para_unidade_id }));
    if (linhas.length === 0 && unidadesDed.length === 0) return setMsg({ ok: false, texto: "Escolha ao menos um item ou um dedicado." });
    setOcupado(true); setMsg(null);
    const { error } = await supabaseBrowser().rpc("criar_pedido_transferencia", {
      p: { origem_id: origem, destino_id: destino, chamado_url: chamado, observacao: obs, itens: linhas, dedicados: unidadesDed },
    });
    setOcupado(false);
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Pedido criado. Ele fica pendente até a origem aceitar e enviar; o saldo só sai no envio." });
    setItens([itemVazio()]); setUnidadesDed([]); setObs(""); setChamado("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-4">
      <h2 className="font-medium">Novo pedido de transferência</h2>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="text-sm">De (origem)
          <select className="campo mt-1" value={origem} onChange={(e) => { setOrigem(e.target.value ? Number(e.target.value) : ""); setUnidadesDed([]); }} required>
            <option value="">Selecione</option>
            {origens.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
        <label className="text-sm">Para (destino)
          <select className="campo mt-1" value={destino} onChange={(e) => setDestino(e.target.value ? Number(e.target.value) : "")} required>
            <option value="">Selecione</option>
            {destinos.filter((l) => l.id !== origem).map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
      </div>

      <div className="space-y-1">
        <p className="text-sm font-medium">Itens do estoque livre</p>
        <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={associados} unidades={unidades} reserva="reservar" chicote="sim" chip="nenhum" permiteVazio />
        <p className="text-xs text-slate-500">O chip dos módulos é escolhido por quem envia. &quot;Dedicado para&quot; deixa o item dedicado ao cliente quando chegar.</p>
      </div>

      {origem !== "" && (
        <fieldset className="space-y-1">
          <legend className="text-sm font-medium">Dedicados (vão inteiros)</legend>
          {unidadesNaOrigem.length === 0 && <p className="text-xs text-slate-500">Nenhum estoque dedicado nesta origem.</p>}
          {unidadesNaOrigem.map((u) => (
            <label key={u} className="flex items-start gap-2 text-sm">
              <input type="checkbox" className="mt-1" checked={unidadesDed.includes(u)}
                onChange={(e) => setUnidadesDed(e.target.checked ? [...unidadesDed, u] : unidadesDed.filter((x) => x !== u))} />
              <span><strong>{nomeUn.get(u)}</strong>
                <span className="text-slate-600"> · vai junto: {naOrigem.filter((d) => d.unidade_id === u).map((d) => `${d.quantidade}× ${nomeItem(prod.get(d.produto_id)?.nome, prod.get(d.produto_id)?.usa_chip, d.condicao)}`).join(", ")}</span></span>
            </label>
          ))}
        </fieldset>
      )}

      <label className="block text-sm">Link do chamado no Jira (opcional)
        <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
      </label>
      <label className="block text-sm">Observação
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-marca-700"}`}>{msg.texto}</p>}
      <button className="btn" disabled={ocupado}>Criar pedido</button>
    </form>
  );
}

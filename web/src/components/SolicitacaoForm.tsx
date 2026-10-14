"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import type { Associado, ItemForm, Local, Produto, Unidade } from "@/lib/types";

// Técnico: o pedido é para o estoque dele e sai do estoque base dele (fixo). Os demais escolhem de onde e para onde.
export function SolicitacaoForm({ produtos, associados, unidades, locais = [], tecnicoBase }: {
  produtos: Produto[]; associados: Associado[]; unidades: Unidade[]; locais?: Local[]; tecnicoBase: { nome: string } | null | undefined;
}) {
  const ehTecnico = tecnicoBase !== undefined;
  const [origem, setOrigem] = useState<number | "">("");
  const [destino, setDestino] = useState<number | "">("");
  const router = useRouter();
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [chamado, setChamado] = useState("");
  const [obs, setObs] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await supabaseBrowser().rpc("criar_solicitacao", {
      p: { origem_id: origem, destino_id: destino, chamado_url: chamado, observacao: obs, itens: itensParaRpc(itens, associados).map((i) => ({ produto_id: i.produto_id, quantidade: i.quantidade, reservar_para_unidade_id: i.reservar_para_unidade_id })) },
    });
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Solicitação enviada." });
    setItens([itemVazio()]); setObs(""); setChamado("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-3">
      <h2 className="font-medium">Nova solicitação</h2>
      {ehTecnico ? (
        <p className="text-sm text-slate-600">O pedido é para o seu estoque e sai de {tecnicoBase ? tecnicoBase.nome : "seu estoque base"}.</p>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="text-sm">Sai de
            <select className="campo mt-1" value={origem} onChange={(e) => setOrigem(Number(e.target.value))} required>
              <option value="">Selecione</option>
              {locais.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
            </select>
          </label>
          <label className="text-sm">Vai para
            <select className="campo mt-1" value={destino} onChange={(e) => setDestino(Number(e.target.value))} required>
              <option value="">Selecione</option>
              {locais.filter((l) => l.id !== origem).map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
            </select>
          </label>
        </div>
      )}
      <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={associados} unidades={unidades} reserva="reservar" chicote="sim" />
      <label className="block text-sm">Link do chamado no Jira (opcional)
        <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
      </label>
      <label className="block text-sm">Observação
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-marca-700"}`}>{msg.texto}</p>}
      <button className="btn">Enviar solicitação</button>
    </form>
  );
}

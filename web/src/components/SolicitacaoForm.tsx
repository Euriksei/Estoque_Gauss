"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ItensEditor, itemVazio } from "@/components/ItensEditor";
import type { Associado, ItemForm, Produto } from "@/lib/types";

export function SolicitacaoForm({ produtos, associados }: { produtos: Produto[]; associados: Associado[] }) {
  const router = useRouter();
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [chamado, setChamado] = useState("");
  const [obs, setObs] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await supabaseBrowser().rpc("criar_solicitacao", {
      p: { chamado_url: chamado, observacao: obs, itens: itens.map((i) => ({ produto_id: i.produto_id, quantidade: i.quantidade })) },
    });
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Pedido enviado." });
    setItens([itemVazio()]); setObs(""); setChamado("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-3">
      <h2 className="font-medium">Pedir material</h2>
      <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={associados} unidades={[]} />
      <label className="block text-sm">Link do chamado (opcional)
        <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} />
      </label>
      <label className="block text-sm">Observação
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-red-700"}`}>{msg.texto}</p>}
      <button className="btn">Enviar pedido</button>
    </form>
  );
}

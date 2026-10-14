"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import type { Associado, ItemForm, Local, Produto, Unidade } from "@/lib/types";

export function TransferenciaForm({ origens, destinos, produtos, unidades, associados }: {
  origens: Local[]; destinos: Local[]; produtos: Produto[]; unidades: Unidade[]; associados: Associado[];
}) {
  const router = useRouter();
  const [origem, setOrigem] = useState<number | "">(origens.length === 1 ? origens[0].id : "");
  const [destino, setDestino] = useState<number | "">("");
  const [data, setData] = useState(new Date().toISOString().slice(0, 10));
  const [modo, setModo] = useState("");
  const [rastreio, setRastreio] = useState("");
  const [prazo, setPrazo] = useState("");
  const [obs, setObs] = useState("");
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setMsg(null);
    const { error } = await supabaseBrowser().rpc("criar_transferencia", {
      p: { origem_id: origem, destino_id: destino, data, modo_envio: modo, codigo_rastreio: rastreio, prazo_chegada: prazo, observacao: obs, itens: itensParaRpc(itens, associados) },
    });
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Transferência enviada. O saldo saiu do seu estoque e entra no destino quando ele confirmar o recebimento." });
    setItens([itemVazio()]); setRastreio(""); setObs("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-4">
      <h2 className="font-medium">Nova transferência</h2>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="text-sm">De
          <select className="campo mt-1" value={origem} onChange={(e) => setOrigem(Number(e.target.value))} required>
            <option value="">Selecione</option>
            {origens.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
        <label className="text-sm">Para
          <select className="campo mt-1" value={destino} onChange={(e) => setDestino(Number(e.target.value))} required>
            <option value="">Selecione</option>
            {destinos.filter((l) => l.id !== origem).map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
        <label className="text-sm">Data de envio
          <input type="date" className="campo mt-1" value={data} onChange={(e) => setData(e.target.value)} required />
        </label>
        <label className="text-sm">Prazo de chegada
          <input type="date" className="campo mt-1" value={prazo} onChange={(e) => setPrazo(e.target.value)} />
        </label>
        <label className="text-sm">Meio de envio
          <select className="campo mt-1" value={modo} onChange={(e) => setModo(e.target.value)}>
            <option value="">-</option>
            <option value="correios">Correios</option><option value="sedex">Sedex</option>
            <option value="retirada">Retirada</option><option value="tecnico">Técnico</option>
            <option value="transportadora">Transportadora</option>
          </select>
        </label>
        <label className="text-sm">Código de rastreio
          <input className="campo mt-1" value={rastreio} onChange={(e) => setRastreio(e.target.value)} />
        </label>
      </div>
      <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={associados} unidades={unidades} reserva="reservar" chicote="sim" />
      <label className="block text-sm">Observação
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-marca-700"}`}>{msg.texto}</p>}
      <button className="btn">Enviar</button>
    </form>
  );
}

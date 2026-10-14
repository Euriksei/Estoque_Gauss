"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import type { Local } from "@/lib/types";

// O operador atende o pedido do técnico enviando do seu estoque para o carro dele.
export function AtenderSolicitacao({ id, itens, origens }: { id: number; itens: { produto_id: number; quantidade: number }[]; origens: Local[] }) {
  const router = useRouter();
  const [origem, setOrigem] = useState<number | "">(origens.length === 1 ? origens[0].id : "");
  const [modo, setModo] = useState("tecnico");
  const [erro, setErro] = useState("");
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2">
      <select className="campo w-auto" value={origem} onChange={(e) => setOrigem(Number(e.target.value))}>
        <option value="">Enviar de...</option>
        {origens.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
      </select>
      <select className="campo w-auto" value={modo} onChange={(e) => setModo(e.target.value)}>
        <option value="tecnico">Técnico</option><option value="retirada">Retirada</option>
        <option value="correios">Correios</option><option value="sedex">Sedex</option>
      </select>
      <button className="btn" disabled={!origem} onClick={async () => {
        const { error } = await supabaseBrowser().rpc("atender_solicitacao", {
          p_id: id, p: { origem_id: origem, modo_envio: modo, itens: itens.map((i) => ({ ...i, condicao: "novo" })) },
        });
        if (error) setErro(error.message); else router.refresh();
      }}>Atender (envia para o carro)</button>
      {erro && <span className="text-xs text-red-700">{erro}</span>}
    </div>
  );
}

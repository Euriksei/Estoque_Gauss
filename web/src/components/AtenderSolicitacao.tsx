"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { CHIPS } from "@/lib/types";

// O operador atende o pedido: o envio sai da origem e vai para o destino definidos na solicitação.
// Para cada módulo de telemetria do pedido, ele escolhe de qual chip (ou sem chip) o módulo sai.
export function AtenderSolicitacao({ id, modulos }: { id: number; modulos: { chave: string; nome: string }[] }) {
  const router = useRouter();
  const [modo, setModo] = useState("tecnico");
  const [chips, setChips] = useState<Record<string, string>>({});
  const [erro, setErro] = useState("");
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2">
      {modulos.map((m) => (
        <label key={m.chave} className="flex items-center gap-1 text-xs">{m.nome}
          <select className="campo w-auto" value={chips[m.chave] ?? ""} onChange={(e) => setChips({ ...chips, [m.chave]: e.target.value })}>
            <option value="">Chip: escolha</option>
            {Object.entries(CHIPS).map(([v, n]) => <option key={v} value={v}>{n}</option>)}
          </select>
        </label>
      ))}
      <select className="campo w-auto" value={modo} onChange={(e) => setModo(e.target.value)}>
        <option value="tecnico">Técnico</option><option value="retirada">Retirada</option>
        <option value="correios">Correios</option><option value="sedex">Sedex</option>
      </select>
      <button className="btn" onClick={async () => {
        if (modulos.some((m) => !chips[m.chave])) return setErro("Escolha o chip de cada módulo.");
        const { error } = await supabaseBrowser().rpc("atender_solicitacao", {
          p_id: id, p: { modo_envio: modo, chips },
        });
        if (error) setErro(error.message); else router.refresh();
      }}>Atender (enviar)</button>
      {erro && <span className="text-xs text-marca-700">{erro}</span>}
    </div>
  );
}

"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

// O operador atende o pedido: o envio sai da origem e vai para o destino definidos na solicitação.
export function AtenderSolicitacao({ id }: { id: number }) {
  const router = useRouter();
  const [modo, setModo] = useState("tecnico");
  const [erro, setErro] = useState("");
  return (
    <div className="mt-2 flex flex-wrap items-center gap-2">
      <select className="campo w-auto" value={modo} onChange={(e) => setModo(e.target.value)}>
        <option value="tecnico">Técnico</option><option value="retirada">Retirada</option>
        <option value="correios">Correios</option><option value="sedex">Sedex</option>
      </select>
      <button className="btn" onClick={async () => {
        const { error } = await supabaseBrowser().rpc("atender_solicitacao", {
          p_id: id, p: { modo_envio: modo },
        });
        if (error) setErro(error.message); else router.refresh();
      }}>Atender (enviar)</button>
      {erro && <span className="text-xs text-red-700">{erro}</span>}
    </div>
  );
}

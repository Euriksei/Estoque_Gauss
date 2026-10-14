"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

// Botão que chama uma função do banco e atualiza a página.
export function Acao({ fn, args, texto, confirmar, pedirMotivo, secundario }: {
  fn: string; args: Record<string, unknown>; texto: string; confirmar?: string; pedirMotivo?: boolean; secundario?: boolean;
}) {
  const router = useRouter();
  const [erro, setErro] = useState("");
  const [ocupado, setOcupado] = useState(false);
  return (
    <span>
      <button className={secundario ? "btn-sec" : "btn"} disabled={ocupado} onClick={async () => {
        if (confirmar && !window.confirm(confirmar)) return;
        const extra = pedirMotivo ? { p_motivo: window.prompt("Motivo:") ?? "" } : {};
        if (pedirMotivo && !extra.p_motivo) return;
        setOcupado(true);
        const { error } = await supabaseBrowser().rpc(fn, { ...args, ...extra });
        setOcupado(false);
        if (error) setErro(error.message); else { setErro(""); router.refresh(); }
      }}>{texto}</button>
      {erro && <span className="ml-2 text-xs text-marca-700">{erro}</span>}
    </span>
  );
}

"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { PERFIS, type Local, type Perfil, type Usuario } from "@/lib/types";

export function UsuarioLinha({ u, locais, meusLocais }: { u: Usuario; locais: Local[]; meusLocais: number[] }) {
  const router = useRouter();
  const [erro, setErro] = useState("");
  const sb = supabaseBrowser();
  const carro = locais.find((l) => l.tecnico?.usuario_id === u.id);

  async function rodar(p: PromiseLike<{ error: { message: string } | null }>) {
    const { error } = await p;
    setErro(error?.message ?? "");
    if (!error) router.refresh();
  }

  return (
    <tr className="align-top">
      <td className="td"><div className="font-medium">{u.nome}</div><div className="text-xs text-slate-500">{u.email}</div></td>
      <td className="td">
        <select className="campo w-auto" value={u.perfil} onChange={(e) => rodar(sb.from("usuario").update({ perfil: e.target.value as Perfil }).eq("id", u.id))}>
          {Object.entries(PERFIS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
        </select>
      </td>
      <td className="td">
        <label className="flex items-center gap-1 text-sm">
          <input type="checkbox" checked={u.ativo} onChange={(e) => rodar(sb.from("usuario").update({ ativo: e.target.checked }).eq("id", u.id))} /> Ativo
        </label>
      </td>
      <td className="td">
        {u.perfil === "operador" && locais.filter((l) => l.tipo === "estoque").map((l) => (
          <label key={l.id} className="mr-3 inline-flex items-center gap-1 text-sm">
            <input type="checkbox" checked={meusLocais.includes(l.id)} onChange={(e) =>
              rodar(e.target.checked
                ? sb.from("usuario_local").insert({ usuario_id: u.id, local_id: l.id })
                : sb.from("usuario_local").delete().eq("usuario_id", u.id).eq("local_id", l.id))} /> {l.nome}
          </label>
        ))}
        {u.perfil === "tecnico" && <a className="text-sm underline" href="/cadastros">{carro ? `Estoque: ${carro.nome}` : "Ligue este login a um técnico em Cadastros"}</a>}
        {erro && <div className="text-xs text-red-700">{erro}</div>}
      </td>
    </tr>
  );
}

import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getUsuario } from "@/lib/dados";
import { TrocarChipForm } from "@/components/TrocarChipForm";
import { CHIPS } from "@/lib/types";

export const dynamic = "force-dynamic";

type Linha = { local_id: number; produto_id: number; condicao: string; reservado_unidade_id: number | null; quantidade: number };

export default async function Chips() {
  const usuario = (await getUsuario())!;
  if (usuario.perfil !== "admin" && usuario.perfil !== "operador") redirect("/transferencias");
  const sb = supabaseServer();
  const [{ operaveis, todos }, cat, { data }] = await Promise.all([getLocais(usuario), getCatalogo(), sb.from("saldo").select("*")]);
  const saldo = ((data ?? []) as Linha[]).filter((s) => s.quantidade !== 0 && s.reservado_unidade_id === null);
  const modulos = cat.produtos.filter((p) => p.usa_chip);
  const chipsAvulsos = cat.produtos.filter((p) => p.chip_tipo);
  const nomeLocal = new Map(todos.map((l) => [l.id, l.nome]));
  const locaisComChip = [...new Set(saldo.filter((s) => chipsAvulsos.some((c) => c.id === s.produto_id) || modulos.some((m) => m.id === s.produto_id)).map((s) => s.local_id))];

  return (
    <div className="space-y-5">
      <h1 className="text-xl font-bold text-marinho-900">Chips dos módulos</h1>
      <p className="text-sm text-slate-600">
        Todo módulo de telemetria (Ruptela, Galileosky e Teltonika) tem o estoque separado por chip: {Object.values(CHIPS).join(", ")}.
        Quando um módulo está sem chip, ou o chip precisa mudar, registre aqui. Os chips avulsos continuam sendo itens normais de estoque (entrada e descarte em Registrar).
      </p>
      <TrocarChipForm locais={operaveis} modulos={modulos} />
      {locaisComChip.map((lid) => (
        <div key={lid} className="card space-y-2">
          <h2 className="font-medium">{nomeLocal.get(lid)}</h2>
          <table className="w-full">
            <thead><tr><th className="th">Item</th><th className="th">Chip</th><th className="th text-right">Qtd.</th></tr></thead>
            <tbody className="divide-y divide-slate-100">
              {saldo.filter((s) => s.local_id === lid && (modulos.some((m) => m.id === s.produto_id) || chipsAvulsos.some((c) => c.id === s.produto_id)))
                .map((s, i) => {
                  const p = cat.produtos.find((x) => x.id === s.produto_id);
                  return (
                    <tr key={i}>
                      <td className="td">{p?.nome}</td>
                      <td className="td">{p?.usa_chip ? CHIPS[s.condicao] : "chip avulso"}</td>
                      <td className="td text-right font-medium">{s.quantidade}</td>
                    </tr>
                  );
                })}
            </tbody>
          </table>
        </div>
      ))}
    </div>
  );
}

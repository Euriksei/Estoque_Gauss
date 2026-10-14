import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getTecnicos, getUsuario } from "@/lib/dados";
import { DedicadoAcoes } from "@/components/DedicadoAcoes";
import { TIPOS, STATUS, nomeUnidade } from "@/lib/types";

export const dynamic = "force-dynamic";

type Pos = { unidade_id: number; produto_id: number; situacao: "em_local" | "em_transito" | "entregue"; local_id: number | null; quantidade: number };
type Hist = { unidade_id: number; produto_id: number; movimentacao_id: number; tipo: string; status: string; data: string; local_origem_id: number | null; local_destino_id: number | null; quantidade: number };

const SITUACAO = { em_local: "Guardado", em_transito: "Em trânsito", entregue: "Entregue ao cliente" };

export default async function Dedicados() {
  const usuario = (await getUsuario())!;
  // O técnico só usa Transferências e Solicitações.
  if ((usuario.perfil as string) === "tecnico") redirect("/transferencias");
  const sb = supabaseServer();
  const [{ todos, operaveis }, cat, pos, hist, tecnicos] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("dedicados_posicao").select("*"),
    sb.from("dedicados_historico").select("*").order("movimentacao_id", { ascending: false }).limit(300),
    getTecnicos(),
  ]);
  const nomeUn = new Map(cat.unidades.map((u) => [u.id, nomeUnidade(u)]));
  const nomeProd = new Map(cat.produtos.map((p) => [p.id, p.nome]));
  const nomeLocal = new Map(todos.map((l) => [l.id, l.nome]));
  const posicoes = (pos.data ?? []) as Pos[];
  const historico = (hist.data ?? []) as Hist[];
  const operaveisIds = new Set(operaveis.map((l) => l.id));
  const podeMover = usuario.perfil === "admin" || usuario.perfil === "operador" || usuario.perfil === "tecnico";
  const unidadesComItens = [...new Set([...posicoes.map((p) => p.unidade_id), ...historico.map((h) => h.unidade_id)])];

  return (
    <div className="space-y-5">
      <h1 className="text-xl font-bold text-marinho-900">Itens dedicados a clientes</h1>
      <p className="text-sm text-slate-600">Itens reservados para um cliente ficam fora do estoque livre. Aqui você acompanha onde está cada um, do estoque até a entrega. Depois de dedicado, o item só se movimenta por esta tela: transferir para outro estoque ou enviar ao cliente.</p>
      {unidadesComItens.length === 0 && <p className="text-sm text-slate-500">Nenhum item dedicado ainda. Para criar um, use "Dedicado para" em Registrar (entrada por compra, ajuste) ou em Transferências.</p>}
      {unidadesComItens.map((u) => (
        <div key={u} className="card space-y-3">
          <h2 className="font-medium">{nomeUn.get(u)}</h2>
          <table className="w-full">
            <thead><tr><th className="th">Item</th><th className="th">Situação</th><th className="th">Onde</th><th className="th text-right">Qtd.</th><th className="th"></th></tr></thead>
            <tbody className="divide-y divide-slate-100">
              {posicoes.filter((p) => p.unidade_id === u).map((p, i) => (
                <tr key={i}>
                  <td className="td">{nomeProd.get(p.produto_id)}</td>
                  <td className="td">{SITUACAO[p.situacao]}</td>
                  <td className="td">{p.local_id ? nomeLocal.get(p.local_id) ?? "-" : "-"}</td>
                  <td className="td text-right font-medium">{p.quantidade}</td>
                  <td className="td">
                    {podeMover && p.situacao === "em_local" && p.local_id && operaveisIds.has(p.local_id) && p.quantidade > 0 && (
                      <DedicadoAcoes unidadeId={u} produtoId={p.produto_id} localId={p.local_id} max={p.quantidade}
                        destinos={todos} tecnicos={tecnicos.filter((t) => t.ativo)} ehTecnico={usuario.perfil === "tecnico"} podeTransferir={usuario.perfil !== "tecnico"} />
                    )}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
          <details className="text-sm">
            <summary className="cursor-pointer text-slate-600">Histórico completo</summary>
            <ul className="mt-2 space-y-1">
              {historico.filter((h) => h.unidade_id === u).map((h, i) => (
                <li key={i}>{h.data} · {TIPOS[h.tipo]} ({STATUS[h.status]}) · {h.quantidade}× {nomeProd.get(h.produto_id)}
                  {h.local_origem_id && ` · de ${nomeLocal.get(h.local_origem_id) ?? "outro local"}`}
                  {h.local_destino_id && ` · para ${nomeLocal.get(h.local_destino_id) ?? "outro local"}`}</li>
              ))}
            </ul>
          </details>
        </div>
      ))}
    </div>
  );
}

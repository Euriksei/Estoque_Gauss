import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getUsuario, getCatalogo, getLocais, nomeUnidade } from "@/lib/dados";

export const dynamic = "force-dynamic";

type Linha = { local_id: number; produto_id: number; reservado_unidade_id: number | null; quantidade: number };

export default async function Estoque({ searchParams }: { searchParams: { local?: string; q?: string; grupo?: string; categoria?: string } }) {
  const usuario = (await getUsuario())!;
  // O técnico só usa Transferências e Solicitações.
  if ((usuario.perfil as string) === "tecnico") redirect("/transferencias");
  const sb = supabaseServer();
  const [{ data }, { produtos, unidades }, { todos }] = await Promise.all([
    sb.from("saldo").select("*"),
    getCatalogo(),
    getLocais(usuario),
  ]);
  const saldo = ((data ?? []) as Linha[]).filter((l) => l.quantidade !== 0);
  const visiveis = todos.filter((l) => saldo.some((s) => s.local_id === l.id));
  const filtroLocal = searchParams.local ? Number(searchParams.local) : null;
  const q = (searchParams.q ?? "").toLowerCase();
  const filtroCat = searchParams.categoria ? Number(searchParams.categoria) : null;
  const categorias = [...new Map(produtos.filter((p) => p.categoria_id).map((p) => [p.categoria_id as number, p.categoria?.nome ?? ""])).entries()].sort((a, b) => a[1].localeCompare(b[1], "pt-BR"));
  const grupoDe = (id: number) => { const l = todos.find((x) => x.id === id); return l?.tipo === "tecnico" ? `tec-${l.tecnico?.vinculo}` : "fixo"; };

  const nomeProduto = new Map(produtos.map((p) => [p.id, p]));
  const nomeUn = new Map(unidades.map((u) => [u.id, nomeUnidade(u)]));
  const nomeLocal = new Map(todos.map((l) => [l.id, l.nome]));

  const linhas = saldo
    .filter((s) => (filtroLocal ? s.local_id === filtroLocal : true))
    .filter((s) => (searchParams.grupo ? grupoDe(s.local_id) === searchParams.grupo : true))
    .filter((s) => (filtroCat ? nomeProduto.get(s.produto_id)?.categoria_id === filtroCat : true))
    .filter((s) => (q ? (nomeProduto.get(s.produto_id)?.nome ?? "").toLowerCase().includes(q) : true));

  // Alerta de estoque mínimo: soma do estoque livre dos locais fixos (não conta o carro do técnico nem dedicados).
  const fixos = new Set(todos.filter((l) => l.tipo === "estoque").map((l) => l.id));
  const totalLivre = new Map<number, number>();
  for (const s of saldo) {
    if (fixos.has(s.local_id) && s.reservado_unidade_id === null) {
      totalLivre.set(s.produto_id, (totalLivre.get(s.produto_id) ?? 0) + s.quantidade);
    }
  }
  const abaixo = usuario.perfil === "tecnico" ? [] :
    produtos.filter((p) => p.estoque_minimo > 0 && (totalLivre.get(p.id) ?? 0) < p.estoque_minimo);

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-bold text-marinho-900">{usuario.perfil === "tecnico" ? "Meu estoque" : "Estoque"}</h1>

      {abaixo.length > 0 && (
        <div className="card border-amber-300 bg-amber-50 text-sm">
          <strong>{abaixo.length} item(ns) abaixo do estoque mínimo:</strong>{" "}
          {abaixo.slice(0, 12).map((p) => `${p.nome} (${totalLivre.get(p.id) ?? 0}/${p.estoque_minimo})`).join(", ")}
          {abaixo.length > 12 && "…"}
        </div>
      )}

      <form className="flex flex-wrap gap-2">
        {visiveis.length > 1 && (
          <select name="local" defaultValue={searchParams.local ?? ""} className="campo w-auto">
            <option value="">Todos os locais</option>
            {visiveis.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        )}
        {visiveis.length > 1 && (
          <select name="grupo" defaultValue={searchParams.grupo ?? ""} className="campo w-auto">
            <option value="">Todos os tipos de estoque</option>
            <option value="fixo">Estoques fixos</option>
            <option value="tec-pj">Estoque técnico PJ</option>
            <option value="tec-clt">Estoque técnico CLT</option>
          </select>
        )}
        <select name="categoria" defaultValue={searchParams.categoria ?? ""} className="campo w-auto">
          <option value="">Todas as categorias</option>
          {categorias.map(([id, nome]) => <option key={id} value={id}>{nome}</option>)}
        </select>
        <input name="q" defaultValue={searchParams.q ?? ""} placeholder="Buscar item" className="campo w-60" />
        <button className="btn-sec">Filtrar</button>
      </form>

      <div className="card overflow-x-auto p-0">
        <table className="w-full">
          <thead className="border-b border-slate-200">
            <tr><th className="th">Local</th><th className="th">Categoria</th><th className="th">Item</th><th className="th">Livre ou dedicado</th><th className="th text-right">Qtd.</th></tr>
          </thead>
          <tbody className="divide-y divide-slate-100">
            {linhas.map((s, i) => (
              <tr key={i}>
                <td className="td">{nomeLocal.get(s.local_id)}</td>
                <td className="td">{nomeProduto.get(s.produto_id)?.categoria?.nome}</td>
                <td className="td">{nomeProduto.get(s.produto_id)?.nome}</td>
                <td className="td">{s.reservado_unidade_id ? `Dedicado: ${nomeUn.get(s.reservado_unidade_id)}` : "Livre"}</td>
                <td className="td text-right font-medium">{s.quantidade}</td>
              </tr>
            ))}
            {linhas.length === 0 && <tr><td className="td text-slate-500" colSpan={5}>Nenhum item em estoque.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
}

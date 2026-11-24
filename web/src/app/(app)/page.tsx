import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getUsuario, getCatalogo, getLocais, nomeUnidade } from "@/lib/dados";
import { CHIPS } from "@/lib/types";

export const dynamic = "force-dynamic";

type Linha = { local_id: number; produto_id: number; condicao: string; reservado_unidade_id: number | null; quantidade: number };
// Ordem das colunas de chip dos módulos (condicao no banco: novo = sem chip).
const ORDEM_CHIPS = ["novo", "vivo", "claro", "arquia"] as const;
type LinhaTela = { local_id: number; produto_id: number; reservado_unidade_id: number | null; quantidade: number; chips: Record<string, number> | null };

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

  // Módulo com chip: uma linha por local/item/reserva, com o saldo de cada chip (inclusive os zerados) e o total.
  const agrupar = (lista: Linha[]) => {
    const saida: LinhaTela[] = [];
    const porChave = new Map<string, LinhaTela>();
    for (const s of lista) {
      if (!nomeProduto.get(s.produto_id)?.usa_chip) { saida.push({ ...s, chips: null }); continue; }
      const chave = `${s.local_id}|${s.produto_id}|${s.reservado_unidade_id ?? ""}`;
      let l = porChave.get(chave);
      if (!l) {
        l = { local_id: s.local_id, produto_id: s.produto_id, reservado_unidade_id: s.reservado_unidade_id, quantidade: 0,
              chips: Object.fromEntries(ORDEM_CHIPS.map((c) => [c, 0])) };
        porChave.set(chave, l);
        saida.push(l);
      }
      l.chips![s.condicao] = (l.chips![s.condicao] ?? 0) + s.quantidade;
      l.quantidade += s.quantidade;
    }
    return saida;
  };
  // O dedicado não entra na contagem geral: a tabela principal é só o estoque livre; o dedicado tem a seção própria.
  const linhasTela = agrupar(linhas.filter((s) => s.reservado_unidade_id === null));
  const dedicadas = agrupar(linhas.filter((s) => s.reservado_unidade_id !== null));
  const unidadesDedicadas = [...new Set(dedicadas.map((l) => l.reservado_unidade_id!))]
    .sort((a, b) => (nomeUn.get(a) ?? "").localeCompare(nomeUn.get(b) ?? "", "pt-BR"));

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

      <TabelaSaldo linhas={linhasTela} comLocal vazio="Nenhum item no estoque livre." nomeLocal={nomeLocal} nomeProduto={nomeProduto} />

      {/* Estoque dedicado: separado do livre, por cliente/unidade, com os próprios totais e as colunas de chip. */}
      <section className="space-y-3" aria-labelledby="titulo-dedicado">
        <h2 id="titulo-dedicado" className="text-lg font-semibold text-marinho-900">Estoque dedicado</h2>
        <p className="text-sm text-slate-600">Itens reservados para um cliente. Não entram no estoque livre acima nem no alerta de mínimo.</p>
        {unidadesDedicadas.length === 0 && <p className="text-sm text-slate-500">Nenhum item dedicado nos filtros escolhidos.</p>}
        {unidadesDedicadas.map((u) => {
          const doCliente = dedicadas.filter((l) => l.reservado_unidade_id === u);
          return (
            <div key={u} className="space-y-1" data-dedicado={nomeUn.get(u)}>
              <h3 className="text-sm font-medium">{nomeUn.get(u)} <span className="font-normal text-slate-500">· total {doCliente.reduce((a, l) => a + l.quantidade, 0)}</span></h3>
              <TabelaSaldo linhas={doCliente} comLocal vazio="" nomeLocal={nomeLocal} nomeProduto={nomeProduto} />
            </div>
          );
        })}
      </section>
    </div>
  );
}

// Tabela de saldo: módulos com chip mostram uma coluna por chip (o zero em cinza) e a quantidade total.
function TabelaSaldo({ linhas, comLocal, vazio, nomeLocal, nomeProduto }: {
  linhas: LinhaTela[]; comLocal?: boolean; vazio: string;
  nomeLocal: Map<number, string>; nomeProduto: Map<number, { nome: string; categoria?: { nome: string } | null }>;
}) {
  const temModulo = linhas.some((l) => l.chips);
  const colunas = (comLocal ? 3 : 2) + (temModulo ? ORDEM_CHIPS.length : 0);
  return (
    <div className="card overflow-x-auto p-0">
      <table className="w-full">
        <thead className="border-b border-slate-200">
          <tr>{comLocal && <th className="th">Local</th>}<th className="th">Categoria</th><th className="th">Item</th>
            {temModulo && ORDEM_CHIPS.map((c) => <th key={c} className="th text-right" title="Módulos: saldo por chip">{CHIPS[c]}</th>)}
            <th className="th text-right">{temModulo ? "Qtd. total" : "Qtd."}</th></tr>
        </thead>
        <tbody className="divide-y divide-slate-100">
          {linhas.map((s, i) => (
            <tr key={i}>
              {comLocal && <td className="td">{nomeLocal.get(s.local_id)}</td>}
              <td className="td">{nomeProduto.get(s.produto_id)?.categoria?.nome}</td>
              <td className="td">{nomeProduto.get(s.produto_id)?.nome}</td>
              {temModulo && ORDEM_CHIPS.map((c) => (
                <td key={c} data-chip={c} className={`td text-right ${s.chips && s.chips[c] === 0 ? "text-slate-400" : ""}`}>
                  {s.chips ? s.chips[c] : ""}
                </td>
              ))}
              <td className="td text-right font-medium">{s.quantidade}</td>
            </tr>
          ))}
          {linhas.length === 0 && vazio && <tr><td className="td text-slate-500" colSpan={colunas + 1}>{vazio}</td></tr>}
        </tbody>
      </table>
    </div>
  );
}

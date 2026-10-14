import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getUsuario } from "@/lib/dados";
import { Acao } from "@/components/Acao";
import { AtenderSolicitacao } from "@/components/AtenderSolicitacao";
import { SolicitacaoForm } from "@/components/SolicitacaoForm";

export const dynamic = "force-dynamic";

type Sol = {
  id: number; status: string; chamado_url: string | null; observacao: string | null; criado_em: string; tecnico_id: string;
  tecnico: { nome: string } | null; solicitacao_item: { produto_id: number; quantidade: number; produto: { nome: string } | null }[];
};

export default async function Solicitacoes() {
  const usuario = (await getUsuario())!;
  const sb = supabaseServer();
  const [{ operaveis }, cat, { data }] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("solicitacao").select("*, tecnico:usuario(nome), solicitacao_item(produto_id, quantidade, produto(nome))").order("id", { ascending: false }).limit(100),
  ]);
  const sols = (data ?? []) as unknown as Sol[];
  const operador = usuario.perfil === "admin" || usuario.perfil === "operador";
  const fixos = operaveis.filter((l) => l.tipo === "estoque");
  const rotulo: Record<string, string> = { aberta: "Aberta", atendida: "Atendida", cancelada: "Cancelada" };

  return (
    <div className="space-y-5">
      <h1 className="text-lg font-semibold">Solicitações de material</h1>
      {(usuario.perfil === "tecnico" || operador) && <SolicitacaoForm produtos={cat.produtos} associados={cat.associados} />}
      <div className="space-y-3">
        {sols.map((s) => (
          <div key={s.id} className="card text-sm">
            <div className="flex flex-wrap gap-x-3">
              <strong>{s.tecnico?.nome}</strong>
              <span className="rounded bg-slate-100 px-2 py-0.5 text-xs">{rotulo[s.status]}</span>
              <span className="text-slate-500">{new Date(s.criado_em).toLocaleString("pt-BR")}</span>
              {s.chamado_url && <a className="underline" href={s.chamado_url} target="_blank" rel="noreferrer">chamado</a>}
            </div>
            <ul className="mt-2 list-disc pl-5">{s.solicitacao_item.map((i, k) => <li key={k}>{i.quantidade}× {i.produto?.nome}</li>)}</ul>
            {s.observacao && <p className="mt-1 text-slate-600">{s.observacao}</p>}
            {s.status === "aberta" && operador && fixos.length > 0 && (
              <AtenderSolicitacao id={s.id} itens={s.solicitacao_item.map((i) => ({ produto_id: i.produto_id, quantidade: i.quantidade }))} origens={fixos} />
            )}
            {s.status === "aberta" && (s.tecnico_id === usuario.id || operador) && (
              <div className="mt-2"><Acao fn="cancelar_solicitacao" args={{ p_id: s.id }} texto="Cancelar pedido" secundario /></div>
            )}
          </div>
        ))}
        {sols.length === 0 && <p className="text-sm text-slate-500">Nenhuma solicitação.</p>}
      </div>
    </div>
  );
}

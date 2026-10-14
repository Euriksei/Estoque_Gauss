import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getUsuario } from "@/lib/dados";
import { Colapsavel } from "@/components/Colapsavel";
import { Acao } from "@/components/Acao";
import { AtenderSolicitacao } from "@/components/AtenderSolicitacao";
import { nomeUnidade } from "@/lib/types";
import { SolicitacaoForm } from "@/components/SolicitacaoForm";

export const dynamic = "force-dynamic";

type Sol = {
  id: number; status: string; chamado_url: string | null; observacao: string | null; criado_em: string; tecnico_id: string; origem_id: number | null; destino_id: number | null;
  tecnico: { nome: string } | null; solicitacao_item: { produto_id: number; quantidade: number; reservar_para_unidade_id: number | null; produto: { nome: string } | null }[];
};

export default async function Solicitacoes() {
  const usuario = (await getUsuario())!;
  const sb = supabaseServer();
  const [{ todos, operaveis }, cat, { data }] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("solicitacao").select("*, tecnico:usuario(nome), solicitacao_item(produto_id, quantidade, reservar_para_unidade_id, produto(nome))").order("id", { ascending: false }).limit(100),
  ]);
  const sols = (data ?? []) as unknown as Sol[];
  const operador = usuario.perfil === "admin" || usuario.perfil === "operador";
  const operaveisIds = new Set(operaveis.map((l) => l.id));
  const nomeUn = new Map(cat.unidades.map((u) => [u.id, nomeUnidade(u)]));
  const nomeLocal = new Map(todos.map((l) => [l.id, l.nome]));
  const podeSolicitar = usuario.perfil !== "consulta";
  const base = usuario.perfil === "tecnico" ? todos.find((l) => l.id === operaveis[0]?.base_id) : undefined;
  const rotulo: Record<string, string> = { aberta: "Aberta", atendida: "Atendida", cancelada: "Cancelada" };

  return (
    <div className="space-y-5">
      <h1 className="text-xl font-bold text-marinho-900">Solicitações de material</h1>
      {podeSolicitar && (
        <Colapsavel rotulo="Nova solicitação">
          <SolicitacaoForm produtos={cat.produtos} associados={cat.associados} unidades={cat.unidades} locais={todos}
            tecnicoBase={usuario.perfil === "tecnico" ? (base ? { nome: base.nome } : null) : undefined} />
        </Colapsavel>
      )}
      {[{ titulo: "Pendentes", lista: sols.filter((s) => s.status === "aberta") }, { titulo: "Concluídas e canceladas", lista: sols.filter((s) => s.status !== "aberta") }].map((g) => (
        <section key={g.titulo} className="space-y-3">
          <h2 className="font-medium">{g.titulo} ({g.lista.length})</h2>
          {g.lista.map((s) => (
            <div key={s.id} className="card text-sm">
              <div className="flex flex-wrap gap-x-3">
                <strong>{s.origem_id ? nomeLocal.get(s.origem_id) : "?"} → {s.destino_id ? nomeLocal.get(s.destino_id) : s.tecnico?.nome}</strong>
                <span className="rounded bg-slate-100 px-2 py-0.5 text-xs">{rotulo[s.status]}</span>
                <span className="text-slate-500">pedido por {s.tecnico?.nome} em {new Date(s.criado_em).toLocaleString("pt-BR")}</span>
                {s.chamado_url && <a className="underline" href={s.chamado_url} target="_blank" rel="noreferrer">chamado</a>}
              </div>
              <ul className="mt-2 list-disc pl-5">{s.solicitacao_item.map((i, k) => <li key={k}>{i.quantidade}× {i.produto?.nome}{i.reservar_para_unidade_id && ` · dedicado: ${nomeUn.get(i.reservar_para_unidade_id)}`}</li>)}</ul>
              {s.observacao && <p className="mt-1 text-slate-600">{s.observacao}</p>}
              {s.status === "aberta" && operador && s.origem_id != null && operaveisIds.has(s.origem_id) && (
                <AtenderSolicitacao id={s.id} />
              )}
              {s.status === "aberta" && (s.tecnico_id === usuario.id || operador) && (
                <div className="mt-2"><Acao fn="cancelar_solicitacao" args={{ p_id: s.id }} texto="Cancelar solicitação" secundario /></div>
              )}
            </div>
          ))}
          {g.lista.length === 0 && <p className="text-sm text-slate-500">Nenhuma.</p>}
        </section>
      ))}
    </div>
  );
}

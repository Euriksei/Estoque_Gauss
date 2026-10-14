import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getUsuario } from "@/lib/dados";
import { Colapsavel } from "@/components/Colapsavel";
import { Acao } from "@/components/Acao";
import { AtenderSolicitacao } from "@/components/AtenderSolicitacao";
import { nomeUnidade } from "@/lib/types";
import { SolicitacaoForm } from "@/components/SolicitacaoForm";

export const dynamic = "force-dynamic";

type Sol = {
  id: number; status: string; chamado_url: string | null; observacao: string | null; criado_em: string; prazo_producao: string | null; tecnico_id: string; origem_id: number | null; destino_id: number | null;
  tecnico: { nome: string } | null; solicitacao_item: { produto_id: number; quantidade: number; reservar_para_unidade_id: number | null; produto: { nome: string } | null }[];
};

export default async function Solicitacoes() {
  const usuario = (await getUsuario())!;
  const sb = supabaseServer();
  const [{ todos, operaveis }, cat, { data }] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("solicitacao").select("*, tecnico:usuario(nome), solicitacao_item(produto_id, quantidade, reservar_para_unidade_id, produto(nome))").order("id", { ascending: false }).limit(100),
  ]);
  // Técnico vê só as solicitações em nome dele.
  const sols = ((data ?? []) as unknown as Sol[]).filter((s) => usuario.perfil !== "tecnico" || s.tecnico_id === usuario.id);
  const operador = usuario.perfil === "admin" || usuario.perfil === "operador";
  const operaveisIds = new Set(operaveis.map((l) => l.id));
  const nomeUn = new Map(cat.unidades.map((u) => [u.id, nomeUnidade(u)]));
  const nomeLocal = new Map(todos.map((l) => [l.id, l.nome]));
  const podeSolicitar = usuario.perfil !== "consulta";
  const base = usuario.perfil === "tecnico" ? todos.find((l) => l.id === operaveis[0]?.base_id) : undefined;
  const rotulo: Record<string, string> = { aberta: "Aberta", em_producao: "Em produção", atendida: "Atendida", cancelada: "Cancelada" };

  return (
    <div className="space-y-5">
      <h1 className="text-xl font-bold text-marinho-900">Solicitações de material</h1>
      {podeSolicitar && (
        <Colapsavel rotulo="Nova solicitação">
          <SolicitacaoForm produtos={cat.produtos} associados={cat.associados} unidades={cat.unidades} locais={todos}
            tecnicoBase={usuario.perfil === "tecnico" ? (base ? { nome: base.nome } : null) : undefined} />
        </Colapsavel>
      )}
      {[{ titulo: "Pendentes", lista: sols.filter((s) => s.status === "aberta") }, { titulo: "Em produção", lista: sols.filter((s) => s.status === "em_producao") }, { titulo: "Concluídas e canceladas", lista: sols.filter((s) => s.status === "atendida" || s.status === "cancelada") }].map((g) => (
        <section key={g.titulo} className="space-y-3">
          <h2 className="font-medium">{g.titulo} ({g.lista.length})</h2>
          {g.lista.map((s) => (
            <div key={s.id} className="card text-sm">
              <div className="flex flex-wrap gap-x-3">
                <strong>{s.origem_id ? nomeLocal.get(s.origem_id) : "?"} → {s.destino_id ? nomeLocal.get(s.destino_id) : s.tecnico?.nome}</strong>
                <span className={`rounded px-2 py-0.5 text-xs ${s.status === "em_producao" ? "bg-amber-100" : s.status === "atendida" ? "bg-green-100" : "bg-slate-100"}`}>{rotulo[s.status]}</span>
                {s.status === "em_producao" && s.prazo_producao && (
                  <span className={new Date(s.prazo_producao) < new Date() ? "font-medium text-marca-700" : "text-slate-500"}>
                    prazo até {new Date(s.prazo_producao).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short" })}{new Date(s.prazo_producao) < new Date() && " (atrasada)"}
                  </span>
                )}
                <span className="text-slate-500">pedido por {s.tecnico?.nome} em {new Date(s.criado_em).toLocaleString("pt-BR")}</span>
                {s.chamado_url && <a className="underline" href={s.chamado_url} target="_blank" rel="noreferrer">chamado</a>}
              </div>
              <ul className="mt-2 list-disc pl-5">{s.solicitacao_item.map((i, k) => <li key={k}>{i.quantidade}× {i.produto?.nome}{i.reservar_para_unidade_id && ` · dedicado: ${nomeUn.get(i.reservar_para_unidade_id)}`}</li>)}</ul>
              {s.observacao && <p className="mt-1 text-slate-600">{s.observacao}</p>}
              {s.status === "aberta" && operador && s.origem_id != null && operaveisIds.has(s.origem_id) && (
                <div className="mt-2"><Acao fn="aceitar_solicitacao" args={{ p_id: s.id }} texto="Aceitar (iniciar produção)" /></div>
              )}
              {s.status === "em_producao" && operador && s.origem_id != null && operaveisIds.has(s.origem_id) && (
                <AtenderSolicitacao id={s.id} />
              )}
              {(s.status === "aberta" ? (s.tecnico_id === usuario.id || operador) : s.status === "em_producao" && operador) && (
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

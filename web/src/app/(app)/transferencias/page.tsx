import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getUsuario } from "@/lib/dados";
import { Colapsavel } from "@/components/Colapsavel";
import { Acao } from "@/components/Acao";
import { TransferenciaForm } from "@/components/TransferenciaForm";
import { STATUS, nomeUnidade } from "@/lib/types";

export const dynamic = "force-dynamic";

type Mov = {
  id: number; status: string; data: string; modo_envio: string | null; codigo_rastreio: string | null; prazo_chegada: string | null;
  local_origem_id: number; local_destino_id: number; observacao: string | null; recebido_em: string | null;
  movimentacao_item: { quantidade: number; reservar_para_unidade_id: number | null; reservado_unidade_id: number | null; produto: { nome: string } | null }[];
};

export default async function Transferencias() {
  const usuario = (await getUsuario())!;
  const sb = supabaseServer();
  const [{ todos, operaveis }, cat, { data }] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("movimentacao")
      .select("id,status,data,modo_envio,codigo_rastreio,prazo_chegada,local_origem_id,local_destino_id,observacao,recebido_em, movimentacao_item(quantidade,reservar_para_unidade_id,reservado_unidade_id, produto(nome))")
      .eq("tipo", "TRANSFERENCIA").order("id", { ascending: false }).limit(100),
  ]);
  const movs = (data ?? []) as unknown as Mov[];
  const nome = new Map(todos.map((l) => [l.id, l.nome]));
  const nomeUn = new Map(cat.unidades.map((u) => [u.id, nomeUnidade(u)]));
  const meus = new Set(operaveis.map((l) => l.id));
  const ehOperador = usuario.perfil === "admin" || usuario.perfil === "operador";
  const tipoLocal = new Map(todos.map((l) => [l.id, l.tipo]));
  const baseLocal = new Map(todos.map((l) => [l.id, l.base_id]));
  // Quem opera o destino confirma. Quando o destino é estoque de técnico, o operador do estoque de origem
  // ou da base do técnico também confirma (técnico sem login).
  const podeConfirmar = (m: Mov) =>
    meus.has(m.local_destino_id) ||
    (ehOperador && tipoLocal.get(m.local_destino_id) === "tecnico" &&
      (meus.has(m.local_origem_id) || (baseLocal.get(m.local_destino_id) != null && meus.has(baseLocal.get(m.local_destino_id)!))));
  const podeEnviar = usuario.perfil === "admin" || usuario.perfil === "operador";

  return (
    <div className="space-y-5">
      <h1 className="text-lg font-semibold">Transferências</h1>
      {podeEnviar && operaveis.length > 0 && (
        <Colapsavel rotulo="Nova transferência"><TransferenciaForm origens={operaveis} destinos={todos} produtos={cat.produtos} unidades={cat.unidades} associados={cat.associados} /></Colapsavel>
      )}
      {[{ titulo: "Em andamento", lista: movs.filter((m) => m.status === "em_transito") }, { titulo: "Concluídas e canceladas", lista: movs.filter((m) => m.status !== "em_transito") }].map((g) => (
      <section key={g.titulo} className="space-y-3">
        <h2 className="font-medium">{g.titulo} ({g.lista.length})</h2>
        {g.lista.map((m) => (
          <div key={m.id} className="card text-sm">
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
              <strong>{nome.get(m.local_origem_id)} → {nome.get(m.local_destino_id)}</strong>
              <span className={`rounded px-2 py-0.5 text-xs ${m.status === "em_transito" ? "bg-amber-100" : m.status === "recebido" ? "bg-green-100" : "bg-slate-100"}`}>{STATUS[m.status]}</span>
              <span className="text-slate-500">enviada em {m.data}{m.prazo_chegada && ` · prazo ${m.prazo_chegada}`}{m.modo_envio && ` · ${m.modo_envio}`}{m.codigo_rastreio && ` · rastreio ${m.codigo_rastreio}`}</span>
            </div>
            <ul className="mt-2 list-disc pl-5">
              {m.movimentacao_item.map((i, k) => (
                <li key={k}>{i.quantidade}× {i.produto?.nome}{(i.reservar_para_unidade_id || i.reservado_unidade_id) && ` · dedicado: ${nomeUn.get((i.reservar_para_unidade_id ?? i.reservado_unidade_id)!)}`}</li>
              ))}
            </ul>
            {m.observacao && <p className="mt-1 text-slate-600">{m.observacao}</p>}
            {m.status === "em_transito" && (
              <div className="mt-2 flex gap-2">
                {podeConfirmar(m) && <Acao fn="confirmar_recebimento" args={{ p_id: m.id }} texto="Confirmar recebimento" />}
                {meus.has(m.local_origem_id) && <Acao fn="cancelar_transferencia" args={{ p_id: m.id }} texto="Cancelar envio" secundario pedirMotivo />}
              </div>
            )}
          </div>
        ))}
        {g.lista.length === 0 && <p className="text-sm text-slate-500">Nenhuma.</p>}
      </section>
      ))}
    </div>
  );
}

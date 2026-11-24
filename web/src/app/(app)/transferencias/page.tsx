import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getUsuario } from "@/lib/dados";
import { Colapsavel } from "@/components/Colapsavel";
import { Acao } from "@/components/Acao";
import { AtenderSolicitacao } from "@/components/AtenderSolicitacao";
import { PedidoCard } from "@/components/PedidoCard";
import { TransferenciaForm, type DedicadoNoLocal } from "@/components/TransferenciaForm";
import { SELECT_PEDIDO, STATUS, nomeItem, nomeModo, nomeUnidade, type AcoesPedido, type Pedido } from "@/lib/types";

export const dynamic = "force-dynamic";

type Mov = {
  id: number; status: string; data: string; modo_envio: string | null; codigo_rastreio: string | null; prazo_chegada: string | null;
  local_origem_id: number; local_destino_id: number; observacao: string | null;
  movimentacao_item: { quantidade: number; condicao: string; reservar_para_unidade_id: number | null; reservado_unidade_id: number | null; produto: { nome: string; usa_chip: boolean } | null }[];
};

// Transferências = pedido entre estoques: admin/operador pede; a origem aceita (em produção, prazo de 1 dia),
// prepara e envia (em trânsito); o destino confirma o recebimento.
export default async function Transferencias() {
  const usuario = (await getUsuario())!;
  const sb = supabaseServer();
  const [{ todos, operaveis }, cat, ped, acoes, movsRes, ded] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("solicitacao").select(SELECT_PEDIDO).in("tipo", ["transferencia", "legado"]).order("id", { ascending: false }).limit(200),
    sb.from("solicitacao_acoes").select("id,situacao,pode_aceitar,pode_atender,pode_cancelar"),
    sb.from("movimentacao")
      .select("id,status,data,modo_envio,codigo_rastreio,prazo_chegada,local_origem_id,local_destino_id,observacao, movimentacao_item(quantidade,condicao,reservar_para_unidade_id,reservado_unidade_id, produto(nome,usa_chip))")
      .eq("tipo", "TRANSFERENCIA").order("id", { ascending: false }).limit(200),
    sb.from("dedicados_posicao").select("unidade_id,local_id,produto_id,condicao,quantidade").eq("situacao", "em_local"),
  ]);
  const pedidos = (ped.data ?? []) as unknown as Pedido[];
  const acao = new Map(((acoes.data ?? []) as AcoesPedido[]).map((a) => [a.id, a]));
  const movs = (movsRes.data ?? []) as unknown as Mov[];
  const mov = new Map(movs.map((m) => [m.id, m]));
  const dedicados = (ded.data ?? []) as DedicadoNoLocal[];
  const prod = new Map(cat.produtos.map((p) => [p.id, p]));
  const nome = new Map(todos.map((l) => [l.id, l.nome]));
  const nomeUn = new Map(cat.unidades.map((u) => [u.id, nomeUnidade(u)]));
  const meus = new Set(operaveis.map((l) => l.id));
  const ehOperador = usuario.perfil === "admin" || usuario.perfil === "operador";
  const tipoLocal = new Map(todos.map((l) => [l.id, l.tipo]));
  const baseLocal = new Map(todos.map((l) => [l.id, l.base_id]));
  // Confirmar recebimento (sem mudança no banco): quem opera o destino; se o destino é estoque de técnico,
  // também o operador da origem ou da base do técnico (técnico sem login).
  const podeConfirmar = (m: Mov) =>
    meus.has(m.local_destino_id) ||
    (ehOperador && tipoLocal.get(m.local_destino_id) === "tecnico" &&
      (meus.has(m.local_origem_id) || (baseLocal.get(m.local_destino_id) != null && meus.has(baseLocal.get(m.local_destino_id)!))));
  const resumoEnvio = (m: Mov) => [`enviada em ${m.data}`, m.modo_envio && nomeModo(m.modo_envio), m.codigo_rastreio && `rastreio ${m.codigo_rastreio}`, m.prazo_chegada && `prazo de chegada ${m.prazo_chegada}`].filter(Boolean).join(" · ");
  const itensMov = (m: Mov) => m.movimentacao_item.map((i) => `${i.quantidade}× ${nomeItem(i.produto?.nome, i.produto?.usa_chip, i.condicao)}`).join("\n");
  // O que o dedicado de uma unidade leva hoje na origem do pedido.
  const junto = (origem: number | null) => (u: number) => dedicados.filter((d) => d.local_id === origem && d.unidade_id === u && d.quantidade > 0)
    .map((d) => `${d.quantidade}× ${nomeItem(prod.get(d.produto_id)?.nome, prod.get(d.produto_id)?.usa_chip, d.condicao)}`);

  // Transferências feitas direto (antes dos pedidos), sem pedido ligado: continuam visíveis para concluir.
  const ligadas = new Set(pedidos.map((s) => s.movimentacao_id).filter((x): x is number => x != null));
  const diretas = movs.filter((m) => !ligadas.has(m.id) && (usuario.perfil !== "tecnico" || meus.has(m.local_destino_id)));
  const situacao = (s: Pedido) => acao.get(s.id)?.situacao ?? s.status;
  const grupos = [
    { titulo: "Pendentes", sit: ["aberta"] },
    { titulo: "Em produção", sit: ["em_producao"] },
    { titulo: "Em trânsito", sit: ["em_transito"] },
    { titulo: "Concluídas", sit: ["recebido", "atendida", "cancelada"] },
  ];

  const cartaoPedido = (s: Pedido) => {
    const a = acao.get(s.id);
    const sit = situacao(s);
    const m = s.movimentacao_id ? mov.get(s.movimentacao_id) : undefined;
    const modulos = s.solicitacao_item.filter((i) => i.produto?.usa_chip && !i.condicao).map((i) => ({ id: i.id, nome: i.produto?.nome ?? "" }));
    return (
      <PedidoCard key={`p${s.id}`} s={s} situacao={sit} nomeUn={nomeUn} dedicadoJunto={sit === "aberta" || sit === "em_producao" ? junto(s.origem_id) : undefined}
        de={s.origem_id ? nome.get(s.origem_id) ?? "?" : "?"} para={s.destino_id ? nome.get(s.destino_id) ?? "?" : "?"} envio={m ? resumoEnvio(m) : undefined}>
        {a?.pode_aceitar && <Acao fn="aceitar_solicitacao" args={{ p_id: s.id }} texto="Aceitar" />}
        {a?.pode_atender && <AtenderSolicitacao id={s.id} tipo="transferencia" modulos={modulos} />}
        {m && m.status === "em_transito" && podeConfirmar(m) && <Acao fn="confirmar_recebimento" args={{ p_id: m.id }} texto="Confirmar recebimento" confirmar={`Confirma que recebeu:\n${itensMov(m)}`} />}
        {m && m.status === "em_transito" && usuario.perfil !== "tecnico" && meus.has(m.local_origem_id) && <Acao fn="cancelar_transferencia" args={{ p_id: m.id }} texto="Cancelar envio" secundario pedirMotivo />}
        {a?.pode_cancelar && <Acao fn="cancelar_solicitacao" args={{ p_id: s.id }} texto="Cancelar pedido" secundario confirmar="Cancelar este pedido?" />}
      </PedidoCard>
    );
  };

  const cartaoDireta = (m: Mov) => (
    <div key={`m${m.id}`} className="card text-sm">
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <strong>{nome.get(m.local_origem_id)} → {nome.get(m.local_destino_id)}</strong>
        <span className={`rounded px-2 py-0.5 text-xs ${m.status === "em_transito" ? "bg-sky-100" : m.status === "recebido" ? "bg-green-100" : "bg-slate-100"}`}>{STATUS[m.status]}</span>
        <span className="text-xs text-slate-500">transferência direta (antiga)</span>
        <span className="text-slate-500">{resumoEnvio(m)}</span>
      </div>
      <ul className="mt-2 list-disc pl-5">
        {m.movimentacao_item.map((i, k) => (
          <li key={k}>{i.quantidade}× {nomeItem(i.produto?.nome, i.produto?.usa_chip, i.condicao)}{(i.reservar_para_unidade_id || i.reservado_unidade_id) && ` · dedicado: ${nomeUn.get((i.reservar_para_unidade_id ?? i.reservado_unidade_id)!)}`}</li>
        ))}
      </ul>
      {m.observacao && <p className="mt-1 text-slate-600">{m.observacao}</p>}
      {m.status === "em_transito" && (
        <div className="mt-2 flex gap-2">
          {podeConfirmar(m) && <Acao fn="confirmar_recebimento" args={{ p_id: m.id }} texto="Confirmar recebimento" confirmar={`Confirma que recebeu:\n${itensMov(m)}`} />}
          {usuario.perfil !== "tecnico" && meus.has(m.local_origem_id) && <Acao fn="cancelar_transferencia" args={{ p_id: m.id }} texto="Cancelar envio" secundario pedirMotivo />}
        </div>
      )}
    </div>
  );

  return (
    <div className="space-y-5">
      <h1 className="text-xl font-bold text-marinho-900">Transferências</h1>
      <p className="text-sm text-slate-600">Pedido de material entre estoques. O saldo só sai quando a origem aceita, prepara e envia; entra no destino quando ele confirma o recebimento.</p>
      {ehOperador && (
        <Colapsavel rotulo="Novo pedido de transferência">
          <TransferenciaForm origens={todos.filter((l) => l.tipo === "estoque")} destinos={todos} produtos={cat.produtos} unidades={cat.unidades} associados={cat.associados} dedicados={dedicados} />
        </Colapsavel>
      )}
      {grupos.map((g) => {
        const lista = pedidos.filter((s) => g.sit.includes(situacao(s)));
        const antigas = g.titulo === "Em trânsito" ? diretas.filter((m) => m.status === "em_transito") : g.titulo === "Concluídas" ? diretas.filter((m) => m.status !== "em_transito") : [];
        return (
          <section key={g.titulo} className="space-y-3">
            <h2 className="font-medium">{g.titulo} ({lista.length + antigas.length})</h2>
            {lista.map(cartaoPedido)}
            {antigas.map(cartaoDireta)}
            {lista.length + antigas.length === 0 && <p className="text-sm text-slate-500">Nenhuma.</p>}
          </section>
        );
      })}
    </div>
  );
}

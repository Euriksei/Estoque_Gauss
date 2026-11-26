import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getTecnicos, getUsuario } from "@/lib/dados";
import { Colapsavel } from "@/components/Colapsavel";
import { Acao } from "@/components/Acao";
import { AtenderSolicitacao } from "@/components/AtenderSolicitacao";
import { PedidoCard } from "@/components/PedidoCard";
import { SolicitacaoForm } from "@/components/SolicitacaoForm";
import type { DedicadoNoLocal } from "@/components/TransferenciaForm";
import { SELECT_PEDIDO, nomeItem, nomeUnidade, type AcoesPedido, type Pedido } from "@/lib/types";

export const dynamic = "force-dynamic";

// Solicitações = o agendamento pede envio para cliente (itens livres ou dedicado inteiro) ou a retirada de
// um dedicado no cliente. O estoque aceita (em produção, prazo de 1 dia) e atende.
export default async function Solicitacoes() {
  const usuario = (await getUsuario())!;
  // O técnico só usa Transferências.
  if ((usuario.perfil as string) === "tecnico") redirect("/transferencias");
  const sb = supabaseServer();
  const [{ todos }, cat, ped, acoes, ded, tecnicos] = await Promise.all([
    getLocais(usuario), getCatalogo(),
    sb.from("solicitacao").select(SELECT_PEDIDO).in("tipo", ["enviar_cliente", "enviar_dedicado", "retirar_dedicado"]).order("id", { ascending: false }).limit(200),
    sb.from("solicitacao_acoes").select("id,situacao,pode_aceitar,pode_atender,pode_cancelar"),
    sb.from("dedicados_posicao").select("unidade_id,local_id,produto_id,condicao,quantidade").eq("situacao", "em_local"),
    getTecnicos(),
  ]);
  const pedidos = (ped.data ?? []) as unknown as Pedido[];
  const acao = new Map(((acoes.data ?? []) as AcoesPedido[]).map((a) => [a.id, a]));
  const dedicados = (ded.data ?? []) as DedicadoNoLocal[];
  const prod = new Map(cat.produtos.map((p) => [p.id, p]));
  const nomeUn = new Map(cat.todasUnidades.map((u) => [u.id, nomeUnidade(u)]));
  const nomeLocal = new Map(todos.map((l) => [l.id, l.nome]));
  const estoques = todos.filter((l) => l.tipo === "estoque");
  const situacao = (s: Pedido) => acao.get(s.id)?.situacao ?? s.status;
  const junto = (origem: number | null) => (u: number) => dedicados.filter((d) => d.local_id === origem && d.unidade_id === u && d.quantidade > 0)
    .map((d) => `${d.quantidade}× ${nomeItem(prod.get(d.produto_id)?.nome, prod.get(d.produto_id)?.usa_chip, d.condicao)}`);
  const grupos = [
    { titulo: "Pendentes", sit: ["aberta"] },
    { titulo: "Em produção", sit: ["em_producao"] },
    { titulo: "Concluídas e canceladas", sit: ["atendida", "cancelada", "em_transito", "recebido"] },
  ];

  return (
    <div className="space-y-5">
      <h1 className="text-xl font-bold text-marinho-900">Solicitações de envio ao cliente</h1>
      <p className="text-sm text-slate-600">O agendamento (ou o administrador) pede: enviar itens ao cliente, enviar o dedicado inteiro de um cliente ou retirar um dedicado no cliente. O estoque aceita e atende.</p>
      {(usuario.perfil === "agendamento" || usuario.perfil === "admin") && (
        <Colapsavel rotulo="Nova solicitação">
          <SolicitacaoForm produtos={cat.produtos} associados={cat.associados} unidades={cat.unidades} estoques={estoques} dedicados={dedicados} />
        </Colapsavel>
      )}
      {grupos.map((g) => {
        const lista = pedidos.filter((s) => g.sit.includes(situacao(s)));
        return (
          <section key={g.titulo} className="space-y-3">
            <h2 className="font-medium">{g.titulo} ({lista.length})</h2>
            {lista.map((s) => {
              const a = acao.get(s.id);
              const sit = situacao(s);
              const retirar = s.tipo === "retirar_dedicado";
              const cliente = s.unidade_id ? nomeUn.get(s.unidade_id) ?? "cliente" : "cliente";
              const modulos = s.solicitacao_item.filter((i) => i.produto?.usa_chip && !i.condicao).map((i) => ({ id: i.id, nome: i.produto?.nome ?? "" }));
              return (
                <PedidoCard key={s.id} s={s} situacao={sit} nomeUn={nomeUn} dedicadoJunto={sit === "aberta" || sit === "em_producao" ? junto(s.origem_id) : undefined}
                  de={retirar ? cliente : s.origem_id ? nomeLocal.get(s.origem_id) ?? "?" : "?"}
                  para={retirar ? (s.destino_id ? nomeLocal.get(s.destino_id) ?? "?" : "?") : cliente}>
                  {a?.pode_aceitar && <Acao fn="aceitar_solicitacao" args={{ p_id: s.id }} texto="Aceitar" />}
                  {a?.pode_atender && <AtenderSolicitacao id={s.id} tipo={retirar ? "chegada" : "cliente"} modulos={modulos} tecnicos={tecnicos.filter((t) => t.ativo)} />}
                  {a?.pode_cancelar && <Acao fn="cancelar_solicitacao" args={{ p_id: s.id }} texto="Cancelar solicitação" secundario confirmar="Cancelar esta solicitação?" />}
                </PedidoCard>
              );
            })}
            {lista.length === 0 && <p className="text-sm text-slate-500">Nenhuma.</p>}
          </section>
        );
      })}
    </div>
  );
}

import { CHIPS, SITUACOES, TIPOS_PEDIDO, type Pedido } from "@/lib/types";

const COR: Record<string, string> = {
  aberta: "bg-slate-100", em_producao: "bg-amber-100", em_transito: "bg-sky-100", recebido: "bg-green-100", atendida: "bg-green-100", cancelada: "bg-slate-100",
};

// Cartão de um pedido (Transferências e Solicitações): de onde para onde, situação, prazo de produção
// (com aviso de atraso), cliente, itens e dedicados que vão inteiros. As ações entram como children.
export function PedidoCard({ s, situacao, de, para, nomeUn, dedicadoJunto, envio, children }: {
  s: Pedido; situacao: string; de: string; para: string; nomeUn: Map<number, string>;
  // O que cada dedicado do pedido leva hoje (saldo dedicado da unidade na origem), para mostrar antes do envio.
  dedicadoJunto?: (unidadeId: number) => string[];
  envio?: string; // resumo do envio (data, meio, rastreio, prazo), quando já foi enviado
  children?: React.ReactNode;
}) {
  const agora = new Date();
  const atrasada = situacao === "em_producao" && s.prazo_producao && new Date(s.prazo_producao) < agora;
  const nomeItem = (i: Pedido["solicitacao_item"][number]) =>
    `${i.produto?.nome ?? ""}${i.produto?.usa_chip ? ` (${i.condicao ? CHIPS[i.condicao] ?? i.condicao : "chip escolhido no envio"})` : ""}`;
  return (
    <div className="card text-sm" data-pedido={s.id}>
      <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
        <strong>{de} → {para}</strong>
        <span className={`rounded px-2 py-0.5 text-xs ${COR[situacao] ?? "bg-slate-100"}`}>{SITUACOES[situacao] ?? situacao}</span>
        <span className="text-xs text-slate-500">{TIPOS_PEDIDO[s.tipo] ?? s.tipo} #{s.id}</span>
        {situacao === "em_producao" && s.prazo_producao && (
          <span className={atrasada ? "font-medium text-marca-700" : "text-slate-500"}>
            prazo até {new Date(s.prazo_producao).toLocaleString("pt-BR", { dateStyle: "short", timeStyle: "short", timeZone: "America/Sao_Paulo" })}{atrasada && " (atrasado)"}
          </span>
        )}
        {s.finalidade && <span>finalidade: <strong>{s.finalidade === "mobilizacao" ? "Mobilização" : s.finalidade === "manutencao" ? "Manutenção" : s.finalidade}</strong></span>}
        {s.unidade_id && <span>cliente: <strong>{nomeUn.get(s.unidade_id)}</strong></span>}
        <span className="text-slate-500">pedido por {s.criador?.nome ?? "-"} em {new Date(s.criado_em).toLocaleString("pt-BR", { timeZone: "America/Sao_Paulo" })}</span>
        {s.chamado_url && <a className="underline" href={s.chamado_url} target="_blank" rel="noreferrer">chamado</a>}
      </div>
      {envio && <p className="mt-1 text-slate-500">{envio}</p>}
      {(s.solicitacao_item.length > 0 || s.solicitacao_dedicado.length > 0) && (
        <ul className="mt-2 list-disc pl-5">
          {s.solicitacao_item.map((i) => (
            <li key={i.id}>{i.quantidade}× {nomeItem(i)}
              {i.reservar_para_unidade_id && ` · dedicado para: ${nomeUn.get(i.reservar_para_unidade_id)}`}
              {i.reservado_unidade_id && ` · sai do dedicado de: ${nomeUn.get(i.reservado_unidade_id)}`}</li>
          ))}
          {s.solicitacao_dedicado.map((d) => {
            const junto = dedicadoJunto?.(d.unidade_id) ?? [];
            return (
              <li key={`d${d.unidade_id}`}>Dedicado inteiro de <strong>{nomeUn.get(d.unidade_id)}</strong>
                {junto.length > 0 && <span className="text-slate-600">: {junto.join(", ")}</span>}</li>
            );
          })}
        </ul>
      )}
      {s.tipo === "enviar_dedicado" && (
        <p className="mt-2">Vai o dedicado inteiro de <strong>{s.unidade_id ? nomeUn.get(s.unidade_id) : "-"}</strong>
          {s.unidade_id && (dedicadoJunto?.(s.unidade_id) ?? []).length > 0 && <span className="text-slate-600">: {dedicadoJunto!(s.unidade_id).join(", ")}</span>}</p>
      )}
      {s.observacao && <p className="mt-1 text-slate-600">{s.observacao}</p>}
      {children && <div className="mt-2 flex flex-wrap items-start gap-2">{children}</div>}
    </div>
  );
}

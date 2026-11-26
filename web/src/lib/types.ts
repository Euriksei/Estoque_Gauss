export type Perfil = "admin" | "operador" | "tecnico" | "consulta" | "agendamento";

// "Ver como" do administrador (view minha_visualizacao). perfil_real é o da tabela usuario; o perfil efetivo vai em Usuario.perfil.
export type Visao = {
  perfil_real: Perfil; perfil: Perfil; simulando: boolean; local_id: number | null; local_nome: string | null;
  tecnico_id: number | null; tecnico_nome: string | null; locais_operaveis: number[] | null;
};
// perfil = perfil EFETIVO (o simulado, quando o administrador está vendo como outro perfil).
export type Usuario = { id: string; nome: string; email: string; perfil: Perfil; ativo: boolean; visao?: Visao | null };
export type Vinculo = "pj" | "clt";
export type Tecnico = { id: number; nome: string; vinculo: Vinculo; usuario_id: string | null; ativo: boolean };
export type Local = {
  id: number; nome: string; tipo: "estoque" | "tecnico"; tecnico_id: number | null; base_id: number | null;
  tecnico?: { nome: string; vinculo: Vinculo; usuario_id: string | null } | null;
};
export type Produto = { id: number; nome: string; categoria_id: number | null; fabricante: string | null; estoque_minimo: number; usa_chip?: boolean; chip_tipo?: string | null; chip_rede?: string | null; ativo?: boolean; categoria?: { nome: string } | null };
export type Unidade = { id: number; nome: string; cliente_id: number; ativo?: boolean; cliente?: { nome: string; ativo?: boolean } | null };
export const nomeUnidade = (u: Unidade) => `${u.cliente?.nome ?? ""} - ${u.nome}`;
// Kit do item (item_associado): opcional vem desmarcado; mesmo grupo = escolha de um só (ex.: Case).
export type Associado = { produto_id: number; associado_id: number; quantidade: number; opcional?: boolean; grupo?: string | null };
// Tipo de chip: módulos usam M2M; MDVR e DashCAM usam Voz e Dados.
export const REDES: Record<string, string> = { m2m: "M2M", voz_dados: "Voz e Dados" };

export type ItemForm = {
  produto_id: number | "";
  quantidade: number;
  reservado_unidade_id?: number | "";
  reservar_para_unidade_id?: number | "";
  sentido?: "mais" | "menos"; // só no ajuste de inventário
  chip?: string; // chip do módulo: novo (sem chip), claro, vivo ou arqia
  kitAberto?: boolean; // "Kit completo" desmarcado: o usuário escolhe periférico a periférico
  kit?: Record<string, { on?: boolean }>; // ajustes do kit por periférico (chave: id, ou "case>plug")
  kitGrupo?: Record<string, number>; // grupo do kit -> item escolhido (0 = nenhum)
};

// Chips dos módulos de telemetria. "novo" é o valor guardado no banco para módulo sem chip.
export const CHIPS: Record<string, string> = { novo: "Sem chip", claro: "Claro", vivo: "Vivo", arqia: "Arqia" };
// Nome do item para mostrar: módulos com chip ganham o chip entre parênteses.
export const nomeItem = (nome: string | undefined | null, usaChip: boolean | undefined, chip: string | null | undefined) =>
  `${nome ?? ""}${usaChip ? ` (${CHIPS[chip ?? "novo"] ?? chip})` : ""}`;

export const TIPOS: Record<string, string> = {
  TROCA_CHIP: "Troca de chip",
  ENTRADA_COMPRA: "Entrada por compra",
  DEVOLUCAO_CLIENTE: "Devolução de cliente",
  SAIDA_CLIENTE: "Saída para cliente",
  ENVIO_TECNICO: "Envio para estoque técnico",
  CONSUMO_INTERNO: "Consumo interno / teste",
  DESCARTE: "Descarte",
  AJUSTE: "Ajuste de inventário",
  TRANSFERENCIA: "Transferência",
  SAIDA_TECNICO: "Saída para estoque técnico",
};

export const STATUS: Record<string, string> = {
  registrado: "Registrado",
  em_transito: "Em trânsito",
  recebido: "Recebido",
  cancelado: "Cancelado",
};

// Pedidos (tabela solicitacao). Transferências: tipo transferencia (e os antigos, legado); Solicitações: os três do agendamento.
export const TIPOS_PEDIDO: Record<string, string> = {
  transferencia: "Pedido de transferência",
  enviar_cliente: "Enviar ao cliente",
  enviar_dedicado: "Enviar dedicado",
  retirar_dedicado: "Retirar dedicado",
  legado: "Pedido antigo",
};
// solicitacao_acoes.situacao (em_transito/recebido seguem a transferência gerada).
export const SITUACOES: Record<string, string> = {
  aberta: "Pendente", em_producao: "Em produção", em_transito: "Em trânsito", recebido: "Recebido", atendida: "Atendida", cancelada: "Cancelada",
};
export type Pedido = {
  id: number; tipo: string; status: string; origem_id: number | null; destino_id: number | null; unidade_id: number | null;
  chamado_url: string | null; observacao: string | null; finalidade?: string | null; prazo_producao: string | null; movimentacao_id: number | null; criado_em: string;
  criador: { nome: string } | null;
  solicitacao_item: { id: number; produto_id: number; quantidade: number; condicao: string | null; reservar_para_unidade_id: number | null; reservado_unidade_id: number | null; produto: { nome: string; usa_chip: boolean } | null }[];
  solicitacao_dedicado: { unidade_id: number }[];
};
export type AcoesPedido = { id: number; situacao: string; pode_aceitar: boolean; pode_atender: boolean; pode_cancelar: boolean };
// Colunas do select de pedidos (o criador é solicitacao.tecnico_id, nome antigo da coluna).
export const SELECT_PEDIDO = "id,tipo,status,origem_id,destino_id,unidade_id,chamado_url,observacao,finalidade,prazo_producao,movimentacao_id,criado_em, criador:usuario(nome), solicitacao_item(id,produto_id,quantidade,condicao,reservar_para_unidade_id,reservado_unidade_id, produto(nome,usa_chip)), solicitacao_dedicado(unidade_id)";

export const PERFIS: Record<Perfil, string> = {
  admin: "Administrador",
  operador: "Operador de estoque",
  tecnico: "Técnico",
  consulta: "Consulta",
  agendamento: "Agendamento (consulta e pede transferência)",
};

export const VINCULOS: Record<Vinculo, string> = { pj: "PJ", clt: "CLT" };

export const MODOS: Record<string, string> = {
  tecnico: "Técnico",
  correios: "Correios", // Sedex virou Correios (o banco migrou os registros antigos)
  retirada: "Retirada",
  transportadora: "Transportadora",
};
// Modos de envio que têm código de rastreio.
export const MODOS_COM_RASTREIO = ["correios", "transportadora"];
// Nome do meio de envio para leitura (registro antigo "sedex" aparece como Correios).
export const nomeModo = (m: string) => MODOS[m === "sedex" ? "correios" : m] ?? m;
// Hoje (AAAA-MM-DD) no fuso de São Paulo: valor padrão e limite (max) dos campos de data, que não aceitam data futura.
export const hojeSP = () => new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());

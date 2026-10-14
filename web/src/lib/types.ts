export type Perfil = "admin" | "operador" | "tecnico" | "consulta";

export type Usuario = { id: string; nome: string; email: string; perfil: Perfil; ativo: boolean };
export type Local = { id: number; nome: string; tipo: "estoque" | "tecnico"; tecnico_id: string | null; base_id: number | null };
export type Produto = { id: number; nome: string; categoria_id: number | null; fabricante: string | null; estoque_minimo: number; categoria?: { nome: string } | null };
export type Unidade = { id: number; nome: string; cliente_id: number; cliente?: { nome: string } | null };
export const nomeUnidade = (u: Unidade) => `${u.cliente?.nome ?? ""} - ${u.nome}`;
export type Associado = { produto_id: number; associado_id: number; quantidade: number };

export type ItemForm = {
  produto_id: number | "";
  condicao: "novo" | "usado";
  quantidade: number;
  reservado_unidade_id?: number | "";
  reservar_para_unidade_id?: number | "";
};

export const TIPOS: Record<string, string> = {
  ENTRADA_COMPRA: "Entrada por compra",
  DEVOLUCAO_CLIENTE: "Devolução de cliente",
  SAIDA_CLIENTE: "Saída para cliente",
  CONSUMO_INTERNO: "Consumo interno / teste",
  DESCARTE: "Descarte",
  AJUSTE: "Ajuste de inventário",
  TRANSFERENCIA: "Transferência",
};

export const STATUS: Record<string, string> = {
  registrado: "Registrado",
  em_transito: "Em trânsito",
  recebido: "Recebido",
  cancelado: "Cancelado",
};

export const PERFIS: Record<Perfil, string> = {
  admin: "Administrador",
  operador: "Operador de estoque",
  tecnico: "Técnico",
  consulta: "Consulta",
};

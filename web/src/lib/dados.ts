import { supabaseServer } from "@/lib/supabase/server";
import type { Associado, Local, Produto, Tecnico, Unidade, Usuario, Visao } from "@/lib/types";
export { nomeUnidade } from "@/lib/types";

export async function getUsuario(): Promise<Usuario | null> {
  const sb = supabaseServer();
  const { data: auth } = await sb.auth.getUser();
  if (!auth.user) return null;
  const [{ data }, { data: visao }] = await Promise.all([
    sb.from("usuario").select("*").eq("id", auth.user.id).maybeSingle(),
    sb.from("minha_visualizacao").select("*").maybeSingle(),
  ]);
  if (!data) return null;
  const usuario = data as Usuario;
  // O banco (fn_perfil, RLS, RPCs) já segue o perfil efetivo; a tela usa o mesmo, vindo de minha_visualizacao.
  const v = (visao as Visao | null) ?? null;
  return { ...usuario, perfil: v?.perfil ?? usuario.perfil, visao: v };
}

// Locais que o usuário pode movimentar (espelha fn_pode_operar_local do banco).
export async function getLocais(usuario: Usuario) {
  const sb = supabaseServer();
  const { data } = await sb.from("local").select("*, tecnico(nome, vinculo, usuario_id)").eq("ativo", true).order("nome");
  const todos = (data ?? []) as unknown as Local[];
  let operaveis: Local[] = [];
  // Com a view minha_visualizacao, os estoques operáveis vêm do banco (valem também no "Ver como").
  if (usuario.visao?.locais_operaveis) { const ids = new Set(usuario.visao.locais_operaveis); operaveis = todos.filter((l) => ids.has(l.id)); }
  else if (usuario.perfil === "admin") operaveis = todos;
  else if (usuario.perfil === "tecnico") operaveis = todos.filter((l) => l.tecnico?.usuario_id === usuario.id);
  else if (usuario.perfil === "operador") {
    const { data: ul } = await sb.from("usuario_local").select("local_id").eq("usuario_id", usuario.id);
    const ids = new Set((ul ?? []).map((x: { local_id: number }) => x.local_id));
    operaveis = todos.filter((l) => ids.has(l.id));
  }
  return { todos, operaveis };
}

export async function getCatalogo() {
  const sb = supabaseServer();
  const [p, u, a] = await Promise.all([
    sb.from("produto").select("*, categoria(nome)").eq("ativo", true).order("nome"),
    sb.from("unidade_cliente").select("*, cliente(nome, ativo)").order("nome"),
    sb.from("item_associado").select("*"),
  ]);
  const ativos = new Set(((p.data ?? []) as { id: number }[]).map((x) => x.id));
  return {
    produtos: (p.data ?? []) as unknown as Produto[],
    // Telas de escolha: só unidade ativa de cliente ativo. Nomes do histórico: todasUnidades.
    unidades: ((u.data ?? []) as unknown as Unidade[]).filter((x) => x.ativo !== false && x.cliente?.ativo !== false),
    todasUnidades: (u.data ?? []) as unknown as Unidade[],
    // Só associados entre itens ativos (as cases e suportes antigos podem ficar inativos).
    associados: ((a.data ?? []) as Associado[]).filter((x) => ativos.has(x.produto_id) && ativos.has(x.associado_id)),
  };
}


export async function getTecnicos() {
  const { data } = await supabaseServer().from("tecnico").select("*").order("nome");
  return (data ?? []) as Tecnico[];
}

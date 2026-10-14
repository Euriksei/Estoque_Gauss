import { supabaseServer } from "@/lib/supabase/server";
import type { Associado, Local, Produto, Tecnico, Unidade, Usuario } from "@/lib/types";
export { nomeUnidade } from "@/lib/types";

export async function getUsuario(): Promise<Usuario | null> {
  const sb = supabaseServer();
  const { data: auth } = await sb.auth.getUser();
  if (!auth.user) return null;
  const { data } = await sb.from("usuario").select("*").eq("id", auth.user.id).maybeSingle();
  return (data as Usuario) ?? null;
}

// Locais que o usuário pode movimentar (espelha fn_pode_operar_local do banco).
export async function getLocais(usuario: Usuario) {
  const sb = supabaseServer();
  const { data } = await sb.from("local").select("*, tecnico(nome, vinculo, usuario_id)").eq("ativo", true).order("nome");
  const todos = (data ?? []) as unknown as Local[];
  let operaveis: Local[] = [];
  if (usuario.perfil === "admin") operaveis = todos;
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
    sb.from("unidade_cliente").select("*, cliente(nome)").order("nome"),
    sb.from("item_associado").select("*"),
  ]);
  return {
    produtos: (p.data ?? []) as unknown as Produto[],
    unidades: (u.data ?? []) as unknown as Unidade[],
    associados: (a.data ?? []) as Associado[],
  };
}


export async function getTecnicos() {
  const { data } = await supabaseServer().from("tecnico").select("*").order("nome");
  return (data ?? []) as Tecnico[];
}

import { supabaseServer } from "@/lib/supabase/server";
import { getLocais, getUsuario } from "@/lib/dados";
import { UsuarioLinha } from "@/components/UsuarioLinha";
import type { Usuario } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function Usuarios() {
  const usuario = (await getUsuario())!;
  if (usuario.perfil !== "admin") return <p className="text-sm">Somente administradores.</p>;
  const sb = supabaseServer();
  const [{ todos }, us, ul] = await Promise.all([
    getLocais(usuario),
    sb.from("usuario").select("*").order("ativo").order("nome"),
    sb.from("usuario_local").select("usuario_id, local_id"),
  ]);
  const usuarios = (us.data ?? []) as Usuario[];
  const vinculos = (ul.data ?? []) as { usuario_id: string; local_id: number }[];
  return (
    <div className="space-y-3">
      <h1 className="text-lg font-semibold">Usuários</h1>
      <p className="text-sm text-slate-600">Quem se cadastra fica inativo até você liberar. Operadores enxergam e movimentam só os estoques marcados; técnicos, só o estoque ligado ao cadastro deles (veja Cadastros, Técnicos).</p>
      <div className="card overflow-x-auto p-0">
        <table className="w-full">
          <thead className="border-b border-slate-200"><tr><th className="th">Usuário</th><th className="th">Perfil</th><th className="th">Acesso</th><th className="th">Estoques</th></tr></thead>
          <tbody className="divide-y divide-slate-100">
            {usuarios.map((u) => (
              <UsuarioLinha key={u.id} u={u} locais={todos}
                meusLocais={vinculos.filter((v) => v.usuario_id === u.id).map((v) => v.local_id)} />
            ))}
          </tbody>
        </table>
      </div>
    </div>
  );
}

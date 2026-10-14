import Link from "next/link";
import { redirect } from "next/navigation";
import { getUsuario } from "@/lib/dados";
import { supabaseServer } from "@/lib/supabase/server";
import { PERFIS, type Perfil } from "@/lib/types";
import { SairBotao } from "@/components/SairBotao";

const MENU: { href: string; nome: string; perfis: Perfil[] }[] = [
  { href: "/", nome: "Estoque", perfis: ["admin", "operador", "tecnico", "consulta"] },
  { href: "/movimentar", nome: "Registrar", perfis: ["admin", "operador", "tecnico"] },
  { href: "/transferencias", nome: "Transferências", perfis: ["admin", "operador", "tecnico", "consulta"] },
  { href: "/solicitacoes", nome: "Solicitações", perfis: ["admin", "operador", "tecnico", "consulta"] },
  { href: "/dedicados", nome: "Dedicados", perfis: ["admin", "operador", "tecnico", "consulta"] },
  { href: "/historico", nome: "Histórico", perfis: ["admin", "operador", "tecnico", "consulta"] },
  { href: "/cadastros", nome: "Cadastros", perfis: ["admin"] },
  { href: "/usuarios", nome: "Usuários", perfis: ["admin"] },
];

export default async function AppLayout({ children }: { children: React.ReactNode }) {
  const { data: auth } = await supabaseServer().auth.getUser();
  if (!auth.user) redirect("/login");
  const usuario = await getUsuario();
  if (!usuario) {
    // Logado, mas sem registro na tabela de usuários: avisa em vez de voltar para o login sem explicar.
    return (
      <main className="mx-auto mt-24 max-w-md px-4 text-center">
        <h1 className="mb-2 text-lg font-semibold">Conta sem cadastro de usuário</h1>
        <p className="mb-4 text-sm text-slate-600">
          Você entrou como {auth.user.email}, mas essa conta não tem registro na tabela de usuários.
          Peça a um administrador para criá-lo, ou rode o comando de liberação no banco.
        </p>
        <SairBotao />
      </main>
    );
  }
  if (!usuario.ativo) {
    return (
      <main className="mx-auto mt-24 max-w-md px-4 text-center">
        <h1 className="mb-2 text-lg font-semibold">Aguardando liberação</h1>
        <p className="mb-4 text-sm text-slate-600">
          Seu cadastro foi criado, mas um administrador ainda precisa liberar o seu acesso.
        </p>
        <SairBotao />
      </main>
    );
  }
  return (
    <div>
      <header className="border-b border-slate-200 bg-white">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-4 gap-y-1 px-4 py-2">
          <span className="font-semibold">Estoque Gauss</span>
          <nav className="flex flex-wrap gap-3 text-sm">
            {MENU.filter((m) => m.perfis.includes(usuario.perfil)).map((m) => (
              <Link key={m.href} href={m.href} className="text-slate-600 hover:text-slate-900">{m.nome}</Link>
            ))}
          </nav>
          <span className="ml-auto text-xs text-slate-500">{usuario.nome} · {PERFIS[usuario.perfil]}</span>
          <SairBotao />
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-4 py-5">{children}</main>
    </div>
  );
}

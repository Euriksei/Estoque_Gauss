import Link from "next/link";
import { redirect } from "next/navigation";
import { getUsuario } from "@/lib/dados";
import { supabaseServer } from "@/lib/supabase/server";
import { PERFIS, type Perfil } from "@/lib/types";
import { SairBotao } from "@/components/SairBotao";
import { Menu } from "@/components/Menu";

const MENU: { href: string; nome: string; perfis: Perfil[] }[] = [
  { href: "/", nome: "Estoque", perfis: ["admin", "operador", "tecnico", "consulta", "agendamento"] },
  { href: "/movimentar", nome: "Registrar", perfis: ["admin", "operador", "tecnico"] },
  { href: "/transferencias", nome: "Transferências", perfis: ["admin", "operador", "tecnico", "consulta", "agendamento"] },
  { href: "/solicitacoes", nome: "Solicitações", perfis: ["admin", "operador", "tecnico", "consulta", "agendamento"] },
  { href: "/dedicados", nome: "Dedicados", perfis: ["admin", "operador", "tecnico", "consulta", "agendamento"] },
  { href: "/historico", nome: "Histórico", perfis: ["admin", "operador", "tecnico", "consulta", "agendamento"] },
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
      <header className="bg-gradient-to-r from-marinho-950 via-marinho-900 to-marinho-700 shadow-md">
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-5 gap-y-2 px-4 py-3">
          <Link href="/" className="flex items-center gap-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo.png" alt="Gauss Fleet" className="h-9 w-9 rounded-lg" />
            <span className="leading-tight text-white">
              <span className="block text-sm font-bold tracking-wide">Estoque Gauss</span>
              <span className="block text-[10px] uppercase tracking-[0.2em] text-slate-400">Gauss Fleet</span>
            </span>
          </Link>
          <Menu itens={MENU.filter((m) => m.perfis.includes(usuario.perfil)).map(({ href, nome }) => ({ href, nome }))} />
          <span className="ml-auto text-xs text-slate-300">{usuario.nome} · {PERFIS[usuario.perfil]}</span>
          <SairBotao />
        </div>
        <div className="h-0.5 bg-gradient-to-r from-marca-600 via-marca-500 to-transparent" />
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}

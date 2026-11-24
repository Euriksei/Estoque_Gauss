import Link from "next/link";
import { redirect } from "next/navigation";
import { getUsuario } from "@/lib/dados";
import { supabaseServer } from "@/lib/supabase/server";
import { PERFIS, type Perfil } from "@/lib/types";
import { SairBotao } from "@/components/SairBotao";
import { Menu } from "@/components/Menu";
import { ConfigMenu } from "@/components/ConfigMenu";
import { FaixaVerComo } from "@/components/VerComo";

const MENU: { href: string; nome: string; perfis: Perfil[] }[] = [
  { href: "/", nome: "Estoque", perfis: ["admin", "operador", "consulta", "agendamento"] },
  { href: "/movimentar", nome: "Registrar", perfis: ["admin", "operador"] },
  { href: "/transferencias", nome: "Transferências", perfis: ["admin", "operador", "tecnico", "consulta", "agendamento"] },
  { href: "/solicitacoes", nome: "Solicitações", perfis: ["admin", "operador", "consulta", "agendamento"] }, // o técnico só usa Transferências
  { href: "/dedicados", nome: "Dedicados", perfis: ["admin", "operador", "consulta", "agendamento"] },
  { href: "/historico", nome: "Histórico", perfis: ["admin", "operador", "consulta", "agendamento"] },
  { href: "/chips", nome: "Chips", perfis: ["admin", "operador"] },
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
  // "Ver como": o menu e as telas seguem o perfil efetivo; a faixa mostra que é simulação e permite voltar.
  const visao = usuario.visao;
  const adminReal = (visao?.perfil_real ?? usuario.perfil) === "admin";
  const faixa = visao?.simulando
    ? `Vendo como ${PERFIS[usuario.perfil]}${visao.tecnico_nome ? ` - ${visao.tecnico_nome}` : visao.local_nome ? ` - ${visao.local_nome}` : ""}`
    : null;
  const quem = `${usuario.nome} · ${PERFIS[usuario.perfil]}`;
  return (
    <div>
      {faixa && <FaixaVerComo texto={faixa} />}
      <header className="bg-gradient-to-r from-marinho-950 via-marinho-900 to-marinho-700 shadow-md">
        {/* Uma linha só: logo | menu | nome | engrenagem. No celular o menu vai para a linha de baixo. */}
        <div className="mx-auto flex max-w-6xl flex-wrap items-center gap-x-5 gap-y-2 px-4 py-3 md:flex-nowrap">
          <Link href="/" className="flex shrink-0 items-center gap-2.5">
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src="/logo.png" alt="Gauss Fleet" className="h-9 w-9 rounded-lg" />
            <span className="leading-tight text-white">
              <span className="block text-sm font-bold tracking-wide">Estoque Gauss</span>
              <span className="block text-[10px] uppercase tracking-[0.2em] text-slate-400">Gauss Fleet</span>
            </span>
          </Link>
          {/* O menu nunca quebra linha; se faltar espaço, rola na horizontal dentro dele (sem barra). */}
          <div className="order-last w-full min-w-0 overflow-x-auto [scrollbar-width:none] md:order-none md:w-auto xl:shrink-0 [&::-webkit-scrollbar]:hidden">
            <Menu itens={MENU.filter((m) => m.perfis.includes(usuario.perfil)).map(({ href, nome }) => ({ href, nome }))} />
          </div>
          {/* O nome cede espaço primeiro (trunca com reticências); o texto completo fica no title e no menu da engrenagem. */}
          <span className="ml-auto min-w-12 shrink-[100] grow basis-0 truncate text-right text-xs text-slate-300 md:grow-0 md:basis-auto" title={quem}>{quem}</span>
          <div className="shrink-0"><ConfigMenu verComo={adminReal} quem={quem} /></div>
        </div>
        <div className="h-0.5 bg-gradient-to-r from-marca-600 via-marca-500 to-transparent" />
      </header>
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}

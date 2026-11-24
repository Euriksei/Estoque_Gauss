"use client";
import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { CampoSenha } from "@/components/CampoSenha";

type Modo = "entrar" | "cadastro" | "esqueci";

export default function Login() {
  const router = useRouter();
  const [modo, setModo] = useState<Modo>("entrar");
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [nome, setNome] = useState("");
  const [msg, setMsg] = useState("");
  const [carregando, setCarregando] = useState(false);

  // Volta do link do e-mail com problema (vencido, já usado ou incompleto).
  useEffect(() => {
    if (new URLSearchParams(window.location.search).get("erro") === "link")
      setMsg("Link inválido ou expirado. Peça um novo em \"Esqueci minha senha\".");
  }, []);

  function trocarModo(m: Modo) {
    setModo(m);
    setMsg("");
  }

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setCarregando(true);
    setMsg("");
    const sb = supabaseBrowser();
    if (modo === "cadastro") {
      const { error } = await sb.auth.signUp({ email, password: senha, options: { data: { nome } } });
      setMsg(error ? error.message : "Cadastro feito. Um administrador precisa liberar o seu acesso.");
    } else if (modo === "esqueci") {
      const { error } = await sb.auth.resetPasswordForEmail(email, {
        redirectTo: `${window.location.origin}/auth/confirm?next=/redefinir-senha`,
      });
      // Mesma resposta exista ou não o e-mail, para não revelar quem tem cadastro.
      setMsg(
        error?.status === 429
          ? "Muitos pedidos seguidos. Aguarde alguns minutos e tente de novo."
          : "Se o e-mail estiver cadastrado, enviamos um link para criar uma nova senha. Confira também o spam.",
      );
    } else {
      const { error } = await sb.auth.signInWithPassword({ email, password: senha });
      if (error) setMsg("E-mail ou senha incorretos.");
      else {
        router.push("/");
        router.refresh();
      }
    }
    setCarregando(false);
  }

  const botao = { entrar: "Entrar", cadastro: "Criar conta", esqueci: "Enviar link" }[modo];

  return (
    <main className="flex min-h-screen border-t-4 border-marca-600 items-center justify-center bg-gradient-to-b from-marinho-900 to-marinho-950 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex flex-col items-center text-white">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Gauss Fleet" className="mb-3 h-20 w-20 rounded-2xl ring-2 ring-white shadow-lg" />
          <h1 className="text-2xl font-bold tracking-wide">Estoque Gauss</h1>
          <p className="text-xs uppercase tracking-[0.25em] text-slate-300">Gauss Fleet</p>
        </div>
        <form onSubmit={enviar} className="card space-y-3 !p-6 shadow-xl">
          {modo === "esqueci" && (
            <p className="text-sm text-slate-600">Informe o seu e-mail. Vamos enviar um link para você criar uma nova senha.</p>
          )}
          {modo === "cadastro" && (
            <label className="block text-sm font-medium">Nome
              <input className="campo mt-1 font-normal" value={nome} onChange={(e) => setNome(e.target.value)} required />
            </label>
          )}
          <label className="block text-sm font-medium">E-mail
            <input type="email" className="campo mt-1 font-normal" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </label>
          {modo !== "esqueci" && (
            <label className="block text-sm font-medium">Senha
              <CampoSenha value={senha} onChange={setSenha} autoComplete={modo === "cadastro" ? "new-password" : "current-password"} />
            </label>
          )}
          {modo === "entrar" && (
            <button type="button" className="-mt-1 block text-xs text-slate-500 underline hover:text-marca-600" onClick={() => trocarModo("esqueci")}>
              Esqueci minha senha
            </button>
          )}
          {msg && <p className="text-sm text-slate-600">{msg}</p>}
          <button className="btn w-full" disabled={carregando}>{botao}</button>
          <button type="button" className="w-full text-sm text-slate-500 underline hover:text-marca-600"
            onClick={() => trocarModo(modo === "entrar" ? "cadastro" : "entrar")}>
            {modo === "entrar" ? "Primeiro acesso" : modo === "cadastro" ? "Já tenho conta" : "Voltar para o login"}
          </button>
        </form>
      </div>
    </main>
  );
}

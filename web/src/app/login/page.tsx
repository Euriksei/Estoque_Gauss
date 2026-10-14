"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export default function Login() {
  const router = useRouter();
  const [email, setEmail] = useState("");
  const [senha, setSenha] = useState("");
  const [nome, setNome] = useState("");
  const [cadastro, setCadastro] = useState(false);
  const [msg, setMsg] = useState("");
  const [carregando, setCarregando] = useState(false);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setCarregando(true);
    setMsg("");
    const sb = supabaseBrowser();
    if (cadastro) {
      const { error } = await sb.auth.signUp({ email, password: senha, options: { data: { nome } } });
      setMsg(error ? error.message : "Cadastro feito. Um administrador precisa liberar o seu acesso.");
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
          {cadastro && (
            <label className="block text-sm font-medium">Nome
              <input className="campo mt-1 font-normal" value={nome} onChange={(e) => setNome(e.target.value)} required />
            </label>
          )}
          <label className="block text-sm font-medium">E-mail
            <input type="email" className="campo mt-1 font-normal" value={email} onChange={(e) => setEmail(e.target.value)} required />
          </label>
          <label className="block text-sm font-medium">Senha
            <input type="password" className="campo mt-1 font-normal" value={senha} onChange={(e) => setSenha(e.target.value)} required minLength={6} />
          </label>
          {msg && <p className="text-sm text-slate-600">{msg}</p>}
          <button className="btn w-full" disabled={carregando}>{cadastro ? "Criar conta" : "Entrar"}</button>
          <button type="button" className="w-full text-sm text-slate-500 underline hover:text-marca-600" onClick={() => setCadastro(!cadastro)}>
            {cadastro ? "Já tenho conta" : "Primeiro acesso"}
          </button>
        </form>
      </div>
    </main>
  );
}

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
    <main className="mx-auto mt-24 max-w-sm px-4">
      <h1 className="mb-4 text-xl font-semibold">Estoque Gauss</h1>
      <form onSubmit={enviar} className="card space-y-3">
        {cadastro && (
          <label className="block text-sm">Nome
            <input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required />
          </label>
        )}
        <label className="block text-sm">E-mail
          <input type="email" className="campo mt-1" value={email} onChange={(e) => setEmail(e.target.value)} required />
        </label>
        <label className="block text-sm">Senha
          <input type="password" className="campo mt-1" value={senha} onChange={(e) => setSenha(e.target.value)} required minLength={6} />
        </label>
        {msg && <p className="text-sm text-slate-600">{msg}</p>}
        <button className="btn w-full" disabled={carregando}>{cadastro ? "Criar conta" : "Entrar"}</button>
        <button type="button" className="w-full text-sm text-slate-500 underline" onClick={() => setCadastro(!cadastro)}>
          {cadastro ? "Já tenho conta" : "Primeiro acesso"}
        </button>
      </form>
    </main>
  );
}

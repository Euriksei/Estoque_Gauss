"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { CampoSenha } from "@/components/CampoSenha";

// Formulário de nova senha, usado na redefinição (link do e-mail) e na troca de senha de quem está logado.
export function NovaSenhaForm({ depois }: { depois: string }) {
  const router = useRouter();
  const [senha, setSenha] = useState("");
  const [confirma, setConfirma] = useState("");
  const [msg, setMsg] = useState("");
  const [ok, setOk] = useState(false);
  const [carregando, setCarregando] = useState(false);

  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    setMsg("");
    if (senha !== confirma) {
      setMsg("As senhas não são iguais.");
      return;
    }
    setCarregando(true);
    const { error } = await supabaseBrowser().auth.updateUser({ password: senha });
    setCarregando(false);
    if (error) {
      setMsg(
        error.code === "same_password"
          ? "A nova senha precisa ser diferente da atual."
          : error.code === "weak_password"
            ? "Senha fraca. Use uma senha mais longa."
            : "Não foi possível trocar a senha. Tente de novo ou peça um novo link.",
      );
      return;
    }
    setOk(true);
    setSenha("");
    setConfirma("");
    router.push(depois);
    router.refresh();
  }

  return (
    <form onSubmit={salvar} className="space-y-3">
      <label className="block text-sm font-medium">Nova senha
        <CampoSenha value={senha} onChange={setSenha} autoComplete="new-password" />
      </label>
      <label className="block text-sm font-medium">Repita a nova senha
        <CampoSenha value={confirma} onChange={setConfirma} autoComplete="new-password" />
      </label>
      {msg && <p className="text-sm text-red-600">{msg}</p>}
      {ok && <p className="text-sm text-green-700">Senha alterada.</p>}
      <button className="btn w-full" disabled={carregando}>{carregando ? "Salvando..." : "Salvar nova senha"}</button>
    </form>
  );
}

import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { NovaSenhaForm } from "@/components/NovaSenhaForm";

// Destino do link de "Esqueci minha senha". Fica fora do layout do app para funcionar
// também para quem ainda está aguardando liberação.
export default async function RedefinirSenha() {
  const { data } = await supabaseServer().auth.getUser();
  if (!data.user) redirect("/login?erro=link");

  return (
    <main className="flex min-h-screen border-t-4 border-marca-600 items-center justify-center bg-gradient-to-b from-marinho-900 to-marinho-950 px-4">
      <div className="w-full max-w-sm">
        <div className="mb-6 flex flex-col items-center text-white">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/logo.png" alt="Gauss Fleet" className="mb-3 h-20 w-20 rounded-2xl ring-2 ring-white shadow-lg" />
          <h1 className="text-2xl font-bold tracking-wide">Nova senha</h1>
          <p className="text-xs text-slate-300">{data.user.email}</p>
        </div>
        <div className="card !p-6 shadow-xl">
          <NovaSenhaForm depois="/" />
        </div>
      </div>
    </main>
  );
}

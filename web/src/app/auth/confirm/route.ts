import { NextResponse, type NextRequest } from "next/server";
import type { EmailOtpType } from "@supabase/supabase-js";
import { supabaseServer } from "@/lib/supabase/server";

// Link do e-mail de redefinição de senha: valida o token, abre a sessão e segue para a página indicada.
// Com token_hash funciona em qualquer aparelho; com code, só no navegador que pediu o link.
export async function GET(req: NextRequest) {
  const { searchParams, origin } = req.nextUrl;
  const token_hash = searchParams.get("token_hash");
  const type = searchParams.get("type") as EmailOtpType | null;
  const next = searchParams.get("next") ?? "/";
  // Só aceita caminho interno, para o link não poder mandar a pessoa para outro site.
  const destino = next.startsWith("/") && !next.startsWith("//") ? next : "/";

  const code = searchParams.get("code");
  const sb = supabaseServer();

  if (token_hash && type) {
    // Modelo de e-mail personalizado (README): o token vem direto para cá.
    const { error } = await sb.auth.verifyOtp({ type, token_hash });
    if (!error) return NextResponse.redirect(`${origin}${destino}`);
  } else if (code) {
    // Modelo de e-mail padrão do Supabase: ele valida o link e devolve um código,
    // trocado aqui pela sessão (só no mesmo navegador que pediu o link).
    const { error } = await sb.auth.exchangeCodeForSession(code);
    if (!error) return NextResponse.redirect(`${origin}${destino}`);
  }
  return NextResponse.redirect(`${origin}/login?erro=link`);
}

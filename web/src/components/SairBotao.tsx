"use client";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

export function SairBotao() {
  const router = useRouter();
  return (
    <button
      className="rounded-lg border border-white/25 px-3 py-1.5 text-sm font-medium text-white transition hover:bg-white/10"
      onClick={async () => {
        await supabaseBrowser().auth.signOut();
        router.push("/login");
        router.refresh();
      }}
    >
      Sair
    </button>
  );
}

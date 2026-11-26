import { redirect } from "next/navigation";
import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getTecnicos, getUsuario } from "@/lib/dados";
import { MovimentarForm, type Saldo } from "@/components/MovimentarForm";

export const dynamic = "force-dynamic";

export default async function Movimentar() {
  const usuario = (await getUsuario())!;
  // O técnico só usa Transferências e Solicitações.
  if ((usuario.perfil as string) === "tecnico") redirect("/transferencias");
  if (usuario.perfil === "consulta" || usuario.perfil === "agendamento") return <p className="text-sm">Seu perfil não registra movimentações.</p>;
  const sb = supabaseServer();
  const [{ operaveis }, cat, tecnicos, { data: saldoBruto }] = await Promise.all([getLocais(usuario), getCatalogo(), getTecnicos(), sb.from("saldo").select("*")]);
  // Saldo dos locais que o usuário movimenta: a tela mostra o disponível nas saídas (o banco continua barrando o que faltar).
  const ids = new Set(operaveis.map((l) => l.id));
  const saldo = ((saldoBruto ?? []) as Saldo[]).filter((s) => ids.has(s.local_id) && s.quantidade !== 0);
  // O técnico só dá baixa de saída para cliente, no próprio estoque/carro.
  const tipos = usuario.perfil === "tecnico"
    ? ["SAIDA_CLIENTE"]
    : ["SAIDA_CLIENTE", "ENVIO_TECNICO", "ENTRADA_COMPRA", "DEVOLUCAO_CLIENTE", "CONSUMO_INTERNO", "DESCARTE", "AJUSTE"];
  return (
    <div className="space-y-3">
      <h1 className="text-xl font-bold text-marinho-900">{usuario.perfil === "tecnico" ? "Dar baixa no cliente" : "Registrar entrada ou saída"}</h1>
      {operaveis.length === 0
        ? <p className="text-sm">Você ainda não tem um estoque liberado. Fale com um administrador.</p>
        : <MovimentarForm tipos={tipos} locais={operaveis} produtos={cat.produtos} unidades={cat.unidades} associados={cat.associados} saldo={saldo}
            tecnicos={tecnicos.filter((t) => t.ativo)} ehTecnico={usuario.perfil === "tecnico"} />}
    </div>
  );
}

import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getTecnicos, getUsuario } from "@/lib/dados";
import { MovimentarForm } from "@/components/MovimentarForm";

export const dynamic = "force-dynamic";

export default async function Movimentar() {
  const usuario = (await getUsuario())!;
  if (usuario.perfil === "consulta") return <p className="text-sm">Seu perfil não registra movimentações.</p>;
  const sb = supabaseServer();
  const [{ operaveis, todos }, cat, { data: forn }, tecnicos] = await Promise.all([getLocais(usuario), getCatalogo(), sb.from("fornecedor").select("id, nome").order("nome"), getTecnicos()]);
  // O técnico só dá baixa de saída para cliente, no próprio estoque/carro.
  const tipos = usuario.perfil === "tecnico"
    ? ["SAIDA_CLIENTE"]
    : ["SAIDA_CLIENTE", "SAIDA_TECNICO", "ENTRADA_COMPRA", "DEVOLUCAO_CLIENTE", "CONSUMO_INTERNO", "DESCARTE", "AJUSTE"];
  return (
    <div className="space-y-3">
      <h1 className="text-lg font-semibold">{usuario.perfil === "tecnico" ? "Dar baixa no cliente" : "Registrar entrada ou saída"}</h1>
      {operaveis.length === 0
        ? <p className="text-sm">Você ainda não tem um estoque liberado. Fale com um administrador.</p>
        : <MovimentarForm tipos={tipos} locais={operaveis} produtos={cat.produtos} unidades={cat.unidades} associados={cat.associados} fornecedores={forn ?? []}
            tecnicos={tecnicos.filter((t) => t.ativo)} ehTecnico={usuario.perfil === "tecnico"}
            estoquesTecnico={todos.filter((l) => l.tipo === "tecnico" && l.tecnico_id).flatMap((l) => {
              const t = tecnicos.find((x) => x.id === l.tecnico_id && x.ativo);
              return t ? [{ local_id: l.id, tecnico: t }] : [];
            })} />}
    </div>
  );
}

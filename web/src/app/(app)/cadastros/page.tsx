import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getUsuario } from "@/lib/dados";
import { EstoqueMinimo, NovaUnidade, NovoCliente, NovoProduto } from "@/components/CadastroForms";
import { nomeUnidade } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function Cadastros() {
  const usuario = (await getUsuario())!;
  if (usuario.perfil !== "admin") return <p className="text-sm">Somente administradores.</p>;
  const sb = supabaseServer();
  const [cat, c, f, k] = await Promise.all([
    getCatalogo(),
    sb.from("cliente").select("id, nome").order("nome"),
    sb.from("fornecedor").select("id, nome").order("nome"),
    sb.from("categoria").select("id, nome").order("nome"),
  ]);
  const clientes = c.data ?? [];
  return (
    <div className="space-y-6">
      <h1 className="text-lg font-semibold">Cadastros</h1>
      <section className="card space-y-3">
        <h2 className="font-medium">Clientes e unidades</h2>
        <NovoCliente />
        <NovaUnidade clientes={clientes} />
        <p className="text-sm text-slate-600">{cat.unidades.map(nomeUnidade).join(" · ") || "Nenhuma unidade cadastrada."}</p>
      </section>
      <section className="card space-y-3">
        <h2 className="font-medium">Itens e estoque mínimo</h2>
        <NovoProduto categorias={k.data ?? []} fornecedores={f.data ?? []} />
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead><tr><th className="th">Item</th><th className="th">Categoria</th><th className="th">Fabricante</th><th className="th">Estoque mínimo</th></tr></thead>
            <tbody className="divide-y divide-slate-100">
              {cat.produtos.map((p) => (
                <tr key={p.id}><td className="td">{p.nome}</td><td className="td">{p.categoria?.nome}</td><td className="td">{p.fabricante ?? "-"}</td><td className="td"><EstoqueMinimo id={p.id} valor={p.estoque_minimo} /></td></tr>
              ))}
            </tbody>
          </table>
        </div>
      </section>
    </div>
  );
}

import { supabaseServer } from "@/lib/supabase/server";
import { getCatalogo, getLocais, getTecnicos, getUsuario } from "@/lib/dados";
import { EstoqueMinimo, NovaUnidade, NovoCliente, NovoProduto, NovoTecnico, TecnicoLinha } from "@/components/CadastroForms";
import { nomeUnidade } from "@/lib/types";

export const dynamic = "force-dynamic";

export default async function Cadastros() {
  const usuario = (await getUsuario())!;
  if (usuario.perfil !== "admin") return <p className="text-sm">Somente administradores.</p>;
  const sb = supabaseServer();
  const [cat, c, f, k, tecnicos, { todos }, us] = await Promise.all([
    getCatalogo(),
    sb.from("cliente").select("id, nome").order("nome"),
    sb.from("fornecedor").select("id, nome").order("nome"),
    sb.from("categoria").select("id, nome").order("nome"),
    getTecnicos(),
    getLocais(usuario),
    sb.from("usuario").select("id, nome, email").eq("ativo", true).order("nome"),
  ]);
  const usuarios = (us.data ?? []) as { id: string; nome: string; email: string }[];
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
        <h2 className="font-medium">Técnicos</h2>
        <p className="text-sm text-slate-600">Cada técnico (CLT ou PJ) tem o próprio estoque. Quem leva material ao cliente é escolhido aqui na saída. Se o técnico também usa o sistema, ligue-o ao login dele para ele ver e movimentar o próprio estoque.</p>
        <NovoTecnico usuarios={usuarios} />
        <div className="overflow-x-auto">
          <table className="w-full">
            <thead><tr><th className="th">Técnico</th><th className="th">Vínculo</th><th className="th">Login</th><th className="th">Situação</th><th className="th">Estoque</th></tr></thead>
            <tbody className="divide-y divide-slate-100">
              {tecnicos.map((t) => <TecnicoLinha key={t.id} t={t} usuarios={usuarios} estoque={todos.find((l) => l.tecnico_id === t.id)?.nome ?? null} />)}
              {tecnicos.length === 0 && <tr><td className="td text-slate-500" colSpan={5}>Nenhum técnico cadastrado.</td></tr>}
            </tbody>
          </table>
        </div>
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

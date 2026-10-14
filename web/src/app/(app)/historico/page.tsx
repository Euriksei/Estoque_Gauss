import { supabaseServer } from "@/lib/supabase/server";
import { getLocais, getUsuario } from "@/lib/dados";
import { Acao } from "@/components/Acao";
import { MODOS, STATUS, TIPOS, VINCULOS, nomeUnidade, type Vinculo } from "@/lib/types";

export const dynamic = "force-dynamic";

type Mov = {
  id: number; tipo: string; status: string; data: string; chamado_url: string | null; observacao: string | null; numero_nf: string | null;
  modo_envio: string | null; codigo_rastreio: string | null; tecnico: { nome: string; vinculo: Vinculo } | null;
  local_origem_id: number | null; local_destino_id: number | null;
  unidade: { nome: string; cliente: { nome: string } | null } | null; criador: { nome: string } | null;
  movimentacao_item: { quantidade: number; produto: { nome: string } | null }[];
};

export default async function Historico() {
  const usuario = (await getUsuario())!;
  const sb = supabaseServer();
  const [{ todos }, { data }] = await Promise.all([
    getLocais(usuario),
    sb.from("movimentacao")
      .select("id,tipo,status,data,chamado_url,observacao,numero_nf,modo_envio,codigo_rastreio,tecnico(nome,vinculo),local_origem_id,local_destino_id, unidade:unidade_cliente(nome, cliente(nome)), criador:usuario!movimentacao_criado_por_fkey(nome), movimentacao_item(quantidade, produto(nome))")
      .neq("tipo", "TRANSFERENCIA").order("id", { ascending: false }).limit(150),
  ]);
  const movs = (data ?? []) as unknown as Mov[];
  const nome = new Map(todos.map((l) => [l.id, l.nome]));

  return (
    <div className="space-y-4">
      <h1 className="text-xl font-bold text-marinho-900">Histórico de movimentações</h1>
      <p className="text-sm text-slate-600">As transferências ficam na aba Transferências.</p>
      <div className="card overflow-x-auto p-0">
        <table className="w-full">
          <thead className="border-b border-slate-200"><tr><th className="th">Data</th><th className="th">Tipo</th><th className="th">Local</th><th className="th">Itens</th><th className="th">Detalhes</th><th className="th"></th></tr></thead>
          <tbody className="divide-y divide-slate-100 align-top">
            {movs.map((m) => (
              <tr key={m.id} className={m.status === "cancelado" ? "text-slate-400 line-through" : ""}>
                <td className="td whitespace-nowrap">{m.data}</td>
                <td className="td">{TIPOS[m.tipo]}{m.status === "cancelado" && " (estornada)"}</td>
                <td className="td">{nome.get((m.local_origem_id ?? m.local_destino_id)!) ?? "-"}</td>
                <td className="td">{m.movimentacao_item.map((i, k) => <div key={k}>{i.quantidade}× {i.produto?.nome}</div>)}</td>
                <td className="td text-xs text-slate-600">
                  {m.unidade && <div>{nomeUnidade({ id: 0, cliente_id: 0, nome: m.unidade.nome, cliente: m.unidade.cliente })}</div>}
                  {m.numero_nf && <div>NF {m.numero_nf}</div>}
                  {m.modo_envio && <div>Envio: {MODOS[m.modo_envio]}{m.tecnico && ` · ${m.tecnico.nome} (${VINCULOS[m.tecnico.vinculo]})`}{m.codigo_rastreio && ` · rastreio ${m.codigo_rastreio}`}</div>}
                  {m.chamado_url && <a className="underline" href={m.chamado_url} target="_blank" rel="noreferrer">chamado</a>}
                  {m.observacao && <div>{m.observacao}</div>}
                  <div>por {m.criador?.nome ?? "-"}</div>
                </td>
                <td className="td">{usuario.perfil === "admin" && m.status === "registrado" && <Acao fn="estornar_movimentacao" args={{ p_id: m.id }} texto="Estornar" secundario pedirMotivo confirmar="Estornar esta movimentação?" />}</td>
              </tr>
            ))}
            {movs.length === 0 && <tr><td className="td text-slate-500" colSpan={6}>Nada registrado ainda.</td></tr>}
          </tbody>
        </table>
      </div>
      <p className="text-xs text-slate-500">{STATUS.registrado}: a movimentação já alterou o saldo. Estornadas ficam riscadas e não contam mais no saldo.</p>
    </div>
  );
}

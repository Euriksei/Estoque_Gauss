"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Busca } from "@/components/Busca";
import { REDES, VINCULOS, type Produto, type Tecnico, type Vinculo } from "@/lib/types";

type Opt = { id: number; nome: string };
// Só módulos (Rastreamento e telemetria) e MDVR usam chip; nas outras categorias o item grava sem chip.
const CATEGORIAS_CHIP = ["Rastreamento e telemetria", "MDVR e monitores"];
const catUsaChip = (cats: Opt[], id: number | "") => CATEGORIAS_CHIP.includes(cats.find((c) => c.id === id)?.nome ?? "");

function CamposChip({ usaChip, setUsaChip, rede, setRede }: { usaChip: boolean; setUsaChip: (v: boolean) => void; rede: string; setRede: (v: string) => void }) {
  return (
    <>
      <label className="flex items-center gap-1 pb-2 text-sm"><input type="checkbox" checked={usaChip} onChange={(e) => setUsaChip(e.target.checked)} /> Usa chip</label>
      <label className="text-sm">Tipo de chip
        <select className="campo mt-1" value={rede} onChange={(e) => setRede(e.target.value)}>
          <option value="">-</option>{Object.entries(REDES).map(([v, n]) => <option key={v} value={v}>{n}</option>)}
        </select></label>
    </>
  );
}

function useSalvar() {
  const router = useRouter();
  const [erro, setErro] = useState("");
  return {
    erro,
    async salvar(fn: () => PromiseLike<{ error: { message: string } | null }>) {
      const { error } = await fn();
      setErro(error ? (error as { code?: string }).code === "23505" ? "Já existe um item com esse nome" : error.message : "");
      if (!error) router.refresh();
    },
  };
}

export function NovoCliente() {
  const [nome, setNome] = useState("");
  const { erro, salvar } = useSalvar();
  return (
    <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => { e.preventDefault(); await salvar(() => supabaseBrowser().from("cliente").insert({ nome })); setNome(""); }}>
      <label className="text-sm">Novo cliente<input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required /></label>
      <button className="btn">Adicionar</button>{erro && <span className="text-xs text-marca-700">{erro}</span>}
    </form>
  );
}

export function NovaUnidade({ clientes }: { clientes: Opt[] }) {
  const [clienteId, setClienteId] = useState<number | "">("");
  const [nome, setNome] = useState("");
  const [resp, setResp] = useState("");
  const { erro, salvar } = useSalvar();
  return (
    <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => { e.preventDefault(); await salvar(() => supabaseBrowser().from("unidade_cliente").insert({ cliente_id: clienteId, nome, responsavel: resp || null })); setNome(""); setResp(""); }}>
      <label className="text-sm">Cliente
        <select className="campo mt-1" value={clienteId} onChange={(e) => setClienteId(Number(e.target.value))} required>
          <option value="">Selecione</option>{clientes.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select></label>
      <label className="text-sm">Nova unidade<input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required /></label>
      <label className="text-sm">Responsável<input className="campo mt-1" value={resp} onChange={(e) => setResp(e.target.value)} /></label>
      <button className="btn">Adicionar</button>{erro && <span className="text-xs text-marca-700">{erro}</span>}
    </form>
  );
}

export function NovoProduto({ categorias }: { categorias: Opt[] }) {
  const [nome, setNome] = useState("");
  const [cat, setCat] = useState<number | "">("");
  const [min, setMin] = useState(0);
  const [usaChip, setUsaChip] = useState(false);
  const [rede, setRede] = useState("");
  const comChip = catUsaChip(categorias, cat);
  const { erro, salvar } = useSalvar();
  return (
    <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => { e.preventDefault(); await salvar(() => supabaseBrowser().from("produto").insert({ nome, categoria_id: cat || null, estoque_minimo: min, usa_chip: comChip && usaChip, chip_rede: comChip ? rede || null : null })); setNome(""); }}>
      <label className="text-sm">Novo item<input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required /></label>
      <label className="text-sm">Categoria
        <select className="campo mt-1" value={cat} onChange={(e) => setCat(Number(e.target.value))} required>
          <option value="">Selecione</option>{categorias.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select></label>
      <label className="flex flex-col text-sm">Mínimo<input type="number" min={0} className="campo mt-1 w-24" value={min} onChange={(e) => setMin(Number(e.target.value))} /></label>
      {comChip && <CamposChip usaChip={usaChip} setUsaChip={setUsaChip} rede={rede} setRede={setRede} />}
      <button className="btn">Adicionar</button>{erro && <span className="text-xs text-marca-700">{erro}</span>}
    </form>
  );
}

// Tabela de itens com busca e filtro por categoria. O admin edita, exclui e reativa (inativos com etiqueta).
export function ProdutosTabela({ produtos, categorias: cats }: { produtos: Produto[]; categorias: Opt[] }) {
  const [q, setQ] = useState("");
  const [cat, setCat] = useState<number | "">("");
  const [editando, setEditando] = useState<number | null>(null);
  const [modo, setModo] = useState(false); // lista só leitura até clicar em Editar itens
  const [aviso, setAviso] = useState("");
  const router = useRouter();
  const norm = (t: string) => t.normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase();
  const categorias = [...new Map(produtos.filter((p) => p.categoria_id).map((p) => [p.categoria_id as number, p.categoria?.nome ?? ""])).entries()].sort((a, b) => a[1].localeCompare(b[1], "pt-BR"));
  const lista = produtos.filter((p) => (cat === "" || p.categoria_id === cat) && norm(p.nome).includes(norm(q)));
  async function excluir(p: Produto) {
    if (!confirm(`Excluir "${p.nome}"? Se ele tiver histórico ou fizer parte de um kit, será só desativado.`)) return;
    const { data, error } = await supabaseBrowser().rpc("excluir_item", { p_id: p.id });
    if (error) return setAviso(error.message);
    setAviso(data === "desativado" ? `"${p.nome}": este item tem histórico ou faz parte de um kit: foi desativado, não excluído.` : `"${p.nome}" foi excluído.`);
    router.refresh();
  }
  return (
    <div className="space-y-2">
      <div className="flex flex-wrap gap-2">
        <input className="campo w-60" placeholder="Buscar item" value={q} onChange={(e) => setQ(e.target.value)} />
        <select className="campo w-auto" value={cat} onChange={(e) => setCat(e.target.value ? Number(e.target.value) : "")}>
          <option value="">Todas as categorias</option>
          {categorias.map(([id, nome]) => <option key={id} value={id}>{nome}</option>)}
        </select>
        <span className="self-center text-xs text-slate-500">{lista.length} de {produtos.length} itens</span>
        <button type="button" className={modo ? "btn" : "btn-sec"} onClick={() => { setModo(!modo); setEditando(null); }}>{modo ? "Concluir" : "Editar itens"}</button>
      </div>
      {aviso && <p className="text-sm text-slate-700">{aviso}</p>}
      <div className="overflow-x-auto">
        <table className="w-full">
          <thead><tr><th className="th">Item</th><th className="th">Categoria</th><th className="th">Fabricante</th><th className="th">Estoque mínimo</th>{modo && <th className="th"></th>}</tr></thead>
          <tbody className="divide-y divide-slate-100">
            {lista.map((p) => editando === p.id ? (
              <tr key={p.id}><td className="td" colSpan={5}><EditarItem p={p} categorias={cats} fechar={() => setEditando(null)} /></td></tr>
            ) : (
              <tr key={p.id}>
                <td className="td">{p.nome}{p.ativo === false && <span className="ml-2 rounded bg-slate-200 px-1.5 py-0.5 text-xs">Inativo</span>}</td>
                <td className="td">{p.categoria?.nome}</td><td className="td">{p.fabricante ?? "-"}</td>
                <td className="td">{modo ? <EstoqueMinimo id={p.id} valor={p.estoque_minimo} /> : p.estoque_minimo}</td>
                {modo && <td className="td whitespace-nowrap">
                  <button type="button" className="btn-sec mr-1" onClick={() => setEditando(p.id)}>Editar</button>
                  <button type="button" className="btn-sec" onClick={() => excluir(p)}>Excluir</button>
                </td>}
              </tr>
            ))}
            {lista.length === 0 && <tr><td className="td text-slate-500" colSpan={5}>Nenhum item encontrado.</td></tr>}
          </tbody>
        </table>
      </div>
    </div>
  );
}

function EditarItem({ p, categorias, fechar }: { p: Produto; categorias: Opt[]; fechar: () => void }) {
  const [nome, setNome] = useState(p.nome);
  const [cat, setCat] = useState<number | "">(p.categoria_id ?? "");
  const [fab, setFab] = useState(p.fabricante ?? "");
  const [min, setMin] = useState(p.estoque_minimo);
  const [usaChip, setUsaChip] = useState(!!p.usa_chip);
  const [rede, setRede] = useState(p.chip_rede ?? "");
  const [ativo, setAtivo] = useState(p.ativo !== false);
  const comChip = catUsaChip(categorias, cat);
  const [erro, setErro] = useState("");
  const router = useRouter();
  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    const { error } = await supabaseBrowser().from("produto").update({
      nome: nome.trim(), categoria_id: cat || null, fabricante: fab.trim() || null, estoque_minimo: min, usa_chip: comChip && usaChip, chip_rede: comChip ? rede || null : null, ativo,
    }).eq("id", p.id);
    if (error) return setErro(error.code === "23505" ? "Já existe um item com esse nome" : error.message);
    fechar(); router.refresh();
  }
  return (
    <form onSubmit={salvar} className="flex flex-wrap items-end gap-2 text-sm">
      <label>Nome<input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required /></label>
      <label>Categoria
        <select className="campo mt-1" value={cat} onChange={(e) => setCat(e.target.value ? Number(e.target.value) : "")} required>
          <option value="">Selecione</option>{categorias.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select></label>
      <label>Fabricante<input className="campo mt-1" value={fab} onChange={(e) => setFab(e.target.value)} /></label>
      <label className="flex flex-col">Mínimo<input type="number" min={0} className="campo mt-1 w-20" value={min} onChange={(e) => setMin(Number(e.target.value))} /></label>
      {comChip && <CamposChip usaChip={usaChip} setUsaChip={setUsaChip} rede={rede} setRede={setRede} />}
      <label className="flex items-center gap-1 pb-2"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} /> Ativo</label>
      <button className="btn">Salvar</button>
      <button type="button" className="btn-sec" onClick={fechar}>Cancelar</button>
      {erro && <span className="text-xs text-marca-700">{erro}</span>}
    </form>
  );
}

export function EstoqueMinimo({ id, valor }: { id: number; valor: number }) {
  const [v, setV] = useState(valor);
  const { erro, salvar } = useSalvar();
  return (
    <span className="inline-flex items-center gap-1">
      <input type="number" min={0} className="campo w-20" value={v} onChange={(e) => setV(Number(e.target.value))} />
      {v !== valor && <button className="btn-sec" onClick={() => salvar(() => supabaseBrowser().from("produto").update({ estoque_minimo: v }).eq("id", id))}>Salvar</button>}
      {erro && <span className="text-xs text-marca-700">{erro}</span>}
    </span>
  );
}

export function NovoTecnico({ usuarios, bases }: { usuarios: { id: string; nome: string; email: string }[]; bases: { id: number; nome: string }[] }) {
  const [baseId, setBaseId] = useState<number | "">("");
  const [nome, setNome] = useState("");
  const [vinculo, setVinculo] = useState<Vinculo>("clt");
  const [usuarioId, setUsuarioId] = useState("");
  const { erro, salvar } = useSalvar();
  return (
    <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => {
      e.preventDefault();
      await salvar(async () => {
        const sb = supabaseBrowser();
        const { data, error } = await sb.from("tecnico").insert({ nome, vinculo, usuario_id: usuarioId || null }).select("id").single();
        if (error || !data) return { error: error ?? { message: "Não foi possível cadastrar" } };
        // Cada técnico já nasce com o próprio estoque.
        return sb.from("local").insert({ nome: `Estoque técnico ${VINCULOS[vinculo]} - ${nome}`, tipo: "tecnico", tecnico_id: data.id, base_id: baseId || null });
      });
      setNome(""); setUsuarioId("");
    }}>
      <label className="text-sm">Novo técnico<input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required /></label>
      <label className="text-sm">Vínculo
        <select className="campo mt-1" value={vinculo} onChange={(e) => setVinculo(e.target.value as Vinculo)}>
          <option value="clt">CLT</option><option value="pj">PJ</option>
        </select></label>
      <label className="text-sm">Estoque base
        <select className="campo mt-1" value={baseId} onChange={(e) => setBaseId(Number(e.target.value))} required>
          <option value="">Selecione</option>
          {bases.map((b) => <option key={b.id} value={b.id}>{b.nome}</option>)}
        </select></label>
      <label className="text-sm">Acessa o sistema como (opcional)
        <select className="campo mt-1" value={usuarioId} onChange={(e) => setUsuarioId(e.target.value)}>
          <option value="">Sem login</option>
          {usuarios.map((u) => <option key={u.id} value={u.id}>{u.nome} ({u.email})</option>)}
        </select></label>
      <button className="btn">Cadastrar</button>{erro && <span className="text-xs text-marca-700">{erro}</span>}
    </form>
  );
}

export function TecnicoLinha({ t, usuarios, estoque, localId, baseId, bases }: { t: Tecnico; usuarios: { id: string; nome: string; email: string }[]; estoque: string | null; localId: number | null; baseId: number | null; bases: { id: number; nome: string }[] }) {
  const { erro, salvar } = useSalvar();
  const sb = supabaseBrowser();
  const atualizar = (parte: Partial<Tecnico>) => salvar(() => sb.from("tecnico").update(parte).eq("id", t.id));
  return (
    <tr className="align-top">
      <td className="td font-medium">{t.nome}</td>
      <td className="td">
        <select className="campo w-auto" value={t.vinculo} onChange={(e) => atualizar({ vinculo: e.target.value as Vinculo })}>
          <option value="clt">CLT</option><option value="pj">PJ</option>
        </select>
      </td>
      <td className="td">
        <select className="campo w-auto" value={t.usuario_id ?? ""} onChange={(e) => atualizar({ usuario_id: e.target.value || null })}>
          <option value="">Sem login</option>
          {usuarios.map((u) => <option key={u.id} value={u.id}>{u.nome}</option>)}
        </select>
      </td>
      <td className="td">
        <label className="flex items-center gap-1 text-sm"><input type="checkbox" checked={t.ativo} onChange={(e) => atualizar({ ativo: e.target.checked })} /> Ativo</label>
      </td>
      <td className="td">
        {localId ? (
          <select className="campo w-auto" value={baseId ?? ""} onChange={(e) => salvar(() => sb.from("local").update({ base_id: e.target.value ? Number(e.target.value) : null }).eq("id", localId))}>
            <option value="">Defina o estoque base</option>
            {bases.map((b) => <option key={b.id} value={b.id}>{b.nome}</option>)}
          </select>
        ) : "-"}
      </td>
      <td className="td text-sm">
        {estoque ?? <button className="btn-sec" onClick={() => salvar(() => sb.from("local").insert({ nome: `Estoque técnico ${VINCULOS[t.vinculo]} - ${t.nome}`, tipo: "tecnico", tecnico_id: t.id }))}>Criar estoque</button>}
        {erro && <div className="text-xs text-marca-700">{erro}</div>}
      </td>
    </tr>
  );
}

// Kit de cada item (item_associado): periféricos sugeridos no "Com kit". Só o administrador edita.
// Opcional vem desmarcado; itens com o mesmo grupo viram escolha de um só (ex.: Case).
export function AssociadosEditor({ produtos, associados }: { produtos: { id: number; nome: string }[]; associados: { produto_id: number; associado_id: number; quantidade: number; opcional?: boolean; grupo?: string | null }[] }) {
  const [prod, setProd] = useState<number | "">("");
  const [assoc, setAssoc] = useState<number | "">("");
  const [qtd, setQtd] = useState(1);
  const [opcional, setOpcional] = useState(false);
  const [grupo, setGrupo] = useState("");
  const { erro, salvar } = useSalvar();
  const nome = new Map(produtos.map((p) => [p.id, p.nome]));
  const doItem = associados.filter((k) => k.produto_id === prod);
  return (
    <div className="space-y-2 text-sm">
      <div className="w-72">Item<div className="mt-1"><Busca value={prod} onChange={setProd} placeholder="Digite para buscar" opcoes={produtos.map((p) => ({ value: p.id, label: p.nome }))} /></div></div>
      {prod !== "" && (
        <>
          <ul className="list-disc pl-5">
            {doItem.map((k) => (
              <li key={k.associado_id}>{k.quantidade}× {nome.get(k.associado_id)}{k.opcional && " · opcional"}{k.grupo && ` · grupo ${k.grupo}`}{" "}
                <button type="button" className="text-xs text-marca-700 underline" onClick={() => salvar(() => supabaseBrowser().from("item_associado").delete().eq("produto_id", k.produto_id).eq("associado_id", k.associado_id))}>tirar</button>
              </li>
            ))}
            {doItem.length === 0 && <li className="text-slate-500">Sem kit.</li>}
          </ul>
          <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => { e.preventDefault(); await salvar(() => supabaseBrowser().from("item_associado").upsert({ produto_id: prod, associado_id: assoc, quantidade: qtd, opcional, grupo: grupo.trim() || null })); setAssoc(""); setQtd(1); setOpcional(false); setGrupo(""); }}>
            <div className="w-72">Periférico<div className="mt-1"><Busca required value={assoc} onChange={setAssoc} placeholder="Digite para buscar" opcoes={produtos.filter((p) => p.id !== prod).map((p) => ({ value: p.id, label: p.nome }))} /></div></div>
            <label className="flex flex-col">Qtd.<input type="number" min={1} step={1} className="campo mt-1 w-20" value={qtd || ""} onChange={(e) => { const n = Math.floor(Number(e.target.value)); setQtd(n > 0 ? n : 0); }} required /></label>
            <label className="flex items-center gap-1 pb-2"><input type="checkbox" checked={opcional} onChange={(e) => setOpcional(e.target.checked)} /> Opcional</label>
            <label className="flex flex-col">Grupo (escolha de um só)<input className="campo mt-1 w-32" value={grupo} onChange={(e) => setGrupo(e.target.value)} placeholder="ex.: Case" /></label>
            <button className="btn">Adicionar ao kit</button>
          </form>
          <p className="text-xs text-slate-500">Adicionar um periférico que já está no kit atualiza a quantidade, o opcional e o grupo.</p>
        </>
      )}
      {erro && <span className="text-xs text-marca-700">{erro}</span>}
    </div>
  );
}

// Clientes e unidades: busca + clientes em ordem alfabética, recolhidos (clique expande as unidades).
// Sem busca mostra os 10 primeiros; com busca, todos os que batem, expandidos quando a unidade bateu.
// "Editar clientes" liga o modo de edição: renomear, mover unidade de cliente, reativar e excluir.
type ClienteL = { id: number; nome: string; ativo?: boolean };
type UnidadeL = { id: number; nome: string; cliente_id: number; ativo?: boolean };
const Inativo = () => <span className="ml-1 rounded bg-slate-200 px-1.5 py-0.5 text-xs">Inativo</span>;
const erroNome = (e: { code?: string; message: string }, oque: string) => (e.code === "23505" ? `Já existe ${oque} com esse nome` : e.message);

export function ClientesLista({ clientes, unidades }: { clientes: ClienteL[]; unidades: UnidadeL[] }) {
  const [q, setQ] = useState("");
  const [abertos, setAbertos] = useState<number[]>([]);
  const [todos, setTodos] = useState(false);
  const [modo, setModo] = useState(false);
  const [editando, setEditando] = useState<string | null>(null); // "c12" ou "u34"
  const [aviso, setAviso] = useState("");
  const router = useRouter();
  const norm = (t: string) => t.normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
  const busca = norm(q.trim());
  const ordenados = [...clientes].sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR", { sensitivity: "base" }));
  const linhas = ordenados.map((c) => {
    const us = unidades.filter((u) => u.cliente_id === c.id).sort((a, b) => a.nome.localeCompare(b.nome, "pt-BR"));
    const bateCliente = !busca || norm(c.nome).includes(busca);
    const bateUnidade = !!busca && us.some((u) => norm(u.nome).includes(busca));
    return { c, us, mostra: bateCliente || bateUnidade, expandeBusca: bateUnidade };
  }).filter((l) => l.mostra);
  const visiveis = busca || todos ? linhas : linhas.slice(0, 10);

  async function excluir(fn: "excluir_cliente" | "excluir_unidade", id: number, nome: string) {
    const msg = fn === "excluir_cliente" ? `Excluir o cliente "${nome}" e todas as unidades dele? Se houver histórico, tudo será só desativado.` : `Excluir a unidade "${nome}"? Se houver histórico, será só desativada.`;
    if (!confirm(msg)) return;
    const { data, error } = await supabaseBrowser().rpc(fn, { p_id: id });
    if (error) return setAviso(error.message);
    setAviso(data === "desativado" ? `"${nome}" tem histórico: foi desativado, não excluído.` : `"${nome}" foi excluído.`);
    router.refresh();
  }
  const botoes = (chave: string, fn: "excluir_cliente" | "excluir_unidade", id: number, nome: string) => modo && (
    <span className="ml-2 inline-flex gap-1">
      <button type="button" className="text-xs text-marinho-700 underline" onClick={() => setEditando(chave)}>Editar</button>
      <button type="button" className="text-xs text-marca-700 underline" onClick={() => excluir(fn, id, nome)}>Excluir</button>
    </span>
  );

  return (
    <div className="space-y-2 text-sm">
      <div className="flex flex-wrap gap-2">
        <input className="campo w-72" placeholder="Buscar cliente ou unidade" value={q} onChange={(e) => setQ(e.target.value)} />
        <button type="button" className={modo ? "btn" : "btn-sec"} onClick={() => { setModo(!modo); setEditando(null); }}>{modo ? "Concluir" : "Editar clientes"}</button>
      </div>
      {aviso && <p className="text-slate-700">{aviso}</p>}
      <ul className="divide-y divide-slate-100">
        {visiveis.map(({ c, us, expandeBusca }) => {
          const soPrincipal = !modo && us.length <= 1 && (us[0]?.nome ?? "Principal") === "Principal";
          const aberto = !soPrincipal && (expandeBusca || abertos.includes(c.id));
          return (
            <li key={c.id} className="py-1.5">
              {editando === `c${c.id}` ? <EditarNome tabela="cliente" id={c.id} nome={c.nome} ativo={c.ativo !== false} oque="um cliente" fechar={() => setEditando(null)} /> : (
                <div className="flex items-center">
                  {soPrincipal ? <span className="flex items-center gap-2"><span className="invisible w-3 text-xs" aria-hidden>▸</span><span className="font-medium">{c.nome}</span></span> : (
                    <button type="button" className="flex items-center gap-2 text-left" onClick={() => setAbertos(abertos.includes(c.id) ? abertos.filter((x) => x !== c.id) : [...abertos, c.id])}>
                      <span className="w-3 text-xs text-slate-400">{aberto ? "▾" : "▸"}</span>
                      <span className="font-medium">{c.nome}</span>
                      <span className="text-xs text-slate-500">{us.length} {us.length === 1 ? "unidade" : "unidades"}</span>
                    </button>
                  )}
                  {c.ativo === false && <Inativo />}
                  {botoes(`c${c.id}`, "excluir_cliente", c.id, c.nome)}
                </div>
              )}
              {aberto && !modo && (
                <div className="mt-1 flex flex-wrap gap-1 pl-5">
                  {us.map((u) => <span key={u.id} className={`rounded px-2 py-0.5 text-xs ${busca && norm(u.nome).includes(busca) ? "bg-amber-100" : "bg-slate-100"} ${u.ativo === false ? "line-through" : ""}`}>{u.nome}</span>)}
                </div>
              )}
              {aberto && modo && (
                <ul className="mt-1 space-y-1 pl-5">
                  {us.map((u) => (
                    <li key={u.id}>
                      {editando === `u${u.id}` ? <EditarNome tabela="unidade_cliente" id={u.id} nome={u.nome} ativo={u.ativo !== false} oque="uma unidade neste cliente" clienteId={u.cliente_id} clientes={ordenados} fechar={() => setEditando(null)} /> : (
                        <span>{u.nome}{u.ativo === false && <Inativo />}{botoes(`u${u.id}`, "excluir_unidade", u.id, u.nome)}</span>
                      )}
                    </li>
                  ))}
                  {us.length === 0 && <li className="text-slate-500">Sem unidades.</li>}
                </ul>
              )}
            </li>
          );
        })}
        {visiveis.length === 0 && <li className="py-1.5 text-slate-500">Nenhum cliente encontrado.</li>}
      </ul>
      {!busca && linhas.length > 10 && (
        <button type="button" className="btn-sec" onClick={() => setTodos(!todos)}>{todos ? "Ver menos" : `Ver todos (${linhas.length})`}</button>
      )}
    </div>
  );
}

// Editar cliente (nome, ativo) ou unidade (nome, cliente, ativo): update direto na tabela.
function EditarNome({ tabela, id, nome: n0, ativo: a0, oque, clienteId, clientes, fechar }: {
  tabela: "cliente" | "unidade_cliente"; id: number; nome: string; ativo: boolean; oque: string; clienteId?: number; clientes?: ClienteL[]; fechar: () => void;
}) {
  const [nome, setNome] = useState(n0);
  const [ativo, setAtivo] = useState(a0);
  const [cli, setCli] = useState<number | "">(clienteId ?? "");
  const [erro, setErro] = useState("");
  const router = useRouter();
  async function salvar(e: React.FormEvent) {
    e.preventDefault();
    const dados = tabela === "cliente" ? { nome: nome.trim(), ativo } : { nome: nome.trim(), ativo, cliente_id: cli };
    const { error } = await supabaseBrowser().from(tabela).update(dados).eq("id", id);
    if (error) return setErro(erroNome(error, oque));
    fechar(); router.refresh();
  }
  return (
    <form onSubmit={salvar} className="flex flex-wrap items-center gap-2">
      <input className="campo w-56" value={nome} onChange={(e) => setNome(e.target.value)} required />
      {clientes && (
        <select className="campo w-auto" value={cli} onChange={(e) => setCli(Number(e.target.value))} required>
          {clientes.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select>
      )}
      <label className="flex items-center gap-1"><input type="checkbox" checked={ativo} onChange={(e) => setAtivo(e.target.checked)} /> Ativo</label>
      <button className="btn">Salvar</button>
      <button type="button" className="btn-sec" onClick={fechar}>Cancelar</button>
      {erro && <span className="text-xs text-marca-700">{erro}</span>}
    </form>
  );
}

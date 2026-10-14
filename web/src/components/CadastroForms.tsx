"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { VINCULOS, type Tecnico, type Vinculo } from "@/lib/types";

type Opt = { id: number; nome: string };

function useSalvar() {
  const router = useRouter();
  const [erro, setErro] = useState("");
  return {
    erro,
    async salvar(fn: () => PromiseLike<{ error: { message: string } | null }>) {
      const { error } = await fn();
      setErro(error?.message ?? "");
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
      <button className="btn">Adicionar</button>{erro && <span className="text-xs text-red-700">{erro}</span>}
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
      <button className="btn">Adicionar</button>{erro && <span className="text-xs text-red-700">{erro}</span>}
    </form>
  );
}

export function NovoProduto({ categorias, fornecedores }: { categorias: Opt[]; fornecedores: Opt[] }) {
  const [nome, setNome] = useState("");
  const [cat, setCat] = useState<number | "">("");
  const [forn, setForn] = useState<number | "">("");
  const [min, setMin] = useState(0);
  const { erro, salvar } = useSalvar();
  return (
    <form className="flex flex-wrap items-end gap-2" onSubmit={async (e) => { e.preventDefault(); await salvar(() => supabaseBrowser().from("produto").insert({ nome, categoria_id: cat || null, fornecedor_id: forn || null, estoque_minimo: min })); setNome(""); }}>
      <label className="text-sm">Novo item<input className="campo mt-1" value={nome} onChange={(e) => setNome(e.target.value)} required /></label>
      <label className="text-sm">Categoria
        <select className="campo mt-1" value={cat} onChange={(e) => setCat(Number(e.target.value))} required>
          <option value="">Selecione</option>{categorias.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select></label>
      <label className="text-sm">Fornecedor
        <select className="campo mt-1" value={forn} onChange={(e) => setForn(Number(e.target.value))}>
          <option value="">-</option>{fornecedores.map((c) => <option key={c.id} value={c.id}>{c.nome}</option>)}
        </select></label>
      <label className="text-sm">Mínimo<input type="number" min={0} className="campo mt-1 w-24" value={min} onChange={(e) => setMin(Number(e.target.value))} /></label>
      <button className="btn">Adicionar</button>{erro && <span className="text-xs text-red-700">{erro}</span>}
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
      {erro && <span className="text-xs text-red-700">{erro}</span>}
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
      <button className="btn">Cadastrar</button>{erro && <span className="text-xs text-red-700">{erro}</span>}
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
        {erro && <div className="text-xs text-red-700">{erro}</div>}
      </td>
    </tr>
  );
}

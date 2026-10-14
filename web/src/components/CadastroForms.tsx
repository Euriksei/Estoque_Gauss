"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";

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

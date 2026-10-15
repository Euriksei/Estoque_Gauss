"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Busca } from "@/components/Busca";
import { CHIPS, type Local, type Produto } from "@/lib/types";

// Instala, troca ou retira o chip de módulos que estão no estoque. Mexe nos chips avulsos junto.
export function TrocarChipForm({ locais, modulos }: { locais: Local[]; modulos: Produto[] }) {
  const router = useRouter();
  const [local, setLocal] = useState<number | "">(locais.length === 1 ? locais[0].id : "");
  const [produto, setProduto] = useState<number | "">("");
  const [qtd, setQtd] = useState(1);
  const [de, setDe] = useState("novo");
  const [para, setPara] = useState("claro");
  const [retirado, setRetirado] = useState("estoque");
  const [obs, setObs] = useState("");
  const [msg, setMsg] = useState("");
  const [ok, setOk] = useState(false);
  const [ocupado, setOcupado] = useState(false);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setOcupado(true); setMsg("");
    const { error } = await supabaseBrowser().rpc("trocar_chip", {
      p: { local_id: local, produto_id: produto, quantidade: qtd, de, para, chip_retirado: retirado, observacao: obs },
    });
    setOcupado(false);
    setOk(!error);
    if (error) return setMsg(error.message);
    setMsg("Chip registrado."); setObs(""); setQtd(1);
    router.refresh();
  }

  const retira = de !== "novo";
  return (
    <form onSubmit={enviar} className="card grid gap-3 sm:grid-cols-2">
      <label className="text-sm">Estoque
        <select className="campo mt-1" required value={local} onChange={(e) => setLocal(Number(e.target.value))}>
          <option value="">Selecione</option>
          {locais.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
        </select>
      </label>
      <div className="text-sm">Módulo
        <Busca required value={produto} onChange={setProduto} placeholder="Digite para buscar o módulo" opcoes={modulos.map((m) => ({ value: m.id, label: m.nome }))} />
      </div>
      <label className="text-sm">Quantidade de módulos
        <input type="number" className="campo mt-1" min={1} step={1} inputMode="numeric" value={qtd || ""} required
          onKeyDown={(e) => { if (["-", "+", "e", "E", ".", ","].includes(e.key)) e.preventDefault(); }}
          onChange={(e) => { const n = Math.floor(Number(e.target.value)); setQtd(n > 0 ? n : 0); }} />
      </label>
      <div className="hidden sm:block" />
      <label className="text-sm">Chip que o módulo tem hoje
        <select className="campo mt-1" value={de} onChange={(e) => setDe(e.target.value)}>
          {Object.entries(CHIPS).map(([v, n]) => <option key={v} value={v}>{n}</option>)}
        </select>
      </label>
      <label className="text-sm">Chip que ele vai ficar
        <select className="campo mt-1" value={para} onChange={(e) => setPara(e.target.value)}>
          {Object.entries(CHIPS).map(([v, n]) => <option key={v} value={v}>{n === "Sem chip" ? "Sem chip (só retirar)" : n}</option>)}
        </select>
      </label>
      {retira && (
        <label className="text-sm sm:col-span-2">O que fazer com o chip retirado
          <select className="campo mt-1" value={retirado} onChange={(e) => setRetirado(e.target.value)}>
            <option value="estoque">Voltar para o estoque de chips avulsos</option>
            <option value="descartar">Descartar (chip ruim, módulo não comunicou)</option>
          </select>
        </label>
      )}
      <label className="text-sm sm:col-span-2">Observação{retirado === "descartar" && retira ? " (obrigatória ao descartar)" : ""}
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} required={retirado === "descartar" && retira} />
      </label>
      <p className="text-xs text-slate-500 sm:col-span-2">
        Instalar um chip baixa 1 chip avulso da operadora escolhida por módulo. Trocar de operadora devolve o chip antigo ao estoque avulso (ou descarta, se você escolher).
      </p>
      <div className="flex items-center gap-3 sm:col-span-2">
        <button className="btn" disabled={ocupado}>Registrar troca de chip</button>
        {msg && <p className={`text-sm ${ok ? "text-green-700" : "text-marca-700"}`}>{msg}</p>}
      </div>
    </form>
  );
}

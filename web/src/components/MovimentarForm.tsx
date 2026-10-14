"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import { MODOS, MODOS_COM_RASTREIO, TIPOS, VINCULOS, nomeUnidade, type Associado, type ItemForm, type Local, type Produto, type Tecnico, type Unidade } from "@/lib/types";

type Props = { tipos: string[]; locais: Local[]; produtos: Produto[]; unidades: Unidade[]; associados: Associado[]; fornecedores: { id: number; nome: string }[]; tecnicos: Tecnico[]; ehTecnico: boolean };

export function MovimentarForm({ tipos, locais, produtos, unidades, associados, fornecedores, tecnicos, ehTecnico }: Props) {
  const router = useRouter();
  const [tipo, setTipo] = useState(tipos[0]);
  const [localId, setLocalId] = useState<number | "">(locais.length === 1 ? locais[0].id : "");
  const [data, setData] = useState(new Date().toISOString().slice(0, 10));
  const [unidadeId, setUnidadeId] = useState<number | "">("");
  const [fornecedorId, setFornecedorId] = useState<number | "">("");
  const [nf, setNf] = useState("");
  const [finalidade, setFinalidade] = useState("");
  const [chamado, setChamado] = useState("");
  const [modo, setModo] = useState("");
  const [rastreio, setRastreio] = useState("");
  const [tecnicoId, setTecnicoId] = useState<number | "">("");
  const [obs, setObs] = useState("");
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [enviando, setEnviando] = useState(false);

  const cliente = tipo === "SAIDA_CLIENTE" || tipo === "DEVOLUCAO_CLIENTE";
  const saida = tipo === "SAIDA_CLIENTE";

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setMsg(null);
    const { error } = await supabaseBrowser().rpc("registrar_movimentacao", {
      p: {
        tipo, data, local_id: localId, unidade_id: unidadeId || null, fornecedor_id: fornecedorId || null,
        numero_nf: nf, finalidade, chamado_url: chamado, observacao: obs, itens: itensParaRpc(itens),
        modo_envio: modo, codigo_rastreio: rastreio, tecnico_id: tecnicoId || null,
      },
    });
    setEnviando(false);
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Movimentação registrada." });
    setItens([itemVazio()]);
    setObs("");
    setChamado("");
    setRastreio("");
    setNf("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-4">
      <div className="grid gap-3 sm:grid-cols-3">
        <label className="text-sm">Tipo
          <select className="campo mt-1" value={tipo} onChange={(e) => setTipo(e.target.value)}>
            {tipos.map((t) => <option key={t} value={t}>{TIPOS[t]}</option>)}
          </select>
        </label>
        <label className="text-sm">Local
          <select className="campo mt-1" value={localId} onChange={(e) => setLocalId(Number(e.target.value))} required>
            <option value="">Selecione</option>
            {locais.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
        <label className="text-sm">Data
          <input type="date" className="campo mt-1" value={data} onChange={(e) => setData(e.target.value)} required />
        </label>
      </div>

      {cliente && (
        <div className="grid gap-3 sm:grid-cols-3">
          <label className="text-sm sm:col-span-2">Cliente / unidade
            <select className="campo mt-1" value={unidadeId} onChange={(e) => setUnidadeId(Number(e.target.value))} required>
              <option value="">Selecione</option>
              {unidades.map((u) => <option key={u.id} value={u.id}>{nomeUnidade(u)}</option>)}
            </select>
          </label>
          {tipo === "SAIDA_CLIENTE" && (
            <label className="text-sm">Finalidade
              <select className="campo mt-1" value={finalidade} onChange={(e) => setFinalidade(e.target.value)}>
                <option value="">-</option>
                <option value="mobilizacao">Mobilização</option>
                <option value="manutencao">Manutenção</option>
              </select>
            </label>
          )}
          {saida && !ehTecnico && (
            <>
              <label className="text-sm">Modo de envio
                <select className="campo mt-1" value={modo} onChange={(e) => { setModo(e.target.value); setTecnicoId(""); }} required>
                  <option value="">Selecione</option>
                  {Object.entries(MODOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
                </select>
              </label>
              {modo === "tecnico" && (
                <label className="text-sm sm:col-span-2">Técnico que leva o material
                  <select className="campo mt-1" value={tecnicoId} onChange={(e) => setTecnicoId(Number(e.target.value))} required>
                    <option value="">Selecione</option>
                    {tecnicos.map((t) => <option key={t.id} value={t.id}>{t.nome} ({VINCULOS[t.vinculo]})</option>)}
                  </select>
                </label>
              )}
              {MODOS_COM_RASTREIO.includes(modo) && (
                <label className="text-sm sm:col-span-2">Código de rastreio
                  <input className="campo mt-1" value={rastreio} onChange={(e) => setRastreio(e.target.value)} />
                </label>
              )}
            </>
          )}
          {saida && ehTecnico && <p className="text-sm text-slate-600 sm:col-span-3">Envio por técnico: você é registrado como o técnico que levou o material.</p>}
          <label className="text-sm sm:col-span-3">Link do chamado no Jira (opcional)
            <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
          </label>
        </div>
      )}

      {tipo === "ENTRADA_COMPRA" && (
        <div className="grid gap-3 sm:grid-cols-2">
          <label className="text-sm">Fornecedor
            <select className="campo mt-1" value={fornecedorId} onChange={(e) => setFornecedorId(Number(e.target.value))}>
              <option value="">-</option>
              {fornecedores.map((f) => <option key={f.id} value={f.id}>{f.nome}</option>)}
            </select>
          </label>
          <label className="text-sm">NF de entrada
            <input className="campo mt-1" value={nf} onChange={(e) => setNf(e.target.value)} />
          </label>
        </div>
      )}

      <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={tipo === "SAIDA_CLIENTE" ? associados : []}
        unidades={unidades} reserva={tipo === "SAIDA_CLIENTE" ? "reservado" : "nenhuma"} permiteNegativo={tipo === "AJUSTE"} />

      <label className="block text-sm">{tipo === "AJUSTE" ? "Justificativa (obrigatória; use quantidade negativa para baixar)" : "Observação"}
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} required={tipo === "AJUSTE"} />
      </label>

      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-red-700"}`}>{msg.texto}</p>}
      <button className="btn" disabled={enviando}>Registrar</button>
    </form>
  );
}

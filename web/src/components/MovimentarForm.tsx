"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Busca } from "@/components/Busca";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import { MODOS, MODOS_COM_RASTREIO, TIPOS, VINCULOS, nomeUnidade, type Associado, type ItemForm, type Local, type Produto, type Tecnico, type Unidade } from "@/lib/types";

type Props = { tipos: string[]; locais: Local[]; produtos: Produto[]; unidades: Unidade[]; associados: Associado[]; fornecedores: { id: number; nome: string }[]; tecnicos: Tecnico[]; ehTecnico: boolean;
  // Estoques de técnicos (destino da saída para estoque técnico), com o técnico dono de cada um.
  estoquesTecnico: { local_id: number; tecnico: Tecnico }[] };

export function MovimentarForm({ tipos, locais, produtos, unidades, associados, fornecedores, tecnicos, ehTecnico, estoquesTecnico }: Props) {
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
  const [prazo, setPrazo] = useState("");
  const [obs, setObs] = useState("");
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);
  const [enviando, setEnviando] = useState(false);

  const cliente = tipo === "SAIDA_CLIENTE" || tipo === "DEVOLUCAO_CLIENTE";
  const saida = tipo === "SAIDA_CLIENTE";
  const paraTecnico = tipo === "SAIDA_TECNICO";

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    setEnviando(true);
    setMsg(null);
    // Saída para estoque técnico = transferência: sai do estoque agora e só entra no do técnico quando ele confirmar.
    if (tipo === "SAIDA_TECNICO") {
      const destino = estoquesTecnico.find((e) => e.tecnico.id === tecnicoId)?.local_id;
      const r = await supabaseBrowser().rpc("criar_transferencia", {
        p: { origem_id: localId, destino_id: destino, data, modo_envio: modo, codigo_rastreio: rastreio, prazo_chegada: prazo, observacao: obs, itens: itensParaRpc(itens) },
      });
      setEnviando(false);
      if (r.error) return setMsg({ ok: false, texto: r.error.message });
      setMsg({ ok: true, texto: "Enviado ao estoque do técnico. O saldo só entra nele quando o técnico confirmar o recebimento." });
      setItens([itemVazio()]); setObs(""); setRastreio("");
      router.refresh();
      return;
    }
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
          <div className="text-sm sm:col-span-2">Cliente / unidade
            <div className="mt-1"><Busca required value={unidadeId} onChange={setUnidadeId} placeholder="Digite para buscar o cliente"
              opcoes={unidades.map((u) => ({ value: u.id, label: nomeUnidade(u) }))} /></div>
          </div>
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

      {paraTecnico && (
        <div className="grid gap-3 sm:grid-cols-4">
          <label className="text-sm sm:col-span-2">Estoque do técnico
            <select className="campo mt-1" value={tecnicoId} onChange={(e) => setTecnicoId(Number(e.target.value))} required>
              <option value="">Selecione</option>
              {estoquesTecnico.map((e) => <option key={e.local_id} value={e.tecnico.id}>{e.tecnico.nome} ({VINCULOS[e.tecnico.vinculo]})</option>)}
            </select>
          </label>
          <label className="text-sm">Meio de envio
            <select className="campo mt-1" value={modo} onChange={(e) => setModo(e.target.value)}>
              <option value="">-</option>
              {Object.entries(MODOS).map(([k, v]) => <option key={k} value={k}>{v}</option>)}
            </select>
          </label>
          <label className="text-sm">Prazo de chegada
            <input type="date" className="campo mt-1" value={prazo} onChange={(e) => setPrazo(e.target.value)} />
          </label>
          {MODOS_COM_RASTREIO.includes(modo) && (
            <label className="text-sm sm:col-span-4">Código de rastreio
              <input className="campo mt-1" value={rastreio} onChange={(e) => setRastreio(e.target.value)} />
            </label>
          )}
          <p className="text-xs text-slate-500 sm:col-span-4">O saldo sai do seu estoque agora e só entra no estoque do técnico quando ele confirmar o recebimento (em Transferências).</p>
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

      <ItensEditor key={tipo} itens={itens} onChange={setItens} produtos={produtos} associados={associados}
        chicote={tipo === "ENTRADA_COMPRA" || tipo === "DEVOLUCAO_CLIENTE" ? "sempre" : tipo === "SAIDA_CLIENTE" || paraTecnico ? "opcional" : "nenhum"}
        unidades={unidades} reserva={paraTecnico || tipo === "ENTRADA_COMPRA" || tipo === "AJUSTE" ? "reservar" : "nenhuma"} permiteNegativo={tipo === "AJUSTE"} />

      <label className="block text-sm">{tipo === "AJUSTE" ? "Justificativa (obrigatória; escolha Aumentar ou Reduzir em cada item)" : "Observação"}
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} required={tipo === "AJUSTE"} />
      </label>

      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-red-700"}`}>{msg.texto}</p>}
      <button className="btn" disabled={enviando}>Registrar</button>
    </form>
  );
}

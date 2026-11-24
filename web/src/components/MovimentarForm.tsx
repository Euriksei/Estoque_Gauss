"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Busca } from "@/components/Busca";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import { MODOS, MODOS_COM_RASTREIO, TIPOS, VINCULOS, hojeSP, nomeItem, nomeUnidade, type Associado, type ItemForm, type Local, type Produto, type Tecnico, type Unidade } from "@/lib/types";

export type Saldo = { local_id: number; produto_id: number; condicao: string; reservado_unidade_id: number | null; quantidade: number };
// Tipos que tiram do estoque do local escolhido (no ajuste, só as linhas "Reduzir").
const SAIDAS = ["SAIDA_CLIENTE", "CONSUMO_INTERNO", "DESCARTE", "AJUSTE"];

type Props = { saldo: Saldo[]; tipos: string[]; locais: Local[]; produtos: Produto[]; unidades: Unidade[]; associados: Associado[]; fornecedores: { id: number; nome: string }[]; tecnicos: Tecnico[]; ehTecnico: boolean };

export function MovimentarForm({ saldo, tipos, locais, produtos, unidades, associados, fornecedores, tecnicos, ehTecnico }: Props) {
  const router = useRouter();
  const [tipo, setTipo] = useState(tipos[0]);
  const [localId, setLocalId] = useState<number | "">(locais.length === 1 ? locais[0].id : "");
  const [data, setData] = useState(hojeSP);
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
  const comChicote = tipo === "ENTRADA_COMPRA" || tipo === "DEVOLUCAO_CLIENTE" || tipo === "SAIDA_CLIENTE";
  const linhasRpc = () => itensParaRpc(itens, comChicote ? associados : []);

  // Disponível no local escolhido, por item + chip + reserva (livre ou dedicado), como na view saldo.
  const confere = SAIDAS.includes(tipo) && localId !== "";
  const usaChip = (id: number | "") => !!produtos.find((p) => p.id === id)?.usa_chip;
  const chave = (pid: number | "", chip: string | undefined, res: number | "" | null | undefined) => `${pid}|${usaChip(pid) ? chip || "novo" : "novo"}|${res || ""}`;
  // No ajuste o item sai da reserva escolhida; nas demais saídas, do estoque livre (ou do reservado informado).
  const reservaDe = (l: { reservado_unidade_id?: number | "" | null; reservar_para_unidade_id?: number | "" | null }) =>
    tipo === "AJUSTE" ? l.reservar_para_unidade_id || l.reservado_unidade_id : l.reservado_unidade_id;
  const disponivel = new Map<string, number>();
  for (const s of saldo) if (s.local_id === localId) {
    const k = `${s.produto_id}|${s.condicao}|${s.reservado_unidade_id ?? ""}`;
    disponivel.set(k, (disponivel.get(k) ?? 0) + s.quantidade);
  }
  // Quanto sai de cada item/chip/reserva, somando linhas repetidas e os chicotes gerados.
  const retirada = new Map<string, { qtd: number; produto_id: number; chip?: string; res: number | null }>();
  if (confere) for (const l of linhasRpc()) {
    if (l.produto_id === "" || (usaChip(l.produto_id) && !l.condicao)) continue;
    const res = reservaDe(l) || null;
    const k = chave(l.produto_id, l.condicao, res);
    const r = retirada.get(k) ?? { qtd: 0, produto_id: l.produto_id, chip: l.condicao, res };
    r.qtd += tipo === "AJUSTE" ? -l.quantidade : l.quantidade;
    retirada.set(k, r);
  }
  const nomeLocal = locais.find((l) => l.id === localId)?.nome ?? "";
  const faltas = [...retirada.entries()].filter(([k, r]) => r.qtd > 0 && r.qtd > (disponivel.get(k) ?? 0)).map(([k, r]) => {
    const p = produtos.find((x) => x.id === r.produto_id);
    const u = unidades.find((x) => x.id === r.res);
    return `Só há ${disponivel.get(k) ?? 0} ${nomeItem(p?.nome, p?.usa_chip, r.chip || "novo")}${u ? ` dedicado(s) a ${nomeUnidade(u)}` : " livre(s)"} em ${nomeLocal} (você está tirando ${r.qtd}).`;
  });
  // Linha do editor: mostra o disponível quando o item (e o chip, se for módulo) já foi escolhido.
  const dispLinha = (it: ItemForm) => {
    if (!confere || it.produto_id === "" || (usaChip(it.produto_id) && !it.chip) || (tipo === "AJUSTE" && it.sentido !== "menos")) return null;
    const k = chave(it.produto_id, it.chip, reservaDe(it));
    const d = disponivel.get(k) ?? 0;
    return { disponivel: d, passou: (retirada.get(k)?.qtd ?? 0) > d };
  };

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    if (faltas.length > 0) return setMsg({ ok: false, texto: faltas.join(" ") });
    setEnviando(true);
    setMsg(null);
    const { error } = await supabaseBrowser().rpc("registrar_movimentacao", {
      p: {
        tipo, data, local_id: localId, unidade_id: unidadeId || null, fornecedor_id: fornecedorId || null,
        numero_nf: nf, finalidade, chamado_url: chamado, observacao: obs, itens: linhasRpc(),
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
          <select className="campo mt-1" value={tipo} onChange={(e) => {
            const t = e.target.value;
            setTipo(t);
            // "Dedicado para" só existe na devolução, no ajuste e na saída para técnico: não leva a escolha para outro tipo.
            if (!["DEVOLUCAO_CLIENTE", "AJUSTE"].includes(t)) setItens(itens.map((it) => ({ ...it, reservar_para_unidade_id: undefined })));
          }}>
            {tipos.map((t) => <option key={t} value={t}>{TIPOS[t]}</option>)}
          </select>
        </label>
        <label className="text-sm">Local
          {/* Só os estoques que o usuário movimenta; se for um só, já vem escolhido e travado. */}
          <select className="campo mt-1" value={localId} onChange={(e) => setLocalId(e.target.value ? Number(e.target.value) : "")} required disabled={locais.length === 1}>
            {locais.length > 1 && <option value="">Selecione</option>}
            {locais.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
          </select>
        </label>
        <label className="text-sm">Data
          <input type="date" className="campo mt-1" value={data} max={hojeSP()} onChange={(e) => setData(e.target.value)} required />
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
        chicote={comChicote ? "sim" : "nenhum"} disponivel={dispLinha}
        unidades={unidades} reserva={tipo === "DEVOLUCAO_CLIENTE" || tipo === "AJUSTE" ? "reservar" : "nenhuma"} permiteNegativo={tipo === "AJUSTE"} />

      <label className="block text-sm">{tipo === "AJUSTE" ? "Justificativa (obrigatória; escolha Aumentar ou Reduzir em cada item)" : "Observação"}
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} required={tipo === "AJUSTE"} />
      </label>

      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-marca-700"}`}>{msg.texto}</p>}
      <button className="btn" disabled={enviando}>Registrar</button>
    </form>
  );
}

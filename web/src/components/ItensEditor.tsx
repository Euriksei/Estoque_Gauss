"use client";
import { Busca } from "@/components/Busca";
import { CHIPS, REDES, nomeUnidade, type Associado, type ItemForm, type Produto, type Unidade } from "@/lib/types";

type Props = {
  itens: ItemForm[];
  onChange: (itens: ItemForm[]) => void;
  produtos: Produto[];
  associados: Associado[];
  unidades: Unidade[];
  // "reservado": usar item já reservado (saída/ajuste); "reservar": reservar no destino (transferência)
  reserva?: "reservado" | "reservar" | "nenhuma";
  permiteNegativo?: boolean; // ajuste de inventário: mostra Aumentar/Reduzir (a quantidade é sempre positiva)
  // "sim": cada item com associados (item_associado) ganha o "Com kit": um periférico por linha, com caixa e quantidade.
  chicote?: "sim" | "nenhum";
  // "sim": cada módulo de telemetria ganha a escolha do chip (sem chip, Claro, Vivo, Arqia).
  chip?: "sim" | "nenhum";
  // Saídas: saldo disponível da linha no local escolhido (null = não mostrar) e se a quantidade passou dele.
  disponivel?: (it: ItemForm) => { disponivel: number; passou: boolean } | null;
  permiteVazio?: boolean; // deixa tirar a última linha (pedido que leva só dedicado)
};

export const itemVazio = (): ItemForm => ({ produto_id: "", quantidade: 1 });

export function ItensEditor({ itens, onChange, produtos, associados, unidades, reserva = "nenhuma", permiteNegativo, chicote = "nenhum", chip = "sim", disponivel, permiteVazio }: Props) {
  const nomeUn = (u: Unidade) => nomeUnidade(u);
  const nomeProd = new Map(produtos.map((p) => [p.id, p.nome]));

  function mudar(i: number, parte: Partial<ItemForm>) {
    onChange(itens.map((it, k) => (k === i ? { ...it, ...parte } : it)));
  }

  return (
    <div className="space-y-2">
      {itens.map((it, i) => (
        <div key={i} className="grid grid-cols-12 items-end gap-2">
          <div className="col-span-12 text-xs sm:col-span-5">{i === 0 && <span className="block">Item</span>}
            <Busca required value={it.produto_id} onChange={(v) => mudar(i, { produto_id: v, chip: undefined, kitAberto: undefined, kit: undefined, kitGrupo: undefined })} placeholder="Digite para buscar o item"
              opcoes={produtos.map((p) => ({ value: p.id, label: p.nome }))} />
          </div>
          {permiteNegativo && (
            <label className="col-span-5 text-xs sm:col-span-2">{i === 0 && "Ajuste"}
              <select className="campo" value={it.sentido ?? "mais"} onChange={(e) => mudar(i, { sentido: e.target.value as "mais" | "menos" })}>
                <option value="mais">Aumentar</option>
                <option value="menos">Reduzir</option>
              </select>
            </label>
          )}
          <label className="col-span-3 text-xs sm:col-span-1">{i === 0 && "Qtd."}
            <input type="number" className="campo" min={1} step={1} inputMode="numeric" value={it.quantidade || ""}
              onKeyDown={(e) => { if (["-", "+", "e", "E", ".", ","].includes(e.key)) e.preventDefault(); }}
              onChange={(e) => { const n = Math.floor(Number(e.target.value)); mudar(i, { quantidade: n > 0 ? n : 0 }); }} required />
          </label>
          {reserva !== "nenhuma" && (
            <div className="col-span-12 text-xs sm:col-span-3">{i === 0 && <span className="block">{reserva === "reservar" ? "Dedicado para (opcional)" : "Item reservado de (opcional)"}</span>}
              <Busca vazio="Estoque livre" placeholder="Estoque livre" opcoes={unidades.map((u) => ({ value: u.id, label: nomeUn(u) }))}
                value={(reserva === "reservar" ? it.reservar_para_unidade_id : it.reservado_unidade_id) ?? ""}
                onChange={(v) => mudar(i, reserva === "reservar" ? { reservar_para_unidade_id: v } : { reservado_unidade_id: v })} />
            </div>
          )}
          <button type="button" className="btn-sec col-span-2 whitespace-nowrap sm:col-span-1" title="Tira esta linha da lista antes de registrar" onClick={() => onChange(itens.filter((_, k) => k !== i))} disabled={!permiteVazio && itens.length === 1}>
            Tirar
          </button>
          {chip === "sim" && it.produto_id !== "" && produtos.find((x) => x.id === it.produto_id)?.usa_chip && (
            <label className="col-span-12 flex items-center gap-2 pl-1 text-sm">Chip{(() => { const r = produtos.find((x) => x.id === it.produto_id)?.chip_rede; return r ? ` (usa chip ${REDES[r]})` : ""; })()}
              <select className="campo w-auto" required value={it.chip ?? ""} onChange={(e) => mudar(i, { chip: e.target.value })}>
                <option value="">Escolha o chip</option>
                {Object.entries(CHIPS).map(([v, n]) => <option key={v} value={v}>{n}</option>)}
              </select>
            </label>
          )}
          {(() => {
            const d = disponivel?.(it);
            return d && (
              <p data-disponivel={d.disponivel} className={`col-span-12 pl-1 text-xs ${d.passou ? "font-medium text-marca-700" : "text-slate-600"}`}>
                Disponível: {d.disponivel}{d.passou && " (a quantidade passa do disponível)"}
              </p>
            );
          })()}
          {chicote === "sim" && it.produto_id !== "" && associados.some((a) => a.produto_id === it.produto_id) && (() => {
            const linhas = linhasKit(it, associados);
            const grupos = [...new Set(associados.filter((a) => a.produto_id === it.produto_id && a.grupo).map((a) => a.grupo as string))];
            const disp = (l: LinhaKit) => {
              const d = l.on ? disponivel?.({ produto_id: l.produto_id, quantidade: l.qtd, reservado_unidade_id: it.reservado_unidade_id, reservar_para_unidade_id: it.reservar_para_unidade_id, sentido: it.sentido }) : null;
              return d && <span className={`text-xs ${d.passou ? "font-medium text-marca-700" : "text-slate-500"}`}>disponível: {d.disponivel}</span>;
            };
            const linha = (l: LinhaKit) => (
              <div key={l.chave} className={`flex flex-wrap items-center gap-2 ${l.nivel ? "pl-10" : "pl-5"}`}>
                <label className="flex items-center gap-2">
                  <input type="checkbox" checked={l.on} onChange={(e) => mudar(i, { kit: { ...it.kit, [l.chave]: { ...it.kit?.[l.chave], on: e.target.checked } } })} />
                  {nomeProd.get(l.produto_id)}{l.opcional && <span className="text-xs text-slate-500">(opcional)</span>}
                </label>
                {disp(l)}
              </div>
            );
            return (
              <div className="col-span-12 space-y-1 pl-1 text-sm">
                <label className="flex flex-wrap items-center gap-2">
                  <input type="checkbox" checked={!it.kitAberto} onChange={(e) => mudar(i, { kitAberto: !e.target.checked, kit: undefined, kitGrupo: undefined })} />
                  Kit completo
                  <span className="text-xs text-slate-500">({linhasKit({ ...it, kitAberto: false }, associados).filter((l) => l.on).map((l) => nomeProd.get(l.produto_id)).join(", ") || "nada obrigatório"})</span>
                </label>
                {it.kitAberto && <p className="text-xs text-slate-500">Marque o que vai junto (a quantidade é a do kit).</p>}
                {it.kitAberto && linhas.filter((l) => !l.grupo && l.nivel === 0).map((l) => [linha(l), ...linhas.filter((x) => x.pai === l.produto_id && l.on).map(linha)])}
                {it.kitAberto && grupos.map((g) => (
                  <div key={g} className="space-y-1 pl-5">
                    <p className="text-xs text-slate-600">{g} (escolha um)</p>
                    {[{ associado_id: 0 }, ...associados.filter((a) => a.produto_id === it.produto_id && a.grupo === g)].map((a) => {
                      const l = linhas.find((x) => x.grupo === g && x.produto_id === a.associado_id);
                      return (
                        <div key={a.associado_id} className="space-y-1">
                          <div className="flex flex-wrap items-center gap-2 pl-5">
                            <label className="flex items-center gap-2">
                              <input type="radio" name={`kit-${i}-${g}`} checked={(it.kitGrupo?.[g] ?? 0) === a.associado_id}
                                onChange={() => mudar(i, { kitGrupo: { ...it.kitGrupo, [g]: a.associado_id } })} />
                              {a.associado_id ? nomeProd.get(a.associado_id) : "Nenhum"}
                            </label>
                            {l && disp(l)}
                          </div>
                          {l && linhas.filter((x) => x.pai === l.produto_id).map(linha)}
                        </div>
                      );
                    })}
                  </div>
                ))}
              </div>
            );
          })()}
        </div>
      ))}
      <button type="button" className="btn-sec" onClick={() => onChange([...itens, itemVazio()])}>+ Adicionar item</button>
    </div>
  );
}

// Uma linha do kit: periférico do item (nível 0) ou associado da peça escolhida (nível 1, ex.: o plug da case).
export type LinhaKit = { chave: string; produto_id: number; qtd: number; on: boolean; opcional: boolean; grupo: string | null; nivel: 0 | 1; pai?: number };

// Monta o kit da linha a partir de item_associado: padrão = quantidade do associado x a do item; opcional vem
// desmarcado; no grupo só entra o escolhido. A peça escolhida traz os associados dela (um nível só).
export function linhasKit(it: ItemForm, associados: Associado[]): LinhaKit[] {
  const out: LinhaKit[] = [];
  if (it.produto_id === "") return out;
  // Kit completo (padrão): vale o kit como cadastrado, sem os ajustes; opcional e grupo sem escolha não vão.
  if (!it.kitAberto) it = { ...it, kit: undefined, kitGrupo: undefined };
  for (const a of associados.filter((x) => x.produto_id === it.produto_id)) {
    const chave = String(a.associado_id);
    if (a.grupo && it.kitGrupo?.[a.grupo] !== a.associado_id) continue;
    const on = a.grupo ? true : it.kit?.[chave]?.on ?? !a.opcional;
    const qtd = a.quantidade * (it.quantidade || 0);
    out.push({ chave, produto_id: a.associado_id, qtd, on, opcional: !!a.opcional, grupo: a.grupo ?? null, nivel: 0 });
    for (const b of associados.filter((x) => x.produto_id === a.associado_id)) {
      const c2 = `${a.associado_id}>${b.associado_id}`;
      out.push({ chave: c2, produto_id: b.associado_id, qtd: b.quantidade * qtd, on: on && (it.kit?.[c2]?.on ?? !b.opcional), opcional: !!b.opcional, grupo: null, nivel: 1, pai: a.associado_id });
    }
  }
  return out;
}

// Converte o formulário no formato que as funções do banco esperam. Com `associados`, cada periférico marcado
// do kit vira também uma linha (somando quando o mesmo item aparece em várias linhas).
export function itensParaRpc(itens: ItemForm[], associados: Associado[] = []) {
  const linhas = itens.map((i) => ({
    produto_id: i.produto_id,
    quantidade: i.sentido === "menos" ? -Math.abs(i.quantidade) : Math.abs(i.quantidade),
    reservado_unidade_id: i.reservado_unidade_id || null,
    reservar_para_unidade_id: i.reservar_para_unidade_id || null,
    condicao: i.chip || undefined,
  }));
  for (const i of itens) {
    for (const k of linhasKit(i, associados)) {
      if (!k.on || k.qtd <= 0) continue;
      const sinal = i.sentido === "menos" ? -1 : 1;
      const igual = linhas.find((l) => l.produto_id === k.produto_id && !l.condicao && l.reservado_unidade_id === (i.reservado_unidade_id || null) && l.reservar_para_unidade_id === (i.reservar_para_unidade_id || null));
      if (igual) igual.quantidade += sinal * k.qtd;
      else linhas.push({ produto_id: k.produto_id, quantidade: sinal * k.qtd, reservado_unidade_id: i.reservado_unidade_id || null, reservar_para_unidade_id: i.reservar_para_unidade_id || null, condicao: undefined });
    }
  }
  return linhas;
}

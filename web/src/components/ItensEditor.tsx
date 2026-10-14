"use client";
import { Busca } from "@/components/Busca";
import { nomeUnidade, type Associado, type ItemForm, type Produto, type Unidade } from "@/lib/types";

type Props = {
  itens: ItemForm[];
  onChange: (itens: ItemForm[]) => void;
  produtos: Produto[];
  associados: Associado[];
  unidades: Unidade[];
  // "reservado": usar item já reservado (saída/ajuste); "reservar": reservar no destino (transferência)
  reserva?: "reservado" | "reservar" | "nenhuma";
  permiteNegativo?: boolean; // ajuste de inventário: mostra Aumentar/Reduzir (a quantidade é sempre positiva)
  // "sim": cada módulo que tem chicote ganha a caixa "Com chicote" (marcada por padrão), por linha.
  chicote?: "sim" | "nenhum";
};

export const itemVazio = (): ItemForm => ({ produto_id: "", quantidade: 1 });

export function ItensEditor({ itens, onChange, produtos, associados, unidades, reserva = "nenhuma", permiteNegativo, chicote = "nenhum" }: Props) {
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
            <Busca required value={it.produto_id} onChange={(v) => mudar(i, { produto_id: v, chicote: true, chicoteQtd: undefined })} placeholder="Digite para buscar o item"
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
          <button type="button" className="btn-sec col-span-2 whitespace-nowrap sm:col-span-1" title="Tira esta linha da lista antes de registrar" onClick={() => onChange(itens.filter((_, k) => k !== i))} disabled={itens.length === 1}>
            Tirar
          </button>
          {chicote === "sim" && it.produto_id !== "" && associados.some((a) => a.produto_id === it.produto_id) && (
            <div className="col-span-12 flex flex-wrap items-center gap-2 pl-1 text-sm">
              <label className="flex items-center gap-2">
                <input type="checkbox" checked={it.chicote !== false} onChange={(e) => mudar(i, { chicote: e.target.checked, chicoteQtd: undefined })} />
                Com chicote ({associados.filter((a) => a.produto_id === it.produto_id).map((a) => nomeProd.get(a.associado_id)).join(", ")})
              </label>
              {it.chicote !== false && (
                <label className="flex items-center gap-1 text-xs text-slate-600">quantidade
                  <input type="number" min={1} step={1} className="campo w-20" value={qtdChicote(it, associados)}
                    onKeyDown={(e) => { if (["-", "+", "e", "E", ".", ","].includes(e.key)) e.preventDefault(); }}
                    onChange={(e) => { const n = Math.floor(Number(e.target.value)); mudar(i, { chicoteQtd: n > 0 ? n : 0 }); }} />
                </label>
              )}
            </div>
          )}
        </div>
      ))}
      <button type="button" className="btn-sec" onClick={() => onChange([...itens, itemVazio()])}>+ Adicionar item</button>
    </div>
  );
}

// Quantidade de chicotes da linha: a do módulo vezes a do par, a menos que tenha sido editada.
const qtdChicote = (it: ItemForm, associados: Associado[]) =>
  it.chicoteQtd ?? (associados.find((a) => a.produto_id === it.produto_id)?.quantidade ?? 1) * (it.quantidade || 0);

// Converte o formulário no formato que as funções do banco esperam. Com `associados`, cada linha marcada
// "com chicote" gera também a linha do chicote (somando quando o mesmo chicote aparece em várias linhas).
export function itensParaRpc(itens: ItemForm[], associados: Associado[] = []) {
  const linhas = itens.map((i) => ({
    produto_id: i.produto_id,
    quantidade: i.sentido === "menos" ? -Math.abs(i.quantidade) : Math.abs(i.quantidade),
    reservado_unidade_id: i.reservado_unidade_id || null,
    reservar_para_unidade_id: i.reservar_para_unidade_id || null,
  }));
  for (const i of itens) {
    if (i.produto_id === "" || i.chicote === false) continue;
    for (const a of associados.filter((x) => x.produto_id === i.produto_id)) {
      const qtd = qtdChicote(i, associados);
      if (qtd <= 0) continue;
      const sinal = i.sentido === "menos" ? -1 : 1;
      const igual = linhas.find((l) => l.produto_id === a.associado_id && l.reservado_unidade_id === (i.reservado_unidade_id || null) && l.reservar_para_unidade_id === (i.reservar_para_unidade_id || null));
      if (igual) igual.quantidade += sinal * qtd;
      else linhas.push({ produto_id: a.associado_id, quantidade: sinal * qtd, reservado_unidade_id: i.reservado_unidade_id || null, reservar_para_unidade_id: i.reservar_para_unidade_id || null });
    }
  }
  return linhas;
}

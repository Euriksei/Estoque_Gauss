"use client";
import { nomeUnidade, type Associado, type ItemForm, type Produto, type Unidade } from "@/lib/types";

type Props = {
  itens: ItemForm[];
  onChange: (itens: ItemForm[]) => void;
  produtos: Produto[];
  associados: Associado[];
  unidades: Unidade[];
  // "reservado": usar item já reservado (saída/ajuste); "reservar": reservar no destino (transferência)
  reserva?: "reservado" | "reservar" | "nenhuma";
  permiteNegativo?: boolean;
};

export const itemVazio = (): ItemForm => ({ produto_id: "", condicao: "novo", quantidade: 1 });

export function ItensEditor({ itens, onChange, produtos, associados, unidades, reserva = "nenhuma", permiteNegativo }: Props) {
  const nomeUn = (u: Unidade) => nomeUnidade(u);

  function mudar(i: number, parte: Partial<ItemForm>) {
    onChange(itens.map((it, k) => (k === i ? { ...it, ...parte } : it)));
  }

  // Ao escolher um item, sugere os associados (ex.: módulo Galileo -> chicote Galileo); tudo editável.
  function escolher(i: number, produtoId: number | "") {
    const novos = itens.map((it, k) => (k === i ? { ...it, produto_id: produtoId } : it));
    if (produtoId !== "") {
      const qtd = novos[i].quantidade || 1;
      for (const a of associados.filter((x) => x.produto_id === produtoId)) {
        if (!novos.some((it) => it.produto_id === a.associado_id)) {
          novos.push({ ...itemVazio(), produto_id: a.associado_id, quantidade: a.quantidade * qtd });
        }
      }
    }
    onChange(novos);
  }

  return (
    <div className="space-y-2">
      {itens.map((it, i) => (
        <div key={i} className="grid grid-cols-12 items-end gap-2">
          <label className="col-span-12 text-xs sm:col-span-5">{i === 0 && "Item"}
            <select className="campo" value={it.produto_id} onChange={(e) => escolher(i, e.target.value ? Number(e.target.value) : "")} required>
              <option value="">Selecione o item</option>
              {produtos.map((p) => (
                <option key={p.id} value={p.id}>{p.nome}</option>
              ))}
            </select>
          </label>
          <label className="col-span-4 text-xs sm:col-span-2">{i === 0 && "Condição"}
            <select className="campo" value={it.condicao} onChange={(e) => mudar(i, { condicao: e.target.value as "novo" | "usado" })}>
              <option value="novo">Novo</option>
              <option value="usado">Usado</option>
            </select>
          </label>
          <label className="col-span-3 text-xs sm:col-span-1">{i === 0 && "Qtd."}
            <input type="number" className="campo" min={permiteNegativo ? undefined : 1} value={it.quantidade}
              onChange={(e) => mudar(i, { quantidade: Number(e.target.value) })} required />
          </label>
          {reserva !== "nenhuma" && (
            <label className="col-span-12 text-xs sm:col-span-3">{i === 0 && (reserva === "reservar" ? "Dedicado para (opcional)" : "Item reservado de (opcional)")}
              <select className="campo"
                value={(reserva === "reservar" ? it.reservar_para_unidade_id : it.reservado_unidade_id) ?? ""}
                onChange={(e) => {
                  const v = e.target.value ? Number(e.target.value) : "";
                  mudar(i, reserva === "reservar" ? { reservar_para_unidade_id: v } : { reservado_unidade_id: v });
                }}>
                <option value="">Estoque livre</option>
                {unidades.map((u) => (
                  <option key={u.id} value={u.id}>{nomeUn(u)}</option>
                ))}
              </select>
            </label>
          )}
          <button type="button" className="btn-sec col-span-2 sm:col-span-1" onClick={() => onChange(itens.filter((_, k) => k !== i))} disabled={itens.length === 1}>
            Remover
          </button>
        </div>
      ))}
      <button type="button" className="btn-sec" onClick={() => onChange([...itens, itemVazio()])}>+ Adicionar item</button>
    </div>
  );
}

// Converte o formulário no formato que as funções do banco esperam.
export function itensParaRpc(itens: ItemForm[]) {
  return itens.map((i) => ({
    produto_id: i.produto_id,
    condicao: i.condicao,
    quantidade: i.quantidade,
    reservado_unidade_id: i.reservado_unidade_id || null,
    reservar_para_unidade_id: i.reservar_para_unidade_id || null,
  }));
}

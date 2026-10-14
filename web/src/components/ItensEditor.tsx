"use client";
import { useState } from "react";
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
  // Chicote que acompanha o módulo: "sempre" (entrada: caixa marcada por padrão), "opcional" (saída: caixa
  // "Enviar chicote junto", marcada por padrão) ou "nenhum".
  chicote?: "sempre" | "opcional" | "nenhum";
};

export const itemVazio = (): ItemForm => ({ produto_id: "", condicao: "novo", quantidade: 1 });

export function ItensEditor({ itens, onChange, produtos, associados, unidades, reserva = "nenhuma", permiteNegativo, chicote = "nenhum" }: Props) {
  const [junto, setJunto] = useState(true);
  const sugerir = chicote !== "nenhum" && junto;
  const nomeUn = (u: Unidade) => nomeUnidade(u);

  function mudar(i: number, parte: Partial<ItemForm>) {
    onChange(itens.map((it, k) => (k === i ? { ...it, ...parte } : it)));
  }

  // Ao escolher um item, sugere os associados (ex.: módulo Galileo -> chicote Galileo); tudo editável.
  function escolher(i: number, produtoId: number | "") {
    const novos = itens.map((it, k) => (k === i ? { ...it, produto_id: produtoId } : it));
    if (produtoId !== "" && sugerir) {
      const qtd = novos[i].quantidade || 1;
      for (const a of associados.filter((x) => x.produto_id === produtoId)) {
        if (!novos.some((it) => it.produto_id === a.associado_id)) {
          novos.push({ ...itemVazio(), produto_id: a.associado_id, quantidade: a.quantidade * qtd, auto: true });
        }
      }
    }
    onChange(novos);
  }

  // Marcar a caixa acrescenta os chicotes dos módulos já escolhidos; desmarcar tira os que foram sugeridos.
  function alternar(marcado: boolean) {
    setJunto(marcado);
    if (!marcado) return onChange(itens.filter((it) => !it.auto));
    const novos = [...itens];
    for (const it of itens) {
      if (it.produto_id === "") continue;
      for (const a of associados.filter((x) => x.produto_id === it.produto_id)) {
        if (!novos.some((n) => n.produto_id === a.associado_id)) {
          novos.push({ ...itemVazio(), produto_id: a.associado_id, quantidade: a.quantidade * (it.quantidade || 1), auto: true });
        }
      }
    }
    onChange(novos);
  }

  return (
    <div className="space-y-2">
      {chicote !== "nenhum" && (
        <label className="flex items-center gap-2 text-sm">
          <input type="checkbox" checked={junto} onChange={(e) => alternar(e.target.checked)} />
          {chicote === "sempre"
            ? "Dar entrada no chicote junto com o módulo (desmarque para entrar só o módulo)"
            : "Enviar chicote junto com o módulo (desmarque para enviar só o módulo)"}
        </label>
      )}
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

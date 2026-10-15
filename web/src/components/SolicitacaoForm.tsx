"use client";
import { useState } from "react";
import { useRouter } from "next/navigation";
import { supabaseBrowser } from "@/lib/supabase/client";
import { Busca } from "@/components/Busca";
import { ItensEditor, itemVazio, itensParaRpc } from "@/components/ItensEditor";
import { nomeUnidade, type Associado, type ItemForm, type Local, type Perfil, type Produto, type Unidade } from "@/lib/types";

// Quem pede e de onde sai:
//  - técnico: o pedido é para o estoque dele e sai do estoque base dele;
//  - agendamento: sai do estoque dele (fixo) para um técnico, com o cliente, do estoque livre ou do dedicado de um cliente;
//  - administrador e operador: estoque → técnico (cliente opcional) ou estoque → estoque, de qualquer origem.
export function SolicitacaoForm({ perfil, produtos, associados, unidades, locais = [], tecnicoBase, origemFixa }: {
  perfil: Perfil; produtos: Produto[]; associados: Associado[]; unidades: Unidade[]; locais?: Local[];
  tecnicoBase?: { nome: string } | null; origemFixa?: { id: number; nome: string } | null;
}) {
  const ehTecnico = perfil === "tecnico";
  const ehAgendamento = perfil === "agendamento";
  const [origem, setOrigem] = useState<number | "">("");
  const [destino, setDestino] = useState<number | "">("");
  const [cliente, setCliente] = useState<number | "">("");
  const router = useRouter();
  const [itens, setItens] = useState<ItemForm[]>([itemVazio()]);
  const [chamado, setChamado] = useState("");
  const [obs, setObs] = useState("");
  const [msg, setMsg] = useState<{ ok: boolean; texto: string } | null>(null);

  const destinoLocal = locais.find((l) => l.id === destino);
  const paraTecnico = ehAgendamento || destinoLocal?.tipo === "tecnico";
  // Para um técnico o item sai do estoque livre ou do dedicado de um cliente; entre estoques pode-se dedicar o item no destino.
  const reserva = ehTecnico || !paraTecnico ? "reservar" : "reservado";
  const nomeUn = new Map(unidades.map((u) => [u.id, nomeUnidade(u)]));
  const opcoesDestino = ehAgendamento ? locais.filter((l) => l.tipo === "tecnico") : locais.filter((l) => l.id !== origem);

  async function enviar(e: React.FormEvent) {
    e.preventDefault();
    const linhas = itensParaRpc(itens, associados).map((i) => ({
      produto_id: i.produto_id, quantidade: i.quantidade,
      reservar_para_unidade_id: reserva === "reservar" ? i.reservar_para_unidade_id : null,
      reservado_unidade_id: reserva === "reservado" ? i.reservado_unidade_id : null,
    }));
    // Alerta: item de estoque dedicado indo para um cliente diferente do dedicado.
    const diferentes = linhas.filter((l) => l.reservado_unidade_id && l.reservado_unidade_id !== cliente);
    if (diferentes.length) {
      const nomes = [...new Set(diferentes.map((l) => nomeUn.get(l.reservado_unidade_id as number)))].join(", ");
      const para = cliente ? nomeUn.get(cliente as number) : "nenhum cliente informado";
      if (!window.confirm(`Atenção: um item de estoque dedicado está sendo direcionado a um cliente diferente.\n\nDedicado de: ${nomes}\nSaída para: ${para}\n\nConfirmar mesmo assim?`)) return;
    }
    const { error } = await supabaseBrowser().rpc("criar_solicitacao", {
      p: { origem_id: ehAgendamento ? origemFixa?.id : origem, destino_id: destino, unidade_id: paraTecnico ? cliente : null, chamado_url: chamado, observacao: obs, itens: linhas },
    });
    if (error) return setMsg({ ok: false, texto: error.message });
    setMsg({ ok: true, texto: "Solicitação enviada." });
    setItens([itemVazio()]); setObs(""); setChamado("");
    router.refresh();
  }

  return (
    <form onSubmit={enviar} className="card space-y-3">
      <h2 className="font-medium">Nova solicitação</h2>
      {ehTecnico ? (
        <p className="text-sm text-slate-600">O pedido é para o seu estoque e sai de {tecnicoBase ? tecnicoBase.nome : "seu estoque base"}.</p>
      ) : (
        <div className="grid gap-3 sm:grid-cols-2">
          {ehAgendamento ? (
            <p className="text-sm text-slate-600 sm:col-span-2">
              {origemFixa ? <>Sai de <strong>{origemFixa.nome}</strong> (o seu estoque) para um técnico.</> : "Seu acesso ainda não tem um estoque definido. Fale com um administrador."}
            </p>
          ) : (
            <label className="text-sm">Sai de
              <select className="campo mt-1" value={origem} onChange={(e) => setOrigem(Number(e.target.value))} required>
                <option value="">Selecione</option>
                {locais.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
              </select>
            </label>
          )}
          <label className="text-sm">Vai para{ehAgendamento ? " (técnico)" : ""}
            <select className="campo mt-1" value={destino} onChange={(e) => { setDestino(Number(e.target.value)); setItens(itens.map((i) => ({ ...i, reservado_unidade_id: "", reservar_para_unidade_id: "" }))); }} required>
              <option value="">Selecione</option>
              {opcoesDestino.map((l) => <option key={l.id} value={l.id}>{l.nome}</option>)}
            </select>
          </label>
          {paraTecnico && (
            <div className="text-sm">Cliente{ehAgendamento ? "" : " (opcional)"}
              <Busca required={ehAgendamento} vazio={ehAgendamento ? undefined : "Sem cliente"} placeholder="Digite para buscar o cliente" value={cliente} onChange={setCliente}
                opcoes={unidades.map((u) => ({ value: u.id, label: nomeUn.get(u.id) as string }))} />
            </div>
          )}
        </div>
      )}
      <ItensEditor itens={itens} onChange={setItens} produtos={produtos} associados={associados} unidades={unidades} reserva={reserva} chicote="sim" chip="nenhum" />
      <label className="block text-sm">Link do chamado no Jira (opcional)
        <input className="campo mt-1" value={chamado} onChange={(e) => setChamado(e.target.value)} placeholder="https://.../browse/HW-5698" />
      </label>
      <label className="block text-sm">Observação
        <textarea className="campo mt-1" rows={2} value={obs} onChange={(e) => setObs(e.target.value)} />
      </label>
      {msg && <p className={`text-sm ${msg.ok ? "text-green-700" : "text-marca-700"}`}>{msg.texto}</p>}
      <button className="btn">Enviar solicitação</button>
    </form>
  );
}

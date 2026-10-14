-- Migração 0008: o sistema deixa de separar itens novos e usados. O saldo é uma contagem única por item.
-- O que já estava registrado como "usado" passa a contar como "novo" (some na soma). A coluna continua
-- existindo, sempre "novo", para não mexer nas views e funções.
update movimentacao_item set condicao = 'novo' where condicao <> 'novo';

create or replace function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare it jsonb;
begin
  if p_itens is null or jsonb_typeof(p_itens) <> 'array' or jsonb_array_length(p_itens) = 0 then
    raise exception 'Informe ao menos um item';
  end if;
  for it in select * from jsonb_array_elements(p_itens) loop
    insert into movimentacao_item (movimentacao_id, produto_id, condicao, quantidade, reservado_unidade_id,
                                   reservar_para_unidade_id)
    values (p_mov,
            (it->>'produto_id')::int,
            'novo',
            (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

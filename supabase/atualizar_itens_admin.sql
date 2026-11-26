-- Itens (produto) no Cadastros: o administrador inclui, edita e exclui.
-- Incluir/editar: direto na tabela produto (RLS produto_admin). Nome único sem diferenciar maiúsculas.
-- Excluir: excluir_item(p_id) apaga só item sem uso; com movimentação, solicitação, pedido ou sendo componente
-- do kit de outro item, desativa (ativo = false). Retorna 'excluido' ou 'desativado'.
-- Rode uma vez depois de atualizar_kits.sql. Idempotente.
begin;

do $$ declare v text; begin
  select string_agg(n, ', ') into v from (select lower(nome) n from produto group by 1 having count(*) > 1) d;
  if v is not null then raise exception 'Há itens com o mesmo nome (maiúsculas à parte): %. Renomeie antes.', v; end if;
end $$;
create unique index if not exists produto_nome_unico_ci on produto (lower(nome));

create or replace function public.excluir_item(p_id integer) returns text
language plpgsql security definer set search_path = public as $$
declare v_nome text;
begin
  if fn_perfil() is distinct from 'admin' then
    raise exception 'Só o administrador exclui itens' using errcode = '42501';
  end if;
  select nome into v_nome from produto where id = p_id;
  if v_nome is null then raise exception 'Item não encontrado'; end if;

  if not exists (select 1 from item_associado where associado_id = p_id) then
    begin
      delete from item_associado where produto_id = p_id;   -- o kit do próprio item
      delete from produto where id = p_id;
      return 'excluido';
    exception when foreign_key_violation then
      null;  -- tem histórico (movimentação, saldo, solicitação, pedido): desativa abaixo
    end;
  end if;

  update produto set ativo = false where id = p_id;
  raise notice '% tem histórico ou faz parte do kit de outro item: foi desativado, não excluído', v_nome;
  return 'desativado';
end $$;

revoke execute on function public.excluir_item(integer) from public, anon;
grant execute on function public.excluir_item(integer) to authenticated;

commit;

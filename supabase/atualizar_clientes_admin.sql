-- Clientes e unidades no Cadastros: o administrador renomeia, move unidade de cliente e exclui.
-- Renomear/mover: update direto (RLS cliente_admin / unidade_admin). Nome único sem diferenciar maiúsculas
-- (cliente no geral; unidade dentro do mesmo cliente).
-- Excluir: excluir_cliente(p_id) / excluir_unidade(p_id) apagam só o que não tem uso; com movimentação,
-- solicitação, dedicado ou reserva, desativam (ativo = false). O cliente vai sempre junto com as unidades.
-- Retornam 'excluido' ou 'desativado'. Rode uma vez depois de atualizar_itens_admin.sql. Idempotente.
begin;

alter table cliente         add column if not exists ativo boolean not null default true;
alter table unidade_cliente add column if not exists ativo boolean not null default true;

do $$ declare v text; begin
  select string_agg(n, ', ') into v from (select lower(nome) n from cliente group by 1 having count(*) > 1) d;
  if v is not null then raise exception 'Há clientes com o mesmo nome (maiúsculas à parte): %. Renomeie antes.', v; end if;
  select string_agg(n, ', ') into v from (select lower(nome) n from unidade_cliente group by cliente_id, 1 having count(*) > 1) d;
  if v is not null then raise exception 'Há unidades repetidas no mesmo cliente (maiúsculas à parte): %. Renomeie antes.', v; end if;
end $$;
create unique index if not exists cliente_nome_unico_ci on cliente (lower(nome));
create unique index if not exists unidade_nome_unico_ci on unidade_cliente (cliente_id, lower(nome));

create or replace function public.excluir_unidade(p_id integer) returns text
language plpgsql security definer set search_path = public as $$
begin
  if fn_perfil() is distinct from 'admin' then
    raise exception 'Só o administrador exclui unidades' using errcode = '42501';
  end if;
  if not exists (select 1 from unidade_cliente where id = p_id) then raise exception 'Unidade não encontrada'; end if;
  begin
    delete from unidade_cliente where id = p_id;
    return 'excluido';
  exception when foreign_key_violation then
    null;  -- tem movimentação, solicitação, dedicado ou reserva
  end;
  update unidade_cliente set ativo = false where id = p_id;
  return 'desativado';
end $$;

create or replace function public.excluir_cliente(p_id integer) returns text
language plpgsql security definer set search_path = public as $$
begin
  if fn_perfil() is distinct from 'admin' then
    raise exception 'Só o administrador exclui clientes' using errcode = '42501';
  end if;
  if not exists (select 1 from cliente where id = p_id) then raise exception 'Cliente não encontrado'; end if;
  begin
    delete from unidade_cliente where cliente_id = p_id;
    delete from cliente where id = p_id;
    return 'excluido';
  exception when foreign_key_violation then
    null;  -- alguma unidade tem histórico: nada é apagado
  end;
  update unidade_cliente set ativo = false where cliente_id = p_id;
  update cliente set ativo = false where id = p_id;
  return 'desativado';
end $$;

revoke execute on function public.excluir_cliente(integer), public.excluir_unidade(integer) from public, anon;
grant execute on function public.excluir_cliente(integer), public.excluir_unidade(integer) to authenticated;

commit;

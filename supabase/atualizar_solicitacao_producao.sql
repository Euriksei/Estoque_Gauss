-- Atualização: solicitação aceita vai para "em produção" (prazo de 1 dia).
-- Rode UMA vez no SQL Editor do Supabase, em um banco que já tem o banco_completo.sql anterior.
-- (Quem criar o banco do zero com o banco_completo.sql atual não precisa deste arquivo.)
alter type status_solicitacao add value if not exists 'em_producao' before 'atendida';
alter table solicitacao add column if not exists prazo_producao timestamptz;

create or replace function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_mov bigint; v_itens jsonb;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador atendem solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação já encerrada'; end if;
  if s.origem_id is null or s.destino_id is null then raise exception 'Pedido sem origem ou destino'; end if;
  select jsonb_agg(jsonb_build_object('produto_id', produto_id, 'quantidade', quantidade,
                                      'reservar_para_unidade_id', reservar_para_unidade_id))
    into v_itens from solicitacao_item where solicitacao_id = p_id;
  v_mov := criar_transferencia(p || jsonb_build_object('origem_id', s.origem_id, 'destino_id', s.destino_id, 'itens', v_itens));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

create or replace function public.cancelar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found or s.status::text not in ('aberta','em_producao') then raise exception 'Solicitação não está em andamento'; end if;
  if s.status::text = 'em_producao' and fn_perfil()::text not in ('admin','operador') then
    raise exception 'Depois de aceita, só administrador e operador cancelam' using errcode = '42501';
  end if;
  if s.tecnico_id <> auth.uid() and fn_perfil() not in ('admin','operador') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  update solicitacao set status = 'cancelada' where id = p_id;
end $$;

create or replace function public.aceitar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao;
begin
  if fn_perfil()::text not in ('admin','operador') then
    raise exception 'Só administrador e operador aceitam solicitações' using errcode = '42501';
  end if;
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status::text <> 'aberta' then raise exception 'Só dá para aceitar solicitação aberta'; end if;
  update solicitacao set status = 'em_producao', prazo_producao = now() + interval '1 day' where id = p_id;
end $$;
revoke execute on function public.aceitar_solicitacao(bigint) from public, anon;
grant execute on function public.aceitar_solicitacao(bigint) to authenticated;

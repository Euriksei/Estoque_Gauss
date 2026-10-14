-- Migração 0002: acesso por perfil (RLS), cadastro automático de usuário, auditoria e
-- as funções que fazem todas as escritas de estoque (o app nunca grava direto nas tabelas de movimentação).

-- ---------------------------------------------------------------- usuários novos
-- Quem se cadastra entra como "consulta" e inativo até um administrador liberar o perfil.
create function public.fn_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into usuario (id, nome, email, perfil, ativo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)),
          new.email, 'consulta', false);
  return new;
end $$;

create trigger trg_novo_usuario after insert on auth.users
  for each row execute function public.fn_novo_usuario();

-- ---------------------------------------------------------------- permissões
create function public.fn_pode_operar_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()
      when 'admin'    then true
      when 'operador' then exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local)
      when 'tecnico'  then exists (select 1 from local l where l.id = p_local and l.tecnico_id = auth.uid())
    end, false)
$$;

-- ---------------------------------------------------------------- RLS
alter table usuario            enable row level security;
alter table local              enable row level security;
alter table usuario_local      enable row level security;
alter table categoria          enable row level security;
alter table fornecedor         enable row level security;
alter table produto            enable row level security;
alter table item_associado     enable row level security;
alter table cliente            enable row level security;
alter table unidade_cliente    enable row level security;
alter table movimentacao       enable row level security;
alter table movimentacao_item  enable row level security;
alter table solicitacao        enable row level security;
alter table solicitacao_item   enable row level security;
alter table pedido_compra      enable row level security;
alter table auditoria          enable row level security;

-- Usuários: cada um vê a si mesmo; administrador, operador e consulta veem todos; só o administrador altera.
create policy usuario_ler on usuario for select using (
  id = auth.uid() or fn_perfil() in ('admin','operador','consulta'));
create policy usuario_admin on usuario for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

create policy usuario_local_ler on usuario_local for select using (
  usuario_id = auth.uid() or fn_perfil() in ('admin','consulta'));
create policy usuario_local_admin on usuario_local for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

-- Locais, catálogo e clientes: qualquer usuário ativo lê; só o administrador altera.
-- (Os nomes dos locais são visíveis a todos; as QUANTIDADES só aparecem para quem pode ver o local.)
create policy local_ler on local for select using (fn_perfil() is not null);
create policy local_admin on local for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

create policy categoria_ler on categoria for select using (fn_perfil() is not null);
create policy categoria_admin on categoria for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy fornecedor_ler on fornecedor for select using (fn_perfil() is not null);
create policy fornecedor_admin on fornecedor for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy produto_ler on produto for select using (fn_perfil() is not null);
create policy produto_admin on produto for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy item_associado_ler on item_associado for select using (fn_perfil() is not null);
create policy item_associado_admin on item_associado for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy cliente_ler on cliente for select using (fn_perfil() is not null);
create policy cliente_admin on cliente for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');
create policy unidade_ler on unidade_cliente for select using (fn_perfil() is not null);
create policy unidade_admin on unidade_cliente for all using (fn_perfil() = 'admin') with check (fn_perfil() = 'admin');

-- Movimentações: só leitura direta; vê quem pode ver o local de origem ou de destino.
create policy mov_ler on movimentacao for select using (
  (local_origem_id  is not null and fn_pode_ver_local(local_origem_id))
  or (local_destino_id is not null and fn_pode_ver_local(local_destino_id)));
create policy mov_item_ler on movimentacao_item for select using (
  exists (select 1 from movimentacao m where m.id = movimentacao_id));

-- Solicitações: o técnico vê as próprias; administrador, operador e consulta veem todas.
create policy sol_ler on solicitacao for select using (
  tecnico_id = auth.uid() or fn_perfil() in ('admin','operador','consulta'));
create policy sol_item_ler on solicitacao_item for select using (
  exists (select 1 from solicitacao s where s.id = solicitacao_id));

-- Pedidos de compra: técnico não vê; administrador e operador gerenciam.
create policy pedido_ler on pedido_compra for select using (fn_perfil() in ('admin','operador','consulta'));
create policy pedido_escrever on pedido_compra for all
  using (fn_perfil() in ('admin','operador')) with check (fn_perfil() in ('admin','operador'));

create policy auditoria_ler on auditoria for select using (fn_perfil() = 'admin');

-- ---------------------------------------------------------------- auditoria dos cadastros
create function public.fn_auditar() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into auditoria (usuario_id, tabela, registro_id, acao, antes, depois)
  values (auth.uid(), tg_table_name,
          coalesce((to_jsonb(new)->>'id'), (to_jsonb(old)->>'id')),
          tg_op,
          case when tg_op in ('UPDATE','DELETE') then to_jsonb(old) end,
          case when tg_op in ('INSERT','UPDATE') then to_jsonb(new) end);
  return coalesce(new, old);
end $$;

create trigger aud_usuario        after insert or update or delete on usuario        for each row execute function fn_auditar();
create trigger aud_local          after insert or update or delete on local          for each row execute function fn_auditar();
create trigger aud_produto        after insert or update or delete on produto        for each row execute function fn_auditar();
create trigger aud_cliente        after insert or update or delete on cliente        for each row execute function fn_auditar();
create trigger aud_unidade        after insert or update or delete on unidade_cliente for each row execute function fn_auditar();
create trigger aud_pedido_compra  after insert or update or delete on pedido_compra  for each row execute function fn_auditar();

-- ---------------------------------------------------------------- saldo nunca negativo
-- Chamada depois de cada escrita, dentro da mesma transação: se algum saldo ficou negativo, desfaz tudo.
create function public.fn_verificar_saldo(p_locais integer[]) returns void
language plpgsql security definer set search_path = public as $$
declare r record;
begin
  for r in
    select e.local_id, e.produto_id, e.condicao, e.reservado_unidade_id, sum(e.delta) as q
      from efeito_estoque e
     where e.local_id = any (p_locais)
     group by 1,2,3,4
    having sum(e.delta) < 0
     limit 1
  loop
    raise exception 'Saldo insuficiente: % (%), local %, quantidade faltando %',
      (select nome from produto where id = r.produto_id), r.condicao,
      (select nome from local where id = r.local_id), -r.q
      using errcode = 'P0001';
  end loop;
end $$;

-- Trava por local para duas pessoas não gastarem o mesmo saldo ao mesmo tempo.
create function public.fn_travar_locais(p_locais integer[]) returns void
language plpgsql security definer set search_path = public as $$
declare l integer;
begin
  for l in select distinct x from unnest(p_locais) x where x is not null order by x loop
    perform pg_advisory_xact_lock(l);
  end loop;
end $$;

create function public.fn_gravar_itens(p_mov bigint, p_itens jsonb) returns void
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
            coalesce(it->>'condicao', 'novo')::condicao_item,
            (it->>'quantidade')::int,
            nullif(it->>'reservado_unidade_id','')::int,
            nullif(it->>'reservar_para_unidade_id','')::int);
  end loop;
end $$;

-- ---------------------------------------------------------------- registrar movimentação simples
-- p: {tipo, data, local_id, unidade_id, fornecedor_id, numero_nf, finalidade, chamado_url, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id}]}
create function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_ajuste_pos boolean;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  -- O técnico só dá baixa de saída para cliente no próprio estoque/carro.
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, criado_por)
  values (v_tipo, 'registrado', coalesce((p->>'data')::date, current_date),
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), auth.uid())
  returning id into v_id;

  -- Ajuste: quantidade positiva soma no local, negativa subtrai.
  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'reservar_para_unidade_id só vale em transferência';
  end if;

  -- Entradas e saídas aceitam só quantidade positiva; ajuste aceita sinal.
  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  -- Reserva só faz sentido para o cliente dedicado: a saída deve ser para a mesma unidade.
  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  return v_id;
end $$;

-- ---------------------------------------------------------------- transferência em duas etapas
-- p: {origem_id, destino_id, data, modo_envio, codigo_rastreio, prazo_chegada, observacao,
--     itens:[{produto_id, condicao, quantidade, reservado_unidade_id, reservar_para_unidade_id}]}
create function public.criar_transferencia(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_origem  integer := (p->>'origem_id')::int;
  v_destino integer := (p->>'destino_id')::int;
  v_id bigint;
begin
  if fn_perfil() is null or fn_perfil() = 'consulta' then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if v_origem is null or v_destino is null or v_origem = v_destino then
    raise exception 'Informe origem e destino diferentes';
  end if;
  -- Só o dono do local de origem inicia o envio.
  if not fn_pode_operar_local(v_origem) then
    raise exception 'Sem permissão para enviar deste local' using errcode = '42501';
  end if;
  if fn_perfil() = 'tecnico' then
    raise exception 'Técnico não cria transferência; use solicitação' using errcode = '42501';
  end if;

  perform fn_travar_locais(array[v_origem, v_destino]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, modo_envio, codigo_rastreio,
                            prazo_chegada, observacao, criado_por)
  values ('TRANSFERENCIA', 'em_transito', coalesce((p->>'data')::date, current_date), v_origem, v_destino,
          nullif(p->>'modo_envio','')::modo_envio, nullif(p->>'codigo_rastreio',''),
          nullif(p->>'prazo_chegada','')::date, nullif(p->>'observacao',''), auth.uid())
  returning id into v_id;

  perform fn_gravar_itens(v_id, p->'itens');
  if exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  perform fn_verificar_saldo(array[v_origem]);
  return v_id;
end $$;

-- Quem recebe confirma; só então o saldo entra no estoque dele (o técnico confirma o que chega ao carro).
create function public.confirmar_recebimento(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao;
begin
  select * into m from movimentacao where id = p_id for update;
  if not found or m.tipo <> 'TRANSFERENCIA' then raise exception 'Transferência não encontrada'; end if;
  if m.status <> 'em_transito' then raise exception 'Esta transferência não está em trânsito'; end if;
  if not fn_pode_operar_local(m.local_destino_id) then
    raise exception 'Só quem recebe pode confirmar' using errcode = '42501';
  end if;
  update movimentacao set status = 'recebido', recebido_em = now(), recebido_por = auth.uid() where id = p_id;
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'RECEBIMENTO', jsonb_build_object('status', 'recebido'));
end $$;

-- Cancela um envio ainda em trânsito (o saldo volta para a origem). Quem enviou ou o administrador.
create function public.cancelar_transferencia(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao;
begin
  select * into m from movimentacao where id = p_id for update;
  if not found or m.tipo <> 'TRANSFERENCIA' then raise exception 'Transferência não encontrada'; end if;
  if m.status <> 'em_transito' then raise exception 'Só dá para cancelar o que está em trânsito'; end if;
  if not fn_pode_operar_local(m.local_origem_id) then
    raise exception 'Só quem enviou pode cancelar' using errcode = '42501';
  end if;
  update movimentacao set status = 'cancelado',
         observacao = concat_ws(E'\n', observacao, 'Cancelada: ' || coalesce(p_motivo, '')) where id = p_id;
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'CANCELAMENTO', jsonb_build_object('motivo', p_motivo));
end $$;

-- Estorno de movimentação registrada: só administrador. Marca como cancelada (nada é apagado) e
-- confere que nenhum saldo fica negativo por causa disso.
create function public.estornar_movimentacao(p_id bigint, p_motivo text) returns void
language plpgsql security definer set search_path = public as $$
declare m movimentacao;
begin
  if fn_perfil() <> 'admin' then raise exception 'Só administrador estorna' using errcode = '42501'; end if;
  if nullif(p_motivo,'') is null then raise exception 'Informe o motivo'; end if;
  select * into m from movimentacao where id = p_id for update;
  if not found then raise exception 'Movimentação não encontrada'; end if;
  if m.tipo = 'TRANSFERENCIA' and m.status = 'em_transito' then
    raise exception 'Use cancelar_transferencia para o que está em trânsito';
  end if;
  if m.status not in ('registrado','recebido') then raise exception 'Movimentação já cancelada'; end if;
  perform fn_travar_locais(array[m.local_origem_id, m.local_destino_id]);
  update movimentacao set status = 'cancelado',
         observacao = concat_ws(E'\n', observacao, 'Estornada: ' || p_motivo) where id = p_id;
  perform fn_verificar_saldo(array[m.local_origem_id, m.local_destino_id]);
  insert into auditoria (usuario_id, tabela, registro_id, acao, antes, depois)
  values (auth.uid(), 'movimentacao', p_id::text, 'ESTORNO', jsonb_build_object('status', m.status),
          jsonb_build_object('motivo', p_motivo));
end $$;

-- ---------------------------------------------------------------- solicitações do técnico
-- p: {chamado_url, observacao, itens:[{produto_id, quantidade}]}
create function public.criar_solicitacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb;
begin
  if fn_perfil() not in ('admin','operador','tecnico') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p->'itens' is null or jsonb_array_length(p->'itens') = 0 then raise exception 'Informe ao menos um item'; end if;
  insert into solicitacao (tecnico_id, chamado_url, observacao)
  values (auth.uid(), nullif(p->>'chamado_url',''), nullif(p->>'observacao','')) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade)
    values (v_id, (it->>'produto_id')::int, (it->>'quantidade')::int);
  end loop;
  return v_id;
end $$;

-- O operador atende gerando a transferência do estoque base para o carro do técnico.
-- p tem os mesmos campos de criar_transferencia (origem_id, modo_envio, itens...); o destino é o carro do técnico.
create function public.atender_solicitacao(p_id bigint, p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare s solicitacao; v_destino integer; v_mov bigint;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found then raise exception 'Solicitação não encontrada'; end if;
  if s.status <> 'aberta' then raise exception 'Solicitação já encerrada'; end if;
  select id into v_destino from local where tecnico_id = s.tecnico_id;
  if v_destino is null then raise exception 'Técnico sem estoque/carro cadastrado'; end if;
  v_mov := criar_transferencia(p || jsonb_build_object('destino_id', v_destino));
  update solicitacao set status = 'atendida', movimentacao_id = v_mov where id = p_id;
  return v_mov;
end $$;

create function public.cancelar_solicitacao(p_id bigint) returns void
language plpgsql security definer set search_path = public as $$
declare s solicitacao;
begin
  select * into s from solicitacao where id = p_id for update;
  if not found or s.status <> 'aberta' then raise exception 'Solicitação não está aberta'; end if;
  if s.tecnico_id <> auth.uid() and fn_perfil() not in ('admin','operador') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  update solicitacao set status = 'cancelada' where id = p_id;
end $$;

-- ---------------------------------------------------------------- grants
-- O app só escreve em movimentações/solicitações pelas funções acima.
revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant insert, update, delete on usuario, usuario_local, local, categoria, fornecedor, produto, item_associado,
      cliente, unidade_cliente, pedido_compra to authenticated;   -- limitado pelas políticas acima
grant usage on all sequences in schema public to authenticated;

revoke execute on all functions in schema public from public, anon;
grant execute on function
  fn_perfil(), fn_pode_ver_local(integer), fn_pode_operar_local(integer),
  registrar_movimentacao(jsonb), criar_transferencia(jsonb), confirmar_recebimento(bigint),
  cancelar_transferencia(bigint, text), estornar_movimentacao(bigint, text),
  criar_solicitacao(jsonb), atender_solicitacao(bigint, jsonb), cancelar_solicitacao(bigint)
  to authenticated;

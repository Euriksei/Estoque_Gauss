-- Atualização: "Ver como" do administrador.
-- Rode uma vez, depois de atualizar_fluxo_pedidos.sql. Pode rodar de novo sem problema.
-- O administrador escolhe ver o sistema como operador (de um estoque fixo), agendamento (com um estoque
-- fixo), consulta ou um técnico. Não é só visual: fn_perfil(), as regras de local (fn_pode_ver_local,
-- fn_pode_operar_local), o técnico ligado ao login, a segurança por linha (RLS) e todas as funções passam a
-- usar o perfil e o local escolhidos.
--  * Só quem é administrador DE VERDADE (na tabela usuario) ativa; para os outros perfis nada muda.
--  * O administrador sempre consegue voltar: definir_visualizacao com perfil nulo olha o perfil real.
--  * A tabela usuario não muda (continua perfil admin). Auditoria e "criado por" continuam com o usuário real.
-- Tudo roda numa transação só: se der erro, nada é gravado.

begin;

-- ---------------------------------------------------------------- 1. Onde fica a simulação
create table if not exists visualizacao (
  usuario_id    uuid primary key references usuario(id),
  perfil        perfil_acesso not null check (perfil::text <> 'admin'),
  local_id      integer references local(id),
  tecnico_id    integer references tecnico(id),
  atualizado_em timestamptz not null default now()
);
alter table visualizacao enable row level security;
drop policy if exists visualizacao_ler on visualizacao;
create policy visualizacao_ler on visualizacao for select using (usuario_id = auth.uid());
revoke all on visualizacao from public, anon, authenticated;
grant select on visualizacao to authenticated;

-- ---------------------------------------------------------------- 2. Perfil real e perfil efetivo
-- Perfil gravado na tabela usuario (sem simulação).
create or replace function public.fn_perfil_real() returns perfil_acesso
language sql stable security definer set search_path = public as $$
  select perfil from usuario where id = auth.uid() and ativo
$$;

-- Perfil efetivo: o simulado, se o usuário for administrador de verdade e estiver simulando; senão, o real.
create or replace function public.fn_perfil() returns perfil_acesso
language sql stable security definer set search_path = public as $$
  select case when r.perfil = 'admin'
              then coalesce((select v.perfil from visualizacao v where v.usuario_id = auth.uid()), r.perfil)
              else r.perfil end
    from (select fn_perfil_real() as perfil) r
$$;

-- A simulação vale (administrador real com uma linha em visualizacao)?
create or replace function public.fn_simulacao() returns visualizacao
language sql stable security definer set search_path = public as $$
  select v.* from visualizacao v where v.usuario_id = auth.uid() and fn_perfil_real() = 'admin'
$$;

-- Técnico do login (tecnico.usuario_id) ou o técnico simulado.
create or replace function public.fn_tecnico_atual() returns integer
language sql stable security definer set search_path = public as $$
  select case when (fn_simulacao()).usuario_id is not null then (fn_simulacao()).tecnico_id
              else (select t.id from tecnico t where t.usuario_id = auth.uid() order by t.id limit 1) end
$$;

-- O local está entre os estoques do usuário (usuario_local) ou é o estoque simulado?
create or replace function public.fn_local_do_usuario(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select case when (fn_simulacao()).usuario_id is not null then (fn_simulacao()).local_id is not distinct from p_local
              else exists (select 1 from usuario_local ul where ul.usuario_id = auth.uid() and ul.local_id = p_local) end
$$;

-- ---------------------------------------------------------------- 3. Regras de local com o perfil efetivo
create or replace function public.fn_pode_ver_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()::text
      when 'admin'       then true
      when 'consulta'    then true
      when 'agendamento' then true
      when 'operador'    then fn_local_do_usuario(p_local)
      when 'tecnico'     then exists (select 1 from local l where l.id = p_local and l.tecnico_id = fn_tecnico_atual())
    end, false)
$$;

create or replace function public.fn_pode_operar_local(p_local integer) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    case fn_perfil()::text
      when 'admin'    then true
      when 'operador' then fn_local_do_usuario(p_local)
      when 'tecnico'  then exists (select 1 from local l where l.id = p_local and l.tecnico_id = fn_tecnico_atual())
    end, false)
$$;

-- ---------------------------------------------------------------- 4. registrar_movimentacao: técnico do login ou o simulado
create or replace function public.registrar_movimentacao(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare
  v_tipo tipo_movimento := (p->>'tipo')::tipo_movimento;
  v_local integer := (p->>'local_id')::int;
  v_perfil perfil_acesso := fn_perfil();
  v_id bigint;
  v_entrada boolean := v_tipo in ('ENTRADA_COMPRA','DEVOLUCAO_CLIENTE');
  v_modo modo_envio := nullif(p->>'modo_envio','')::modo_envio;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
  v_data date;
begin
  if v_perfil is null then raise exception 'Usuário sem acesso' using errcode = '42501'; end if;
  if v_tipo = 'TRANSFERENCIA' then raise exception 'Use criar_transferencia' ; end if;
  if v_local is null then raise exception 'Informe o local'; end if;
  if not fn_pode_operar_local(v_local) then
    raise exception 'Sem permissão para movimentar este local' using errcode = '42501';
  end if;
  if v_perfil = 'tecnico' and v_tipo <> 'SAIDA_CLIENTE' then
    raise exception 'Técnico só pode registrar saída para cliente' using errcode = '42501';
  end if;
  if v_tipo in ('SAIDA_CLIENTE','DEVOLUCAO_CLIENTE') and nullif(p->>'unidade_id','') is null then
    raise exception 'Informe o cliente/unidade';
  end if;
  if v_tipo = 'AJUSTE' and nullif(p->>'observacao','') is null then
    raise exception 'Ajuste exige justificativa';
  end if;
  v_data := fn_data_movimento(p->>'data');

  if v_tipo = 'SAIDA_CLIENTE' then
    if v_perfil = 'tecnico' then
      v_modo := 'tecnico';
      v_tec := fn_tecnico_atual();   -- o técnico do login (ou o simulado pelo administrador)
    end if;
    if v_modo is null then raise exception 'Informe o modo de envio'; end if;
    if v_modo = 'sedex' then raise exception 'Sedex não é mais um meio de envio: use Correios'; end if;
    if v_modo = 'tecnico' and v_tec is null then raise exception 'Informe o técnico que leva o material'; end if;
    if v_modo <> 'tecnico' then v_tec := null; end if;
  else
    v_modo := null; v_tec := null;
  end if;

  perform fn_travar_locais(array[v_local]);

  insert into movimentacao (tipo, status, data, local_origem_id, local_destino_id, unidade_id, fornecedor_id,
                            numero_nf, finalidade, chamado_url, observacao, modo_envio, codigo_rastreio, tecnico_id,
                            criado_por)
  values (v_tipo, 'registrado', v_data,
          case when v_entrada then null else v_local end,
          case when v_entrada then v_local else null end,
          nullif(p->>'unidade_id','')::int, nullif(p->>'fornecedor_id','')::int,
          nullif(p->>'numero_nf',''), nullif(p->>'finalidade','')::finalidade,
          nullif(p->>'chamado_url',''), nullif(p->>'observacao',''), v_modo,
          case when v_tipo = 'SAIDA_CLIENTE' then nullif(p->>'codigo_rastreio','') end, v_tec,
          auth.uid())
  returning id into v_id;

  if v_tipo = 'AJUSTE' then
    update movimentacao set local_destino_id = v_local, local_origem_id = null where id = v_id;
  end if;

  perform fn_gravar_itens(v_id, p->'itens');

  -- Dedicado nasce por devolução de cliente, ajuste ou recebimento de transferência ("Dedicado para").
  if v_tipo not in ('DEVOLUCAO_CLIENTE','AJUSTE')
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservar_para_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;
  -- Na compra, item que já sai de um dedicado também não faz sentido (criaria dedicado na entrada).
  if v_tipo = 'ENTRADA_COMPRA'
     and exists (select 1 from movimentacao_item where movimentacao_id = v_id and reservado_unidade_id is not null) then
    raise exception 'Item dedicado só nasce por devolução de cliente, ajuste de inventário ou transferência';
  end if;

  if v_tipo <> 'AJUSTE' and exists (select 1 from movimentacao_item where movimentacao_id = v_id and quantidade <= 0) then
    raise exception 'Quantidade deve ser maior que zero';
  end if;

  if v_tipo = 'SAIDA_CLIENTE' and exists (
       select 1 from movimentacao_item i join movimentacao m on m.id = i.movimentacao_id
        where i.movimentacao_id = v_id and i.reservado_unidade_id is not null
          and i.reservado_unidade_id is distinct from m.unidade_id) then
    raise exception 'Item reservado só pode sair para a unidade reservada';
  end if;

  perform fn_verificar_saldo(array[v_local]);
  perform fn_verificar_dedicado_inteiro(v_id);
  return v_id;
end $$;

-- ---------------------------------------------------------------- 5. Ativar e voltar
-- p: {perfil: null|'admin'|'operador'|'tecnico'|'consulta'|'agendamento', local_id, tecnico_id}
--   operador e agendamento: local_id (estoque fixo) obrigatório; consulta: local_id opcional (só informativo);
--   tecnico: tecnico_id (tecnico.id) obrigatório e com estoque (carro); o local passa a ser a base dele.
--   perfil nulo ou 'admin': volta a administrador.
create or replace function public.definir_visualizacao(p jsonb) returns void
language plpgsql security definer set search_path = public as $$
declare
  v_perfil text := nullif(btrim(coalesce(p->>'perfil','')), '');
  v_local integer := nullif(p->>'local_id','')::int;
  v_tec integer := nullif(p->>'tecnico_id','')::int;
begin
  if fn_perfil_real() is distinct from 'admin' then
    raise exception 'Só o administrador pode ver como outro perfil' using errcode = '42501';
  end if;

  if v_perfil is null or v_perfil = 'admin' then
    delete from visualizacao where usuario_id = auth.uid();
    insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
    values (auth.uid(), 'visualizacao', auth.uid()::text, 'VER_COMO', jsonb_build_object('perfil', 'admin'));
    return;
  end if;

  if v_perfil not in ('operador','tecnico','consulta','agendamento') then
    raise exception 'Perfil inválido: use operador, tecnico, consulta ou agendamento';
  end if;
  if v_perfil in ('operador','agendamento') then
    if v_local is null or not exists (select 1 from local where id = v_local and tipo = 'estoque') then
      raise exception 'Escolha o estoque fixo (por exemplo, Nova Lima ou SBC)';
    end if;
    v_tec := null;
  elsif v_perfil = 'tecnico' then
    if v_tec is null or not exists (select 1 from tecnico where id = v_tec) then raise exception 'Escolha o técnico'; end if;
    if not exists (select 1 from local where tecnico_id = v_tec) then
      raise exception 'Este técnico não tem estoque (carro) cadastrado';
    end if;
    select l.base_id into v_local from local l where l.tecnico_id = v_tec order by l.id limit 1;
  else  -- consulta
    if v_local is not null and not exists (select 1 from local where id = v_local and tipo = 'estoque') then
      raise exception 'Escolha um estoque fixo';
    end if;
    v_tec := null;
  end if;

  insert into visualizacao (usuario_id, perfil, local_id, tecnico_id, atualizado_em)
  values (auth.uid(), v_perfil::perfil_acesso, v_local, v_tec, now())
  on conflict (usuario_id) do update
    set perfil = excluded.perfil, local_id = excluded.local_id, tecnico_id = excluded.tecnico_id, atualizado_em = now();
  insert into auditoria (usuario_id, tabela, registro_id, acao, depois)
  values (auth.uid(), 'visualizacao', auth.uid()::text, 'VER_COMO',
          jsonb_build_object('perfil', v_perfil, 'local_id', v_local, 'tecnico_id', v_tec));
end $$;

-- ---------------------------------------------------------------- 6. Para a tela: quem sou e como estou vendo
create or replace view minha_visualizacao with (security_invoker = true) as
select u.id as usuario_id,
       u.perfil::text as perfil_real,
       fn_perfil()::text as perfil,
       (u.perfil = 'admin' and u.ativo and v.usuario_id is not null) as simulando,
       case when u.perfil = 'admin' and u.ativo then v.local_id end as local_id,
       case when u.perfil = 'admin' and u.ativo then l.nome end as local_nome,
       case when u.perfil = 'admin' and u.ativo then v.tecnico_id end as tecnico_id,
       case when u.perfil = 'admin' and u.ativo then t.nome end as tecnico_nome,
       array(select x.id from local x where fn_pode_operar_local(x.id) order by x.id) as locais_operaveis
  from usuario u
  left join visualizacao v on v.usuario_id = u.id
  left join local l on l.id = v.local_id
  left join tecnico t on t.id = v.tecnico_id
 where u.id = auth.uid();
revoke all on minha_visualizacao from public, anon, authenticated;
grant select on minha_visualizacao to authenticated;

-- ---------------------------------------------------------------- 7. Permissões
revoke execute on function public.fn_perfil_real(), public.fn_simulacao(), public.fn_tecnico_atual(),
  public.fn_local_do_usuario(integer) from public, anon, authenticated;
revoke execute on function public.definir_visualizacao(jsonb), public.fn_perfil(), public.fn_pode_ver_local(integer),
  public.fn_pode_operar_local(integer), public.registrar_movimentacao(jsonb) from public, anon;
grant execute on function public.definir_visualizacao(jsonb), public.fn_perfil(), public.fn_pode_ver_local(integer),
  public.fn_pode_operar_local(integer), public.registrar_movimentacao(jsonb) to authenticated;

commit;

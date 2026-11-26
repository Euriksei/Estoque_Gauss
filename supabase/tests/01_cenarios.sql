\set QUIET on
\pset format unaligned
\pset tuples_only on
-- Funções só de teste (criadas aqui, fora do banco do app):
--  t_transferir: chama a interna criar_transferencia como o usuário logado, para testar as regras dela
--                (o app não chama mais: transferência é pedido).
--  t_criar_solicitacao_antiga: cópia da criar_solicitacao antiga, para criar pedidos 'legado' como os que já existem.
create function public.t_transferir(p jsonb) returns bigint language sql security definer set search_path = public as $t$ select criar_transferencia(p) $t$;
create or replace function public.t_criar_solicitacao_antiga(p jsonb) returns bigint
language plpgsql security definer set search_path = public as $$
declare v_id bigint; it jsonb; v_perfil text := fn_perfil()::text; v_dest integer; v_orig integer;
        v_un integer := nullif(p->>'unidade_id','')::int; v_n integer;
begin
  if v_perfil is null or v_perfil not in ('admin','operador','tecnico','agendamento') then
    raise exception 'Sem permissão' using errcode = '42501';
  end if;
  if p->'itens' is null or jsonb_array_length(p->'itens') = 0 then raise exception 'Informe ao menos um item'; end if;

  if v_perfil = 'tecnico' then
    select l.id, l.base_id into v_dest, v_orig
      from local l join tecnico t on t.id = l.tecnico_id where t.usuario_id = auth.uid();
    if v_dest is null then raise exception 'Seu login não está ligado a um estoque de técnico. Fale com um administrador'; end if;
    if v_orig is null then raise exception 'Seu estoque não tem um estoque base definido. Fale com um administrador'; end if;
    v_un := null;
  elsif v_perfil = 'agendamento' then
    select count(*), min(ul.local_id) into v_n, v_orig
      from usuario_local ul join local l on l.id = ul.local_id where ul.usuario_id = auth.uid() and l.tipo = 'estoque';
    if v_n <> 1 then raise exception 'Seu acesso ainda não tem um estoque definido. Fale com um administrador'; end if;
    v_dest := nullif(p->>'destino_id','')::int;
    if v_dest is null or not exists (select 1 from local where id = v_dest and tipo = 'tecnico') then
      raise exception 'O agendamento solicita do seu estoque para um técnico';
    end if;
    if v_un is null then raise exception 'Informe o cliente'; end if;
    if exists (select 1 from jsonb_array_elements(p->'itens') x where nullif(x->>'reservar_para_unidade_id','') is not null) then
      raise exception 'O agendamento só pode tirar de estoque livre ou dedicado, não criar dedicado';
    end if;
  else
    v_dest := nullif(p->>'destino_id','')::int;
    v_orig := nullif(p->>'origem_id','')::int;
    if v_dest is null or v_orig is null then raise exception 'Informe de onde sai e para onde vai'; end if;
    if v_dest = v_orig then raise exception 'Origem e destino devem ser diferentes'; end if;
    if not exists (select 1 from local where id = v_dest and tipo = 'tecnico') then v_un := null; end if;  -- cliente só em "estoque → técnico"
  end if;
  if exists (select 1 from jsonb_array_elements(p->'itens') x
              where nullif(x->>'reservar_para_unidade_id','') is not null and nullif(x->>'reservado_unidade_id','') is not null) then
    raise exception 'Um item não pode sair de um dedicado e ser dedicado ao mesmo tempo';
  end if;

  insert into solicitacao (tecnico_id, origem_id, destino_id, unidade_id, chamado_url, observacao)
  values (auth.uid(), v_orig, v_dest, v_un, nullif(p->>'chamado_url',''), nullif(p->>'observacao','')) returning id into v_id;
  for it in select * from jsonb_array_elements(p->'itens') loop
    insert into solicitacao_item (solicitacao_id, produto_id, quantidade, reservar_para_unidade_id, reservado_unidade_id)
    values (v_id, (it->>'produto_id')::int, (it->>'quantidade')::int,
            nullif(it->>'reservar_para_unidade_id','')::int, nullif(it->>'reservado_unidade_id','')::int);
  end loop;
  return v_id;
end $$;
grant execute on function public.t_transferir(jsonb), public.t_criar_solicitacao_antiga(jsonb) to authenticated;
-- usuários
insert into auth.users (id,email,raw_user_meta_data) values
 ('00000000-0000-0000-0000-00000000000a','admin@x','{"nome":"Admin"}'),
 ('00000000-0000-0000-0000-0000000000b1','nl@x','{"nome":"Op NL"}'),
 ('00000000-0000-0000-0000-0000000000b2','sbc@x','{"nome":"Op SBC"}'),
 ('00000000-0000-0000-0000-0000000000c1','tec@x','{"nome":"Tec"}'),
 ('00000000-0000-0000-0000-0000000000d1','cons@x','{"nome":"Cons"}'),
 ('00000000-0000-0000-0000-0000000000e1','ag@x','{"nome":"Agenda"}');
update usuario set ativo=true, perfil='admin' where email='admin@x';
update usuario set ativo=true, perfil='operador' where email in ('nl@x','sbc@x');
update usuario set ativo=true, perfil='tecnico' where email='tec@x';
update usuario set ativo=true where email='cons@x';
update usuario set ativo=true, perfil='agendamento' where email='ag@x';
insert into usuario_local select u.id, l.id from usuario u, local l where (u.email='nl@x' and l.nome='Nova Lima') or (u.email='sbc@x' and l.nome like 'São%');
insert into tecnico (nome,vinculo,usuario_id) select 'Tec CLT','clt',id from usuario where email='tec@x';
insert into tecnico (nome,vinculo) values ('Ze PJ','pj');
insert into local (nome,tipo,tecnico_id,base_id) select 'Carro Tec','tecnico',t.id,(select id from local where nome='Nova Lima') from tecnico t where t.nome='Tec CLT';
insert into local (nome,tipo,tecnico_id,base_id) select 'Estoque Ze PJ','tecnico',t.id,(select id from local where nome='Nova Lima') from tecnico t where t.nome='Ze PJ';
insert into cliente(nome) values ('Gerdau'),('CSN'); insert into unidade_cliente(cliente_id,nome) select id,'Ouro Branco' from cliente where nome='Gerdau'; insert into unidade_cliente(cliente_id,nome) select id,'Mineração' from cliente where nome='CSN';
create temp table ids as select
 (select id from local where nome='Nova Lima') nl, (select id from local where nome like 'São%') sbc, (select id from local where nome='Carro Tec') car,
 (select id from produto where nome='Módulo FMC 650') fmc, (select id from produto where nome='Chicote Galileo 7x / 10HUB') chi,
 (select id from unidade_cliente where nome='Ouro Branco') u1, (select id from unidade_cliente where nome='Mineração') u2;
grant select on ids to authenticated;
insert into usuario_local (usuario_id, local_id) select '00000000-0000-0000-0000-0000000000e1', sbc from ids;  -- estoque do agendamento
set role authenticated;
\echo '--- 1. Op NL: compra 100 FMC650 no Nova Lima'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'numero_nf','NF1','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',100)))) is not null from ids;
\echo '--- 2. saída de 150 deve falhar'
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',150)))) from ids;
\echo '--- 3. Op NL transfere 10 p/ SBC (em trânsito) e saldos'
\set ON_ERROR_STOP on
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','correios','codigo_rastreio','AB123','prazo_chegada','2026-10-20','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',10)))) as transf from ids \gset
select 'NL=' || coalesce((select sum(quantidade) from saldo where local_id=nl and produto_id=fmc),0) || ' SBC=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc),0) || ' (op NL nao ve SBC) em_transito=' || (select count(*) from transferencias_em_transito) from ids;
\set ON_ERROR_STOP off
\echo '--- Op NL tenta confirmar recebimento do próprio envio (deve falhar)'
select confirmar_recebimento(:transf);
\set ON_ERROR_STOP on
\echo '--- Op SBC confirma'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select confirmar_recebimento(:transf);
select 'SBC=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc),0) from ids;
\echo '--- 4. Técnico pede material, Op NL atende, técnico confirma'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select t_criar_solicitacao_antiga(jsonb_build_object('observacao','preciso','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',8)))) as sol from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol, jsonb_build_object('origem_id',nl,'modo_envio','tecnico','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',8)))) as t2 from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select 'tecnico ve saldo carro antes=' || coalesce((select sum(quantidade) from saldo where local_id=car),0) || ' saldo NL visível p/ técnico=' || (select count(*) from saldo where local_id=nl) from ids;
select confirmar_recebimento(:t2);
select 'carro=' || (select sum(quantidade) from saldo where local_id=car and produto_id=fmc) || ' linhas_saldo_visiveis=' || (select count(*) from saldo) from ids;
\echo '--- 5. Dedicado: Op NL manda 5 reservados p/ Ouro Branco ao técnico; técnico entrega'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',car,'modo_envio','tecnico','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'reservar_para_unidade_id',u1)))) as t3 from ids \gset
select 'NL livre=' || (select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id is null) || ' posição dedicado: ' || (select string_agg(situacao||':'||quantidade, ',') from dedicados_posicao) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select confirmar_recebimento(:t3);
select 'carro livre=' || (select sum(quantidade) from saldo where local_id=car and reservado_unidade_id is null) || ' reservado=' || (select sum(quantidade) from saldo where local_id=car and reservado_unidade_id is not null) from ids;
\set ON_ERROR_STOP off
\echo '--- técnico tenta usar reservado para OUTRA unidade (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',car,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'reservado_unidade_id',u1)))) from ids;
\echo '--- técnico tenta consumo interno (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- técnico tenta dar baixa em estoque do Nova Lima (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- técnico livre: reservado sendo usado como livre (saída de 9 > 8 livres) deve falhar'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',car,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',9)))) from ids;
\set ON_ERROR_STOP on
\echo '--- técnico entrega os 5 reservados ao Ouro Branco (sem chamado)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',car,'unidade_id',u1,'finalidade','mobilizacao','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'reservado_unidade_id',u1)))) is not null from ids;
select 'dedicado: ' || (select string_agg(situacao||':'||quantidade, ',') from dedicados_posicao) || ' hist=' || (select count(*) from dedicados_historico);
\echo '--- saída com modo de envio: operador NL sem modo (deve falhar), modo técnico sem técnico (deve falhar), modo técnico PJ sem login (ok)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'chamado_url','','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2)))) is not null from ids;
select 'saídas com técnico: ' || (select string_agg(coalesce(t.nome,'-')||'/'||m.modo_envio, ', ' order by m.id) from movimentacao m left join tecnico t on t.id=m.tecnico_id where m.tipo='SAIDA_CLIENTE');
\echo '--- 6. Dedicado nasce por devolução de cliente e ajuste (Op NL), não por compra; sai sempre inteiro; envio ao estoque do Ze PJ (sem login) confirmado por operador'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
\echo '--- devolução de cliente sem modo de envio (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','DEVOLUCAO_CLIENTE','local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- devolução com modo técnico sem o técnico que entregou (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','DEVOLUCAO_CLIENTE','modo_envio','tecnico','local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- devolução criando dedicado (Dedicado para) (deve falhar: dedicado não nasce mais por devolução)'
select registrar_movimentacao(jsonb_build_object('tipo','DEVOLUCAO_CLIENTE','modo_envio','retirada','local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',10,'reservar_para_unidade_id',u2)))) from ids;
\set ON_ERROR_STOP on
\echo '--- devolução com modo técnico e técnico Ze PJ (ok); dedicado da Mineração nasce por ajuste'
select registrar_movimentacao(jsonb_build_object('tipo','DEVOLUCAO_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','contagem','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',10,'reservar_para_unidade_id',u2)))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','contagem','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',2,'reservar_para_unidade_id',u2)))) is not null from ids;
select 'NL chicote livre=' || coalesce((select sum(quantidade) from saldo where local_id=nl and produto_id=chi and reservado_unidade_id is null),0) || ' dedicado Mineração=' || (select sum(quantidade) from saldo where local_id=nl and produto_id=chi and reservado_unidade_id=u2) from ids;
\set ON_ERROR_STOP off
\echo '--- compra criando dedicado (Dedicado para) (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'numero_nf','NF2','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',10,'reservar_para_unidade_id',u2)))) from ids;
\echo '--- compra entrando como dedicado de uma unidade (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'numero_nf','NF2','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',10,'reservado_unidade_id',u2)))) from ids;
\echo '--- criar dedicado em consumo interno (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',1,'reservar_para_unidade_id',u2)))) from ids;
\echo '--- consumo do estoque livre não toca no dedicado (saldo livre é 0; deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',1)))) from ids;
\echo '--- transferir só 4 dos 12 dedicados à Mineração (deve falhar: dedicado vai inteiro)'
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',(select id from local where nome='Estoque Ze PJ'),'modo_envio','correios','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',4,'reservado_unidade_id',u2)))) from ids;
\echo '--- dedicado Mineração para outra unidade (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',12,'reservado_unidade_id',u2)))) from ids;
\echo '--- saída de só 3 dos 12 dedicados à Mineração (deve falhar: dedicado vai inteiro)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',3,'reservado_unidade_id',u2)))) from ids;
\set ON_ERROR_STOP on
\echo '--- transferir os 12 dedicados (inteiro) ao estoque do Ze PJ'
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',(select id from local where nome='Estoque Ze PJ'),'modo_envio','correios','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',12,'reservado_unidade_id',u2)))) as t4 from ids \gset
\echo '--- Op SBC (sem relação com a transferência) tenta confirmar (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
\set ON_ERROR_STOP off
select confirmar_recebimento(:t4);
\set ON_ERROR_STOP on
\echo '--- Op NL (origem e base do técnico) confirma pelo Ze PJ'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select confirmar_recebimento(:t4);
select 'Ze dedicado=' || coalesce((select sum(quantidade) from saldo where local_id=(select id from local where nome='Estoque Ze PJ') and reservado_unidade_id=u2),0) || ' (Op NL não vê o estoque do Ze; confira como admin) NL dedicado=' || coalesce((select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u2),0) from ids;
\echo '--- ajuste cria 3 dedicados à Mineração no NL; entrega dos 3 (inteiro) ao cliente certo, por técnico Ze PJ'
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','contagem','itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',3,'reservar_para_unidade_id',u2)))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',3,'reservado_unidade_id',u2)))) is not null from ids;
select 'NL dedicado restante=' || coalesce((select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u2),0) from ids;
\echo '--- 7. Solicitações: técnico pede só da base dele; agendamento pede transferência mas não atende nem movimenta'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select t_criar_solicitacao_antiga(jsonb_build_object('origem_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2)))) as sol2 from ids \gset
select 'pedido do técnico: origem=' || (select l.nome from solicitacao s join local l on l.id=s.origem_id where s.id=:sol2) || ' (tentou SBC) destino=' || (select l.nome from solicitacao s join local l on l.id=s.destino_id where s.id=:sol2);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select t_criar_solicitacao_antiga(jsonb_build_object('destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',3)))) as sol3 from ids \gset
select 'agendamento vê solicitações=' || (select count(*) from solicitacao) || ' e saldo linhas>0=' || ((select count(*) from saldo) > 0);
\set ON_ERROR_STOP off
\echo '--- agendamento tenta atender, transferir e registrar (devem falhar)'
select atender_solicitacao(:sol3, '{"modo_envio":"correios"}'::jsonb);
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- agendamento sem origem (deve falhar)'
select t_criar_solicitacao_antiga(jsonb_build_object('destino_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- Op SBC não opera Nova Lima: não atende o pedido do técnico (origem NL) (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select atender_solicitacao(:sol2, '{"modo_envio":"correios"}'::jsonb);
\set ON_ERROR_STOP on
\echo '--- Op NL atende o pedido do técnico (origem NL, destino carro)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol2, jsonb_build_object('modo_envio','tecnico','itens',jsonb_build_array(jsonb_build_object('produto_id',(select fmc from ids),'quantidade',2)))) is not null;
select 'transferência em trânsito para o carro: ' || (select count(*) from transferencias_em_transito t where t.local_destino_id=(select car from ids));
\echo '--- 8. Solicitação para estoque dedicado: técnico pede 2 dedicados à Mineração; Op NL atende; chegam como dedicados'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select t_criar_solicitacao_antiga(jsonb_build_object('itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2,'reservar_para_unidade_id',u2), jsonb_build_object('produto_id',fmc,'quantidade',1)))) as sol4 from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol4, '{"modo_envio":"tecnico"}'::jsonb) as t5 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select confirmar_recebimento(:t5);
select 'carro dedicado Mineração=' || (select sum(quantidade) from saldo where local_id=car and reservado_unidade_id=u2) from ids;
\echo '--- consulta não escreve; vê tudo'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
\set ON_ERROR_STOP off
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens','[]'::jsonb)) from ids;
insert into produto(nome) values ('x');
\set ON_ERROR_STOP on
select 'consulta vê saldo linhas=' || (select count(*) from saldo);
\echo '--- operador não estorna; admin estorna'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
select estornar_movimentacao(1,'teste');
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\echo '--- admin estorna a compra de 100 (deve falhar: saldo já usado)'
\set ON_ERROR_STOP off
select estornar_movimentacao(1,'erro de digitação');
\set ON_ERROR_STOP on
select 'auditoria linhas=' || (select count(*) from auditoria);

\echo '--- 9. Aceitar solicitação: aberta -> em_producao (prazo 1 dia); técnico não aceita; só operador/admin cancelam depois'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select t_criar_solicitacao_antiga(jsonb_build_object('itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) as sol5 from ids \gset
\set ON_ERROR_STOP off
\echo '--- técnico tenta aceitar a própria solicitação (deve falhar)'
select aceitar_solicitacao(:sol5);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select aceitar_solicitacao(:sol5);
select 'status=' || status::text || ' prazo≈1 dia: ' || (prazo_producao - now() between interval '23 hours' and interval '25 hours') from solicitacao where id=:sol5;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
\set ON_ERROR_STOP off
\echo '--- técnico tenta cancelar solicitação já em produção (deve falhar)'
select cancelar_solicitacao(:sol5);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:sol5, '{"modo_envio":"tecnico"}'::jsonb) is not null;
select 'status final=' || status::text from solicitacao where id=:sol5;

\echo '--- 10. Chips: módulo com chip, instalar chip avulso, trocar de operadora, descartar chip ruim'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select (select id from local where nome='Nova Lima') as nl2, (select id from produto where nome='Módulo FMC 150') as fm, (select id from produto where nome='Chip Claro M2M') as chc, (select id from produto where nome='Chip Vivo M2M') as chv, (select id from produto where nome='Buzzer') as bz \gset
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',:nl2,'itens',jsonb_build_array(jsonb_build_object('produto_id',:fm,'quantidade',10,'condicao','novo'),jsonb_build_object('produto_id',:fm,'quantidade',4,'condicao','claro'),jsonb_build_object('produto_id',:chc,'quantidade',6),jsonb_build_object('produto_id',:chv,'quantidade',3)))) is not null;
select 'FMC150 sem chip=' || coalesce((select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='novo' and reservado_unidade_id is null),0) || ' claro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='claro');
\echo '--- instalar Claro em 3 módulos sem chip (chip avulso Claro 6 -> 3)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',3,'de','novo','para','claro')) is not null;
select 'sem chip=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='novo' and reservado_unidade_id is null) || ' claro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='claro') || ' chipClaro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chc);
\echo '--- trocar Claro por Vivo em 2 módulos: Claro volta ao avulso (+2), Vivo avulso -2'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',2,'de','claro','para','vivo')) is not null;
select 'claro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='claro') || ' vivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='vivo') || ' chipClaro=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chc) || ' chipVivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chv);
\echo '--- módulo não comunicou: tira o chip Vivo e descarta (módulo volta a sem chip, chip avulso não volta)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','vivo','para','novo','chip_retirado','descartar','observacao','não comunicou no teste')) is not null;
select 'vivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:fm and condicao='vivo') || ' chipVivo=' || (select sum(quantidade) from saldo where local_id=:nl2 and produto_id=:chv);
\set ON_ERROR_STOP off
\echo '--- descartar sem motivo (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','claro','para','novo','chip_retirado','descartar')) is not null;
\echo '--- instalar chip sem chip avulso suficiente (deve falhar): 5 Vivo, só restam 1'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',5,'de','novo','para','vivo')) is not null;
\echo '--- trocar chip em item que não usa chip (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:bz,'quantidade',1,'de','novo','para','claro')) is not null;
\echo '--- saída de módulo com chip que não existe em estoque (deve falhar): 9 Vivo'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',:nl2,'itens',jsonb_build_array(jsonb_build_object('produto_id',:fm,'quantidade',9,'condicao','vivo')))) is not null;
\echo '--- técnico não troca chip (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','novo','para','claro')) is not null;
\set ON_ERROR_STOP on

\echo '--- 11. Regras de solicitação: agendamento, cliente, dedicado e quem dá andamento'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select 'agendamento: origem=' || (select l.nome from solicitacao s join local l on l.id=s.origem_id where s.id=:sol3) || ' destino carro, cliente=' || (select un.nome from solicitacao s join unidade_cliente un on un.id=s.unidade_id where s.id=:sol3);
\set ON_ERROR_STOP off
\echo '--- agendamento tenta estoque -> estoque (deve falhar)'
select t_criar_solicitacao_antiga(jsonb_build_object('destino_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- agendamento sem cliente (deve falhar)'
select t_criar_solicitacao_antiga(jsonb_build_object('destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1)))) from ids;
\echo '--- agendamento tenta criar dedicado (deve falhar)'
select t_criar_solicitacao_antiga(jsonb_build_object('destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1,'reservar_para_unidade_id',u2)))) from ids;
\set ON_ERROR_STOP on
\echo '--- agendamento pede item do dedicado de OUTRO cliente (u2) para o cliente u1: o pedido é aceito (o alerta é na tela)'
select t_criar_solicitacao_antiga(jsonb_build_object('destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1,'reservado_unidade_id',u2)))) as sol6 from ids \gset
select 'item sai do dedicado: ' || (select un.nome from solicitacao_item i join unidade_cliente un on un.id=i.reservado_unidade_id where i.solicitacao_id=:sol6);
\set ON_ERROR_STOP off
\echo '--- operador SBC não aceita pedido com origem em Nova Lima (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select t_criar_solicitacao_antiga(jsonb_build_object('origem_id',(select nl from ids),'destino_id',(select sbc from ids),'itens',jsonb_build_array(jsonb_build_object('produto_id',(select fmc from ids),'quantidade',1)))) as sol7 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select aceitar_solicitacao(:sol7);
\echo '--- operador NL (origem) aceita; administrador também poderia'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select aceitar_solicitacao(:sol7);
select 'status=' || status::text from solicitacao where id=:sol7;

\echo '--- 12. Operador só mexe nos estoques dele (Op NL não tira nada do SBC por nenhum caminho); saldo conferido por chip e por dedicado'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\echo '--- admin pode qualquer local: compra no SBC 3 FMC 650 Vivo, 10 Claro e 10 Buzzer; ajuste cria 2 dedicados ao Ouro Branco'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',sbc,'itens',jsonb_build_array(
  jsonb_build_object('produto_id',fmc,'quantidade',3,'condicao','vivo'), jsonb_build_object('produto_id',fmc,'quantidade',10,'condicao','claro'),
  jsonb_build_object('produto_id',:bz,'quantidade',10)))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',sbc,'observacao','inventário','itens',jsonb_build_array(
  jsonb_build_object('produto_id',fmc,'quantidade',2,'reservar_para_unidade_id',u1)))) is not null from ids;
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',nl,'modo_envio','correios','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as tr_sbc from ids \gset
create temp table sbc_antes as select produto_id, condicao, reservado_unidade_id, quantidade from saldo where local_id=(select sbc from ids);
select 'SBC FMC650 vivo=' || (select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and condicao='vivo') || ' claro=' || (select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and condicao='claro') || ' dedicado Ouro Branco=' || (select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and reservado_unidade_id=u1) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
\echo '--- Op NL: saída para cliente no SBC (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- Op NL: consumo interno no SBC (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- Op NL: descarte no SBC (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','DESCARTE','local_id',sbc,'observacao','quebrado','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- Op NL: ajuste -1 no SBC (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',sbc,'observacao','teste','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',-1)))) from ids;
\echo '--- Op NL: entrada por compra no SBC (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- Op NL: transferência do SBC para Nova Lima (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- Op NL: saída do SBC para estoque de técnico (carro) (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- Op NL: Dedicados, envia o dedicado do Ouro Branco que está no SBC (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1,'reservado_unidade_id',u1)))) from ids;
\echo '--- Op NL: troca de chip no SBC (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',sbc,'produto_id',fmc,'quantidade',1,'de','vivo','para','claro')) from ids;
\echo '--- Op NL: aceitar e atender solicitação com origem no SBC (devem falhar)'
select aceitar_solicitacao(:sol6);
select atender_solicitacao(:sol6, '{}'::jsonb);
\echo '--- Op NL: cancelar transferência que saiu do SBC (deve falhar)'
select cancelar_transferencia(:tr_sbc, 'teste');
\echo '--- Op NL: chamar funções internas direto pela API (devem falhar: permissão negada)'
select fn_gravar_itens(:tr_sbc, jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',5)));
select fn_travar_locais(array[(select sbc from ids)]);
select fn_verificar_saldo(array[(select sbc from ids)]);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select 'SBC sem mudança depois das tentativas do Op NL: ' || (not exists (
  (select produto_id, condicao, reservado_unidade_id, quantidade from saldo where local_id=(select sbc from ids)) except (select * from sbc_antes))
  and not exists ((select * from sbc_antes) except (select produto_id, condicao, reservado_unidade_id, quantidade from saldo where local_id=(select sbc from ids))))
  || ' itens na transferência do SBC=' || (select count(*) from movimentacao_item where movimentacao_id=:tr_sbc);

\echo '--- saldo por chip: no SBC há 3 FMC 650 Vivo e 10 Claro'
\set ON_ERROR_STOP off
\echo '--- saída de 5 Vivo (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'condicao','vivo')))) from ids;
\echo '--- consumo de 4 Vivo (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',4,'condicao','vivo')))) from ids;
\echo '--- ajuste de -4 Vivo (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',sbc,'observacao','teste','itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',-4,'condicao','vivo')))) from ids;
\echo '--- transferência de 5 Vivo para Nova Lima (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',5,'condicao','vivo')))) from ids;
\echo '--- trocar 4 Vivo por Claro (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',sbc,'produto_id',fmc,'quantidade',4,'de','vivo','para','claro')) from ids;
\echo '--- 2 Vivo + 2 Vivo na mesma movimentação (4 > 3) (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',2,'condicao','vivo'),jsonb_build_object('produto_id',fmc,'quantidade',2,'condicao','vivo')))) from ids;
\echo '--- livre x dedicado: saída do livre maior que o livre (o dedicado não cobre) (deve falhar)'
select coalesce((select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and condicao='novo' and reservado_unidade_id is null),0) + 1 as livre_mais_1 from ids \gset
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',:livre_mais_1)))) from ids;
\echo '--- saída de 3 dedicados ao Ouro Branco (só há 2) (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',3,'reservado_unidade_id',u1)))) from ids;
\echo '--- transferência de 3 dedicados ao Ouro Branco (só há 2) (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',sbc,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',3,'reservado_unidade_id',u1)))) from ids;
\echo '--- dedicado com chip Vivo (os 2 dedicados são sem chip) (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',1,'condicao','vivo','reservado_unidade_id',u1)))) from ids;
\set ON_ERROR_STOP on
\echo '--- no limite passa: saída de 3 Vivo e de 2 dedicados ao Ouro Branco'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',fmc,'quantidade',3,'condicao','vivo'),jsonb_build_object('produto_id',fmc,'quantidade',2,'reservado_unidade_id',u1)))) is not null from ids;
select 'SBC FMC650 vivo=' || (select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and condicao='vivo') || ' claro=' || (select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and condicao='claro') || ' dedicado Ouro Branco=' || (select sum(quantidade) from saldo where local_id=sbc and produto_id=fmc and reservado_unidade_id=u1) || ' algum saldo negativo=' || exists (select 1 from saldo where quantidade < 0) from ids;

\echo '--- 13. Datas (nada no futuro, hoje de São Paulo), meio de envio só Correios e dedicado inteiro'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select fn_hoje()::text as hoje, (fn_hoje() + 1)::text as amanha, (fn_hoje() + 10)::text as daqui10 \gset
select 'hoje em São Paulo = ' || (fn_hoje() = (now() at time zone 'America/Sao_Paulo')::date);
\set ON_ERROR_STOP off
\echo '--- compra com data de amanhã (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'data',:'amanha','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- consumo com data de amanhã (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',nl,'data',:'amanha','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- transferência com data de envio amanhã (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','correios','data',:'amanha','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- troca de chip com data de amanhã (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',:nl2,'produto_id',:fm,'quantidade',1,'de','novo','para','claro','data',:'amanha'));
\set ON_ERROR_STOP on
\echo '--- hoje passa; prazo de chegada pode ser futuro; sem data vale hoje de São Paulo'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'data',:'hoje','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',5)))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',5)))) as sem_data from ids \gset
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','correios','prazo_chegada',:'daqui10','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as tr_prazo from ids \gset
select 'sem data = hoje: ' || (select data = fn_hoje() from movimentacao where id=:sem_data) || '; transferência envio hoje e prazo futuro: ' || (select data = fn_hoje() and prazo_chegada > fn_hoje() from movimentacao where id=:tr_prazo);

\echo '--- meio de envio: sedex não existe mais, só Correios'
\set ON_ERROR_STOP off
\echo '--- saída para cliente por sedex (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','sedex','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- transferência por sedex (deve falhar)'
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','sedex','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on
select 'movimentações com sedex=' || (select count(*) from movimentacao where modo_envio::text = 'sedex') || ' com correios=' || (select count(*) from movimentacao where modo_envio = 'correios');

\echo '--- dedicado inteiro: ajuste cria no Nova Lima, para Gerdau - Ouro Branco, 2 FMC 150 Claro, 1 FMC 150 Vivo e 3 Buzzer'
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','inventário','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:fm,'quantidade',2,'condicao','claro','reservar_para_unidade_id',u1),
  jsonb_build_object('produto_id',:fm,'quantidade',1,'condicao','vivo','reservar_para_unidade_id',u1),
  jsonb_build_object('produto_id',:bz,'quantidade',3,'reservar_para_unidade_id',u1)))) is not null from ids;
select 'NL dedicado Ouro Branco=' || (select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u1) from ids;
\set ON_ERROR_STOP off
\echo '--- saída só dos 2 Claro (deve falhar: faltam 4)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:fm,'quantidade',2,'condicao','claro','reservado_unidade_id',u1)))) from ids;
\echo '--- Dedicados: transferência dos módulos sem os Buzzer (deve falhar: faltam 3)'
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','correios','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:fm,'quantidade',2,'condicao','claro','reservado_unidade_id',u1),
  jsonb_build_object('produto_id',:fm,'quantidade',1,'condicao','vivo','reservado_unidade_id',u1)))) from ids;
\echo '--- consumo de 1 Buzzer dedicado (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1,'reservado_unidade_id',u1)))) from ids;
\echo '--- descarte dos 3 Buzzer dedicados (deve falhar: faltam 3 módulos)'
select registrar_movimentacao(jsonb_build_object('tipo','DESCARTE','local_id',nl,'observacao','quebrado','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',3,'reservado_unidade_id',u1)))) from ids;
\echo '--- ajuste reduzindo 1 Claro dedicado (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','contagem','itens',jsonb_build_array(jsonb_build_object('produto_id',:fm,'quantidade',-1,'condicao','claro','reservado_unidade_id',u1)))) from ids;
\set ON_ERROR_STOP on
\echo '--- Dedicados: transferência de tudo (2 Claro, 1 Vivo, 3 Buzzer) para o SBC passa'
select t_transferir(jsonb_build_object('origem_id',nl,'destino_id',sbc,'modo_envio','correios','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:fm,'quantidade',2,'condicao','claro','reservado_unidade_id',u1),
  jsonb_build_object('produto_id',:fm,'quantidade',1,'condicao','vivo','reservado_unidade_id',u1),
  jsonb_build_object('produto_id',:bz,'quantidade',3,'reservado_unidade_id',u1)))) as tr_ded from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select confirmar_recebimento(:tr_ded);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select 'NL dedicado Ouro Branco=' || coalesce((select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u1),0) || ' SBC dedicado Ouro Branco=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and reservado_unidade_id=u1),0) from ids;
\echo '--- Op SBC entrega tudo ao Ouro Branco numa saída só'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','modo_envio','correios','local_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(
  jsonb_build_object('produto_id',:fm,'quantidade',2,'condicao','claro','reservado_unidade_id',u1),
  jsonb_build_object('produto_id',:fm,'quantidade',1,'condicao','vivo','reservado_unidade_id',u1),
  jsonb_build_object('produto_id',:bz,'quantidade',3,'reservado_unidade_id',u1)))) is not null from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select 'SBC dedicado Ouro Branco=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and reservado_unidade_id=u1),0) || ' algum saldo negativo=' || exists (select 1 from saldo where quantidade < 0) from ids;

\echo '--- 14. Novo fluxo: transferência é pedido (a origem aceita e envia); solicitação só do agendamento para cliente'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\echo '--- preparo (admin): Nova Lima recebe 10 Buzzer e 5 FMC 650 Claro; ajuste cria dedicado da Mineração no NL (2 Buzzer + 1 FMC 650 Vivo)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens',jsonb_build_array(
  jsonb_build_object('produto_id',:bz,'quantidade',10), jsonb_build_object('produto_id',fmc,'quantidade',5,'condicao','claro')))) is not null from ids;
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',nl,'observacao','inventário','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:bz,'quantidade',2,'reservar_para_unidade_id',u2), jsonb_build_object('produto_id',fmc,'quantidade',1,'condicao','vivo','reservar_para_unidade_id',u2)))) is not null from ids;
select coalesce(sum(quantidade),0) as bz_nl_antes from saldo where local_id=(select nl from ids) and produto_id=:bz and reservado_unidade_id is null \gset

\echo '--- pedido de transferência: consulta, técnico e agendamento não criam (devem falhar)'
\set ON_ERROR_STOP off
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- não existe mais envio direto: criar_transferencia pela API (deve falhar: permissão negada)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select criar_transferencia(jsonb_build_object('origem_id',nl,'destino_id',car,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- pedido com item tirado do dedicado direto (deve falhar: use dedicados)'
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1,'reservado_unidade_id',u2)))) from ids;
\echo '--- pedido levando dedicado que não existe na origem (deve falhar)'
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'dedicados',jsonb_build_array(u1))) from ids;
\echo '--- pedido sem itens (deve falhar)'
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc)) from ids;
\set ON_ERROR_STOP on

\echo '--- Op SBC cria pedido de Nova Lima para o carro do técnico (qualquer origem), com chamado Jira'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',car,'chamado_url','https://jira.exemplo/browse/OPS-1','observacao','urgente',
  'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',3), jsonb_build_object('produto_id',fmc,'quantidade',2)))) as pt1 from ids \gset
select id as pt1_fmc from solicitacao_item where solicitacao_id=:pt1 and produto_id=(select fmc from ids) \gset
select 'pt1: tipo=' || tipo || ' status=' || status::text || ' chamado=' || chamado_url from solicitacao where id=:pt1;
select 'Op SBC na view: situacao=' || situacao || ' pode_aceitar=' || pode_aceitar || ' pode_cancelar=' || pode_cancelar from solicitacao_acoes where id=:pt1;
\set ON_ERROR_STOP off
\echo '--- Op SBC aceita pedido com origem em Nova Lima (deve falhar)'
select aceitar_solicitacao(:pt1);
\echo '--- Op NL envia antes de aceitar (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:pt1, '{"modo_envio":"tecnico"}'::jsonb);
\set ON_ERROR_STOP on
select 'Op NL na view: pode_aceitar=' || pode_aceitar || ' pode_atender=' || pode_atender || ' saldo NL não mudou com o pedido: ' || ((select coalesce(sum(quantidade),0) from saldo where local_id=(select nl from ids) and produto_id=:bz and reservado_unidade_id is null) = :bz_nl_antes) from solicitacao_acoes where id=:pt1;
select aceitar_solicitacao(:pt1);
select 'aceito: status=' || status::text || ' prazo≈1 dia: ' || (prazo_producao - now() between interval '23 hours' and interval '25 hours') from solicitacao where id=:pt1;
\set ON_ERROR_STOP off
\echo '--- envio com data de amanhã (deve falhar)'
select atender_solicitacao(:pt1, jsonb_build_object('modo_envio','tecnico','data',(fn_hoje()+1)::text));
\echo '--- envio sem meio de envio (deve falhar)'
select atender_solicitacao(:pt1, '{}'::jsonb);
\echo '--- envio por sedex (deve falhar)'
select atender_solicitacao(:pt1, '{"modo_envio":"sedex"}'::jsonb);
\set ON_ERROR_STOP on
\echo '--- Op NL envia: módulos com chip Claro (escolhido no envio), prazo de chegada futuro -> em trânsito; saldo sai na hora'
select atender_solicitacao(:pt1, jsonb_build_object('modo_envio','tecnico','codigo_rastreio','R1','prazo_chegada',(fn_hoje()+3)::text,
  'chips',jsonb_build_object(:'pt1_fmc','claro'))) as mv1 \gset
select 'enviado: situacao=' || (select situacao from solicitacao_acoes where id=:pt1) || ' movimentação=' || m.tipo::text || '/' || m.status::text || ' modo=' || m.modo_envio::text
  || ' chamado na movimentação=' || coalesce(m.chamado_url,'-') || ' NL Buzzer saiu 3: ' || ((select coalesce(sum(quantidade),0) from saldo where local_id=(select nl from ids) and produto_id=:bz and reservado_unidade_id is null) = :bz_nl_antes - 3)
  from movimentacao m where m.id=:mv1;
\set ON_ERROR_STOP off
\echo '--- enviar de novo o mesmo pedido (deve falhar)'
select atender_solicitacao(:pt1, '{"modo_envio":"tecnico"}'::jsonb);
\echo '--- cancelar pedido já enviado (deve falhar)'
select cancelar_solicitacao(:pt1);
\set ON_ERROR_STOP on
\echo '--- técnico vê o pedido para o carro dele e confirma o recebimento'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select 'técnico vê o pedido: ' || (select count(*) from solicitacao where id=:pt1) || ' e não cria solicitação nem pedido';
select confirmar_recebimento(:mv1);
select 'recebido: situacao=' || (select situacao from solicitacao_acoes where id=:pt1) || ' carro FMC 650 Claro=' || (select sum(quantidade) from saldo where local_id=(select car from ids) and produto_id=(select fmc from ids) and condicao='claro');

\echo '--- pedido com dedicado: Op NL pede levar o dedicado da Mineração (inteiro) do NL para o SBC'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'dedicados',jsonb_build_array(u2))) as pt2 from ids \gset
select aceitar_solicitacao(:pt2);
select atender_solicitacao(:pt2, '{"modo_envio":"transportadora"}'::jsonb) as mv2 \gset
select 'itens enviados do dedicado=' || (select count(*) || ' linhas, ' || sum(quantidade) || ' unidades' from movimentacao_item where movimentacao_id=:mv2) || ' NL dedicado Mineração=' || coalesce((select sum(quantidade) from saldo where local_id=nl and reservado_unidade_id=u2),0) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select confirmar_recebimento(:mv2);
select 'SBC dedicado Mineração=' || (select sum(quantidade) from saldo where local_id=sbc and reservado_unidade_id=u2) from ids;
\echo '--- pedido com Dedicado para: 1 Buzzer livre do NL chega ao SBC dedicado ao Ouro Branco'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1,'reservar_para_unidade_id',u1)))) as pt3 from ids \gset
select aceitar_solicitacao(:pt3);
select atender_solicitacao(:pt3, '{"modo_envio":"correios"}'::jsonb) as mv3 \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select confirmar_recebimento(:mv3);
select 'SBC dedicado Ouro Branco (Buzzer)=' || (select sum(quantidade) from saldo where local_id=sbc and reservado_unidade_id=u1 and produto_id=:bz) from ids;
\echo '--- cancelar: só o administrador ou o operador da ORIGEM cancelam pedido aberto ou em produção'
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as pt4 from ids \gset
select 'Op SBC (criou, mas a origem é NL) na view: pode_cancelar=' || pode_cancelar from solicitacao_acoes where id=:pt4;
\set ON_ERROR_STOP off
\echo '--- Op SBC cancela pedido aberto com origem no NL, mesmo tendo criado (deve falhar)'
select cancelar_solicitacao(:pt4);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select 'Op NL (origem) na view: pode_cancelar=' || pode_cancelar from solicitacao_acoes where id=:pt4;
select cancelar_solicitacao(:pt4);
select 'pt4 cancelado pelo operador da origem: ' || (select situacao from solicitacao_acoes where id=:pt4);
select criar_pedido_transferencia(jsonb_build_object('origem_id',nl,'destino_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as pt5 from ids \gset
select aceitar_solicitacao(:pt5);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
\set ON_ERROR_STOP off
\echo '--- Op SBC cancela pedido em produção com origem no NL (deve falhar)'
select cancelar_solicitacao(:pt5);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select cancelar_solicitacao(:pt5);
select 'pt5 em produção cancelado pelo admin: ' || (select situacao from solicitacao_acoes where id=:pt5);
\echo '--- retirar dedicado: quem cancela é o operador do DESTINO'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','retirar_dedicado','destino_id',sbc,'unidade_id',u1,'chamado_url','https://jira.exemplo/browse/AG-10','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as s5 from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
\set ON_ERROR_STOP off
\echo '--- Op NL cancela retirada com destino no SBC (deve falhar)'
select cancelar_solicitacao(:s5);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select cancelar_solicitacao(:s5);
select 's5 cancelada pelo operador do destino: ' || (select situacao from solicitacao_acoes where id=:s5);

\echo '--- solicitação: operador, técnico e consulta não criam (devem falhar; o administrador cria, ver cenário 23)'
\set ON_ERROR_STOP off
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- agendamento: tipo antigo (estoque -> técnico) não existe mais (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','destino_id',car,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- agendamento sem cliente (deve falhar)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- agendamento pede item de dedicado ou cria dedicado em enviar_cliente (devem falhar: só livre)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1,'reservado_unidade_id',u2)))) from ids;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1,'reservar_para_unidade_id',u1)))) from ids;
\set ON_ERROR_STOP on
\echo '--- agendamento: enviar ao cliente Ouro Branco 2 Buzzer e 1 FMC 650 do NL (chip escolhido no atendimento)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',nl,'unidade_id',u1,'chamado_url','https://jira.exemplo/browse/AG-7',
  'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',2), jsonb_build_object('produto_id',fmc,'quantidade',1)))) as s1 from ids \gset
select id as s1_fmc from solicitacao_item where solicitacao_id=:s1 and produto_id=(select fmc from ids) \gset
\set ON_ERROR_STOP off
\echo '--- Op SBC aceita solicitação com origem no NL (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select aceitar_solicitacao(:s1);
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select aceitar_solicitacao(:s1);
\set ON_ERROR_STOP off
\echo '--- agendamento cancela depois de aceita (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select cancelar_solicitacao(:s1);
\echo '--- atender sem meio de envio, e por técnico sem dizer qual (devem falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:s1, '{}'::jsonb);
select atender_solicitacao(:s1, '{"modo_envio":"tecnico"}'::jsonb);
\set ON_ERROR_STOP on
\echo '--- Op NL atende: técnico Ze PJ leva, FMC 650 com Claro -> SAÍDA PARA CLIENTE na hora'
select atender_solicitacao(:s1, jsonb_build_object('modo_envio','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ'),'chips',jsonb_build_object(:'s1_fmc','claro'))) as ms1 \gset
select 'saída: ' || m.tipo::text || ' modo=' || m.modo_envio::text || ' técnico=' || t.nome || ' cliente=' || u.nome || ' chamado=' || m.chamado_url
  || ' itens=' || (select string_agg(p.nome || ' ' || i.condicao::text || ' x' || i.quantidade, ', ' order by p.nome) from movimentacao_item i join produto p on p.id=i.produto_id where i.movimentacao_id=m.id)
  || ' situacao=' || (select situacao from solicitacao_acoes where id=:s1)
  from movimentacao m join tecnico t on t.id=m.tecnico_id join unidade_cliente u on u.id=m.unidade_id where m.id=:ms1;

\echo '--- enviar dedicado: agendamento manda o dedicado da Mineração que está no SBC (vai inteiro)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
\set ON_ERROR_STOP off
\echo '--- enviar_dedicado com itens (deve falhar) e sem dedicado na origem (deve falhar)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_dedicado','origem_id',sbc,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_dedicado','origem_id',nl,'unidade_id',u2)) from ids;
\echo '--- enviar dedicado sem link do chamado, com link em branco e com link sem http (devem falhar)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_dedicado','origem_id',sbc,'unidade_id',u2)) from ids;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_dedicado','origem_id',sbc,'unidade_id',u2,'chamado_url','   ')) from ids;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_dedicado','origem_id',sbc,'unidade_id',u2,'chamado_url','jira.exemplo/browse/AG-8')) from ids;
\echo '--- retirar dedicado sem link do chamado e com link ftp (devem falhar)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','retirar_dedicado','destino_id',nl,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','retirar_dedicado','destino_id',nl,'unidade_id',u1,'chamado_url','ftp://jira.exemplo/AG-9','itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_dedicado','origem_id',sbc,'unidade_id',u2,'chamado_url','https://jira.exemplo/browse/AG-8')) as s2 from ids \gset
select 's2 chamado=' || chamado_url from solicitacao where id=:s2;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select aceitar_solicitacao(:s2);
select atender_solicitacao(:s2, '{"modo_envio":"correios","codigo_rastreio":"BR1"}'::jsonb) as ms2 \gset
select 'saída do dedicado: ' || (select count(*) || ' linhas, ' || sum(quantidade) || ' unidades' from movimentacao_item where movimentacao_id=:ms2) || ' SBC dedicado Mineração=' || coalesce((select sum(quantidade) from saldo where local_id=sbc and reservado_unidade_id=u2),0) from ids;

\echo '--- retirar dedicado: agendamento pede buscar no Ouro Branco 2 FMC 650 Vivo e 1 Buzzer para o NL'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','retirar_dedicado','destino_id',nl,'unidade_id',u1,'chamado_url','https://jira.exemplo/browse/AG-9','itens',jsonb_build_array(
  jsonb_build_object('produto_id',fmc,'quantidade',2,'condicao','vivo'), jsonb_build_object('produto_id',:bz,'quantidade',1)))) as s3 from ids \gset
\set ON_ERROR_STOP off
\echo '--- Op SBC aceita retirada com destino no NL (deve falhar); Op NL registra a chegada antes de aceitar (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select aceitar_solicitacao(:s3);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select atender_solicitacao(:s3, '{}'::jsonb);
\set ON_ERROR_STOP on
select aceitar_solicitacao(:s3);
select atender_solicitacao(:s3, '{}'::jsonb) as ms3 \gset
select 'chegada: ' || m.tipo::text || ' no ' || l.nome || ' itens dedicados a ' || (select string_agg(distinct u.nome, ',') from movimentacao_item i join unidade_cliente u on u.id=i.reservar_para_unidade_id where i.movimentacao_id=m.id)
  || ' NL dedicado Ouro Branco=' || (select sum(quantidade) from saldo where local_id=(select nl from ids) and reservado_unidade_id=(select u1 from ids))
  from movimentacao m join local l on l.id=m.local_destino_id where m.id=:ms3;
\echo '--- agendamento cancela solicitação ainda aberta (quem criou pode)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000e1',false) \gset
\echo '--- enviar ao cliente sem link do chamado continua valendo (chamado opcional)'
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as s4 from ids \gset
select cancelar_solicitacao(:s4);
select 's4: ' || (select situacao from solicitacao_acoes where id=:s4);
\echo '--- pedidos antigos continuam com tipo legado; nenhum saldo negativo'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select 'legado=' || count(*) filter (where tipo='legado') || ' transferencia=' || count(*) filter (where tipo='transferencia') || ' enviar_cliente=' || count(*) filter (where tipo='enviar_cliente')
  || ' enviar_dedicado=' || count(*) filter (where tipo='enviar_dedicado') || ' retirar_dedicado=' || count(*) filter (where tipo='retirar_dedicado')
  || ' algum saldo negativo=' || exists (select 1 from saldo where quantidade < 0) from solicitacao;

\echo '--- 15. Ver como: só o administrador real simula outro perfil, com os mesmos acessos de verdade; voltar sempre funciona'
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select 'Op NL: perfil_real=' || perfil_real || ' perfil=' || perfil || ' simulando=' || simulando from minha_visualizacao;
\set ON_ERROR_STOP off
\echo '--- Op NL tenta ver como agendamento, consulta e técnico (devem falhar)'
select definir_visualizacao(jsonb_build_object('perfil','agendamento','local_id',(select sbc from ids)));
select definir_visualizacao('{"perfil":"consulta"}'::jsonb);
select definir_visualizacao(jsonb_build_object('perfil','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ')));
\echo '--- consulta tenta ver como operador (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
select definir_visualizacao(jsonb_build_object('perfil','operador','local_id',(select nl from ids)));
\set ON_ERROR_STOP on
\echo '--- uma linha de simulação gravada para quem não é admin não vale (o banco só olha a simulação do admin real)'
reset role;
insert into visualizacao (usuario_id, perfil, local_id) values ('00000000-0000-0000-0000-0000000000b1', 'agendamento', (select id from local where nome like 'São%'));
set role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select 'Op NL com linha forjada: perfil=' || fn_perfil() || ' opera SBC=' || fn_pode_operar_local((select sbc from ids)) || ' simulando=' || (select simulando from minha_visualizacao);
reset role;
delete from visualizacao where usuario_id = '00000000-0000-0000-0000-0000000000b1';
set role authenticated;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\set ON_ERROR_STOP off
\echo '--- admin: operador sem estoque, operador num carro de técnico e perfil inválido (devem falhar)'
select definir_visualizacao('{"perfil":"operador"}'::jsonb);
select definir_visualizacao(jsonb_build_object('perfil','operador','local_id',(select car from ids)));
select definir_visualizacao('{"perfil":"chefe"}'::jsonb);
\set ON_ERROR_STOP on
\echo '--- admin vê como operador de Nova Lima'
select definir_visualizacao(jsonb_build_object('perfil','operador','local_id',(select nl from ids)));
select 'admin como operador: perfil_real=' || perfil_real || ' perfil=' || perfil || ' simulando=' || simulando || ' local=' || local_nome || ' locais_operaveis=' || (select string_agg(l.nome, ',') from local l where l.id = any(locais_operaveis)) from minha_visualizacao;
select 'vê só o estoque dele: locais no saldo=' || (select string_agg(distinct l.nome, ',') from saldo s join local l on l.id=s.local_id);
\set ON_ERROR_STOP off
\echo '--- como operador NL: entrada e consumo no SBC (devem falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\echo '--- como operador NL: aceitar pedido com origem no SBC (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
\set ON_ERROR_STOP on
select criar_pedido_transferencia(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as pv1 from ids \gset
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\set ON_ERROR_STOP off
select aceitar_solicitacao(:pv1);
\echo '--- como operador: cadastro de item e estorno, que são do administrador (devem falhar)'
insert into produto (nome) values ('Item criado simulando');
select estornar_movimentacao(1, 'teste');
\set ON_ERROR_STOP on
\echo '--- como operador NL: entrada no NL passa e fica gravada com o usuário real (admin)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',2)))) as mvc from ids \gset
select 'criado_por é o admin real: ' || (criado_por = '00000000-0000-0000-0000-00000000000a') from movimentacao where id=:mvc;

\echo '--- admin vê como agendamento do SBC: cria solicitação, não registra nem cria pedido'
select definir_visualizacao(jsonb_build_object('perfil','agendamento','local_id',(select sbc from ids)));
select 'como agendamento: perfil=' || perfil || ' local=' || local_nome from minha_visualizacao;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) as sv1 from ids \gset
select 'solicitação criada pelo admin real: ' || (tecnico_id = '00000000-0000-0000-0000-00000000000a') || ' tipo=' || tipo from solicitacao where id=:sv1;
\set ON_ERROR_STOP off
\echo '--- como agendamento: registrar e criar pedido de transferência (devem falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',sbc,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select criar_pedido_transferencia(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on

\echo '--- admin vê como consulta: vê tudo, não escreve'
select definir_visualizacao('{"perfil":"consulta"}'::jsonb);
select 'como consulta: perfil=' || perfil || ' locais no saldo=' || (select count(distinct local_id) from saldo) from minha_visualizacao;
\set ON_ERROR_STOP off
\echo '--- como consulta: registrar, criar solicitação, criar pedido e aceitar (devem falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select criar_solicitacao(jsonb_build_object('finalidade','manutencao','tipo','enviar_cliente','origem_id',sbc,'unidade_id',u1,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select criar_pedido_transferencia(jsonb_build_object('origem_id',sbc,'destino_id',nl,'itens',jsonb_build_array(jsonb_build_object('produto_id',:bz,'quantidade',1)))) from ids;
select aceitar_solicitacao(:pv1);
\set ON_ERROR_STOP on

\echo '--- admin vê como o técnico Ze PJ (sem login): vê só o estoque dele; a base vira o local'
select definir_visualizacao(jsonb_build_object('perfil','tecnico','tecnico_id',(select id from tecnico where nome='Ze PJ')));
select 'como técnico: perfil=' || perfil || ' técnico=' || tecnico_nome || ' local (base)=' || local_nome || ' locais no saldo=' || coalesce((select string_agg(distinct l.nome, ',') from saldo s join local l on l.id=s.local_id), '-') from minha_visualizacao;
\set ON_ERROR_STOP off
\echo '--- como técnico: consumo interno e saída do estoque do NL (devem falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','CONSUMO_INTERNO','local_id',(select id from local where nome='Estoque Ze PJ'),'itens',jsonb_build_array(jsonb_build_object('produto_id',(select chi from ids),'quantidade',1))));
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',nl,'unidade_id',u2,'itens',jsonb_build_array(jsonb_build_object('produto_id',chi,'quantidade',1)))) from ids;
\set ON_ERROR_STOP on
\echo '--- como técnico: entrega todo o dedicado da Mineração que está com ele (o técnico da saída é o Ze PJ)'
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',(select id from local where nome='Estoque Ze PJ'),'unidade_id',(select u2 from ids),
  'itens',(select jsonb_agg(jsonb_build_object('produto_id',produto_id,'condicao',condicao,'quantidade',quantidade,'reservado_unidade_id',reservado_unidade_id))
             from saldo where local_id=(select id from local where nome='Estoque Ze PJ') and reservado_unidade_id=(select u2 from ids) and quantidade > 0))) as mvt \gset
select 'saída do técnico simulado: técnico=' || t.nome || ' modo=' || m.modo_envio::text || ' criado_por admin=' || (m.criado_por = '00000000-0000-0000-0000-00000000000a') from movimentacao m join tecnico t on t.id=m.tecnico_id where m.id=:mvt;

\echo '--- voltar a administrador (com null) funciona simulando; a auditoria grava o usuário real'
select definir_visualizacao('{"perfil":null}'::jsonb);
select 'voltou: perfil=' || perfil || ' simulando=' || simulando || ' locais_operaveis=' || cardinality(locais_operaveis) from minha_visualizacao;
select 'auditoria Ver como com o admin real: ' || count(*) from auditoria where acao='VER_COMO' and usuario_id='00000000-0000-0000-0000-00000000000a';
select definir_visualizacao(jsonb_build_object('perfil','operador','local_id',(select nl from ids)));
select definir_visualizacao('{}'::jsonb);
select 'voltar com objeto vazio: perfil=' || fn_perfil() || ' opera SBC=' || fn_pode_operar_local((select sbc from ids));
\set ON_ERROR_STOP off
\echo '--- funções internas do Ver como pela API (devem falhar: permissão negada)'
select fn_perfil_real();
select fn_tecnico_atual();
\set ON_ERROR_STOP on

\echo '--- 21. Chip ruim: descartar o Claro e pegar outro Claro (módulo continua Claro; avulso Claro -1)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select (select id from local where nome='Nova Lima') as nl3, (select id from produto where nome='Módulo FMC 150') as fm3, (select id from produto where nome='Chip Claro M2M') as chc3 \gset
select 'antes: modulos claro=' || (select sum(quantidade) from saldo where local_id=:nl3 and produto_id=:fm3 and condicao='claro') || ' avulso Claro=' || (select sum(quantidade) from saldo where local_id=:nl3 and produto_id=:chc3);
select trocar_chip(jsonb_build_object('local_id',:nl3,'produto_id',:fm3,'quantidade',1,'de','claro','para','claro','chip_retirado','descartar','observacao','não conectou na produção')) is not null;
select 'depois: modulos claro=' || (select sum(quantidade) from saldo where local_id=:nl3 and produto_id=:fm3 and condicao='claro') || ' avulso Claro=' || (select sum(quantidade) from saldo where local_id=:nl3 and produto_id=:chc3);
\set ON_ERROR_STOP off
\echo '--- mesmo chip sem descartar (deve falhar)'
select trocar_chip(jsonb_build_object('local_id',:nl3,'produto_id',:fm3,'quantidade',1,'de','claro','para','claro')) is not null;
\set ON_ERROR_STOP on
\echo '--- 22. Arqia: entrada de chip Arqia avulso e instalação em módulo sem chip'
select (select id from produto where nome='Chip Arqia M2M') as cha \gset
select registrar_movimentacao(jsonb_build_object('tipo','ENTRADA_COMPRA','local_id',:nl3,'itens',jsonb_build_array(jsonb_build_object('produto_id',:cha,'quantidade',2)))) is not null;
select trocar_chip(jsonb_build_object('local_id',:nl3,'produto_id',:fm3,'quantidade',2,'de','novo','para','arqia')) is not null;
select 'arqia: modulos=' || (select sum(quantidade) from saldo where local_id=:nl3 and produto_id=:fm3 and condicao='arqia') || ' chip avulso Arqia=' || (select coalesce(sum(quantidade),0) from saldo where local_id=:nl3 and produto_id=:cha);
\echo '--- 23. Admin: envio para estoque técnico, registrar transferência, troca de chips entre equipamentos, solicitação'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select definir_visualizacao(jsonb_build_object('perfil','admin'));
select (select id from local where nome='Nova Lima') as n23, (select id from local where nome like 'São%') as s23,
       (select id from tecnico where nome='Ze PJ') as ze23, (select id from local where nome='Estoque Ze PJ') as zel23,
       (select id from produto where nome='Módulo FMC 130') as pa23, (select id from produto where nome='Módulo ECO 5') as pb23,
       (select id from produto where nome='DashCAM') as dc23, (select id from produto where nome='Cabo rede') as cr23,
       (select id from unidade_cliente where nome='Ouro Branco') as u23 \gset
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',:n23,'observacao','carga do cenário 23','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:pa23,'condicao','vivo','quantidade',4), jsonb_build_object('produto_id',:pb23,'condicao','claro','quantidade',4),
  jsonb_build_object('produto_id',:dc23,'condicao','novo','quantidade',2), jsonb_build_object('produto_id',:cr23,'quantidade',10)))) is not null;
\set ON_ERROR_STOP off
\echo '--- envio para estoque técnico sem modo de envio (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENVIO_TECNICO','local_id',:n23,'tecnico_id',:ze23,'itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',2))));
\echo '--- envio para estoque técnico sem técnico (deve falhar)'
select registrar_movimentacao(jsonb_build_object('tipo','ENVIO_TECNICO','local_id',:n23,'modo_envio','retirada','itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',2))));
\set ON_ERROR_STOP on
\echo '--- envio para estoque técnico ok: entra na hora no estoque do Ze PJ'
select registrar_movimentacao(jsonb_build_object('tipo','ENVIO_TECNICO','local_id',:n23,'tecnico_id',:ze23,'modo_envio','retirada','itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',2)))) as env23 \gset
select 'envio técnico: status=' || (select status from movimentacao where id=:env23) || ' Ze cabo rede=' || (select sum(quantidade) from saldo where local_id=:zel23 and produto_id=:cr23);
\set ON_ERROR_STOP off
\echo '--- registrar transferência sem modo de envio (deve falhar)'
select registrar_transferencia(jsonb_build_object('origem_id',:n23,'destino_id',:s23,'itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',3))));
\set ON_ERROR_STOP on
\echo '--- registrar transferência ok (em trânsito, com chamado); SBC confirma'
select registrar_transferencia(jsonb_build_object('origem_id',:n23,'destino_id',:s23,'modo_envio','transportadora','chamado_url','https://jira/HW-1','itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',3)))) as tr23 \gset
select 'transferência: ' || status || ' chamado=' || chamado_url from movimentacao where id=:tr23;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b2',false) \gset
select confirmar_recebimento(:tr23);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select 'SBC cabo rede=' || (select sum(quantidade) from saldo where local_id=:s23 and produto_id=:cr23);
\set ON_ERROR_STOP off
\echo '--- técnico registra transferência (deve falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000c1',false) \gset
select registrar_transferencia(jsonb_build_object('origem_id',:n23,'destino_id',:s23,'modo_envio','correios','itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',1))));
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
\echo '--- trocar chips entre módulo (M2M) e DashCAM (Voz e Dados) (deve falhar)'
select trocar_chips_entre(jsonb_build_object('local_id',:n23,'produto_a_id',:pa23,'chip_a','vivo','produto_b_id',:dc23,'chip_b','novo','quantidade',1));
\echo '--- trocar chips entre equipamentos com mais do que há (deve falhar)'
select trocar_chips_entre(jsonb_build_object('local_id',:n23,'produto_a_id',:pa23,'chip_a','vivo','produto_b_id',:pb23,'chip_b','claro','quantidade',9));
\set ON_ERROR_STOP on
\echo '--- trocar chips: 3 FMC 130 Vivo <-> 3 ECO 5 Claro'
select trocar_chips_entre(jsonb_build_object('local_id',:n23,'produto_a_id',:pa23,'chip_a','vivo','produto_b_id',:pb23,'chip_b','claro','quantidade',3)) is not null;
select 'FMC130 claro=' || (select sum(quantidade) from saldo where local_id=:n23 and produto_id=:pa23 and condicao='claro') ||
       ' vivo=' || (select sum(quantidade) from saldo where local_id=:n23 and produto_id=:pa23 and condicao='vivo') ||
       ' ECO5 vivo=' || (select sum(quantidade) from saldo where local_id=:n23 and produto_id=:pb23 and condicao='vivo');
\set ON_ERROR_STOP off
\echo '--- admin cria solicitação sem finalidade (deve falhar)'
select criar_solicitacao(jsonb_build_object('tipo','enviar_cliente','origem_id',:n23,'unidade_id',:u23,'itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',1))));
\set ON_ERROR_STOP on
\echo '--- admin cria solicitação (ok) e cancela'
select criar_solicitacao(jsonb_build_object('finalidade','mobilizacao','tipo','enviar_cliente','origem_id',:n23,'unidade_id',:u23,'itens',jsonb_build_array(jsonb_build_object('produto_id',:cr23,'quantidade',1)))) as sol23 \gset
select cancelar_solicitacao(:sol23);
select 'solicitação do admin: ' || status || ' finalidade=' || finalidade from solicitacao where id=:sol23;

\echo '--- 24. Admin exclui item, cliente e unidade (excluído x desativado)'
insert into produto (nome) values ('Item Teste Livre');
insert into cliente (nome) values ('Cliente Teste Livre');
insert into unidade_cliente (cliente_id, nome) select id, 'Unidade Livre' from cliente where nome = 'Cliente Teste Livre';
insert into unidade_cliente (cliente_id, nome) select id, 'Unidade Livre 2' from cliente where nome = 'Gerdau';
\set ON_ERROR_STOP off
\echo '--- item com nome repetido em outra caixa (deve falhar)'
insert into produto (nome) values ('item teste livre');
\echo '--- operador exclui item, cliente e unidade (devem falhar)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
select excluir_item((select id from produto where nome='Item Teste Livre'));
select excluir_cliente((select id from cliente where nome='Cliente Teste Livre'));
select excluir_unidade((select id from unidade_cliente where nome='Unidade Livre 2'));
\set ON_ERROR_STOP on
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
select 'item livre: ' || excluir_item((select id from produto where nome='Item Teste Livre')) ||
       ' | item com histórico: ' || excluir_item(:cr23) ||
       ' | unidade livre: ' || excluir_unidade((select id from unidade_cliente where nome='Unidade Livre 2')) ||
       ' | unidade com histórico: ' || excluir_unidade(:u23) ||
       ' | cliente livre: ' || excluir_cliente((select id from cliente where nome='Cliente Teste Livre')) ||
       ' | cliente com histórico: ' || excluir_cliente((select id from cliente where nome='CSN'));
select 'ativos: cabo rede=' || (select ativo from produto where id=:cr23) || ' Ouro Branco=' || (select ativo from unidade_cliente where id=:u23) ||
       ' CSN=' || (select ativo from cliente where nome='CSN') || ' unidades CSN ativas=' || (select count(*) from unidade_cliente u join cliente c on c.id=u.cliente_id where c.nome='CSN' and u.ativo);

\echo '--- 25. Kits (item_associado)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
create temp view v_kit as
  select p.nome as prod, a.nome as assoc, ia.quantidade, ia.opcional, ia.grupo
    from item_associado ia join produto p on p.id = ia.produto_id join produto a on a.id = ia.associado_id;
grant select on v_kit to authenticated;
select 'kit FMC 650 ok: ' || ((select string_agg(assoc, ',' order by assoc) from v_kit where prod='Módulo FMC 650') = 'Antena GPS,Antena GSM Femea,Chicote FMC650');
select 'kit Galileo ok: ' || ((select string_agg(assoc || case when opcional then '(opc)' else '' end, ',' order by assoc) from v_kit where prod='Módulo Galileo 7x / 10HUB')
                              = 'Antena GPS,Antena GSM Macho,Antena Wifi(opc),Chicote Galileo 7x / 10HUB');
select 'kit MDVR 3404 ok: ' || ((select string_agg(assoc || case when opcional then '(opc)' else '' end, ',' order by assoc) from v_kit where prod='MDVR 3404')
                              = 'Antena GPS,Antena GSM Macho,Antena Wifi(opc),Chicote MDVR');
select 'kit MDVR 5404 sem chicote ok: ' || ((select string_agg(assoc || case when opcional then '(opc)' else '' end, ',' order by assoc) from v_kit where prod='MDVR 5404')
                              = 'Antena GPS,Antena GSM Macho,Antena Wifi(opc)');
select 'kit DashCAM ok: ' || ((select string_agg(assoc, ',') from v_kit where prod='DashCAM') = 'Chicote DashCAM');
select 'kit ECO 5 só chicote ok: ' || ((select string_agg(assoc, ',') from v_kit where prod='Módulo ECO 5') = 'Chicote ECO 5');
select 'câmeras ok: ' || ((select count(*) from v_kit where prod in ('Camera contexto DVR','Camera Fadiga DVR','Camera frontal (Adas) DVR') and assoc='Extensão cameras') = 3
                       and (select count(*) from v_kit where prod in ('Camera Contexto DashCAM','Camera Fadiga DashCAM','Camera frontal (Adas) DashCAM') and assoc='Extensão cameras DashCAM') = 3
                       and (select string_agg(assoc, ',') from v_kit where prod='Camera IP') = 'Cabo rede');
select 'tablets ok: ' || ((select count(*) from v_kit where prod in ('Tablet Samsung','Tablet Multilaser') and grupo is null
                            and assoc in ('Suporte Tablet','Carregador DC/DC 12V Tablet Roboflex')) = 4
                       and (select count(*) from v_kit where prod in ('Tablet Samsung','Tablet Multilaser') and grupo='Case'
                            and assoc in ('Case Tablet 4 pinos','Case Tablet 10 pinos','Case Tablet Tipo C')) = 6
                       and (select count(*) from v_kit where prod in ('Tablet Samsung','Tablet Multilaser')) = 10);
select 'plug segue a case ok: ' || ((select string_agg(assoc, ',') from v_kit where prod='Case Tablet 4 pinos') = 'Plug Carregador Tablet 4 pinos'
                                 and (select string_agg(assoc, ',') from v_kit where prod='Case Tablet 10 pinos') = 'Plug Carregador Tablet 10 pinos'
                                 and not exists (select 1 from v_kit where prod='Case Tablet Tipo C'));
select (select id from produto where nome='Buzzer') as kbz, (select id from produto where nome='Relé Finder') as krf \gset

\set ON_ERROR_STOP off
\echo '--- operador insere linha em item_associado (deve falhar: RLS)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
insert into item_associado (produto_id, associado_id, quantidade) values (:kbz, :krf, 1);
\echo '--- consulta insere linha em item_associado (deve falhar: RLS)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
insert into item_associado (produto_id, associado_id, quantidade) values (:kbz, :krf, 1);
\set ON_ERROR_STOP on
\echo '--- admin insere, altera opcional/grupo e apaga uma linha de teste; operador e consulta não alteram nem apagam (0 linhas)'
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
insert into item_associado (produto_id, associado_id, quantidade) values (:kbz, :krf, 1);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000b1',false) \gset
with x as (update item_associado set opcional = true where produto_id = :kbz returning 1) select 'operador alterou ' || count(*) || ' linhas' from x;
with x as (delete from item_associado where produto_id = :kbz returning 1) select 'operador apagou ' || count(*) || ' linhas' from x;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-0000000000d1',false) \gset
with x as (update item_associado set grupo = 'X' where produto_id = :kbz returning 1) select 'consulta alterou ' || count(*) || ' linhas' from x;
with x as (delete from item_associado where produto_id = :kbz returning 1) select 'consulta apagou ' || count(*) || ' linhas' from x;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-00000000000a',false) \gset
update item_associado set opcional = true, grupo = 'Teste' where produto_id = :kbz and associado_id = :krf;
select 'admin alterou ok: ' || exists (select 1 from item_associado where produto_id = :kbz and associado_id = :krf and opcional and grupo = 'Teste');
delete from item_associado where produto_id = :kbz and associado_id = :krf;
select 'admin apagou ok: ' || not exists (select 1 from item_associado where produto_id = :kbz);

\echo '--- saída com os periféricos em linhas próprias (módulo + chicote + antenas) baixa cada saldo'
insert into cliente (nome) values ('Cliente Kit');
insert into unidade_cliente (cliente_id, nome) select id, 'Unidade Kit' from cliente where nome = 'Cliente Kit';
select (select id from unidade_cliente where nome='Unidade Kit') as uk, (select id from produto where nome='Módulo FMC 650') as km,
       (select id from produto where nome='Chicote FMC650') as kc, (select id from produto where nome='Antena GPS') as kg,
       (select id from produto where nome='Antena GSM Femea') as kf \gset
create temp table antes_kit as
  select produto_id, coalesce(sum(quantidade), 0) q from saldo
   where local_id = :n23 and reservado_unidade_id is null and condicao = 'novo' and produto_id in (:km, :kc, :kg, :kf) group by 1;
select registrar_movimentacao(jsonb_build_object('tipo','AJUSTE','local_id',:n23,'observacao','carga kits','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:km,'quantidade',5), jsonb_build_object('produto_id',:kc,'quantidade',5),
  jsonb_build_object('produto_id',:kg,'quantidade',5), jsonb_build_object('produto_id',:kf,'quantidade',5)))) is not null;
select registrar_movimentacao(jsonb_build_object('tipo','SAIDA_CLIENTE','local_id',:n23,'unidade_id',:uk,'modo_envio','correios','finalidade','mobilizacao','itens',jsonb_build_array(
  jsonb_build_object('produto_id',:km,'quantidade',2), jsonb_build_object('produto_id',:kc,'quantidade',2),
  jsonb_build_object('produto_id',:kg,'quantidade',2), jsonb_build_object('produto_id',:kf,'quantidade',2)))) is not null;
select 'saída com kit ok: ' || bool_and(coalesce(d.q,0) - coalesce(a.q,0) = 3)
  from (select unnest(array[:km, :kc, :kg, :kf]) pid) p
  left join antes_kit a on a.produto_id = p.pid
  left join (select produto_id, sum(quantidade) q from saldo where local_id = :n23 and reservado_unidade_id is null and condicao = 'novo'
              group by 1) d on d.produto_id = p.pid;

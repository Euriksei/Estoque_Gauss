-- Atualização: fecha as funções internas do banco para quem usa o app.
-- Rode uma vez, depois de atualizar_catalogo.sql. Pode rodar de novo a qualquer momento, mesmo depois das
-- atualizações seguintes: ele sempre aplica a lista FINAL de funções liberadas (só as que já existem no banco).
--
-- Por quê: no Supabase, toda função criada no schema public já nasce com permissão de execução
-- para os papéis anon e authenticated. O banco tirava a permissão só de public e anon, então um
-- usuário logado conseguia chamar pela API funções internas como fn_gravar_itens, que grava itens
-- em qualquer movimentação sem conferir o local nem o saldo (ex.: um operador de Nova Lima tirando
-- itens do SBC). Agora só as funções que o app chama (e as que as regras de segurança usam) ficam
-- liberadas para usuários logados; as internas rodam apenas por dentro dessas funções.

begin;

revoke execute on all functions in schema public from public, anon, authenticated;

-- Lista final das funções liberadas para usuário logado. Funções que ainda não existem (atualizações
-- seguintes não rodadas) são puladas. criar_transferencia só fica liberada enquanto o fluxo de pedidos
-- (atualizar_fluxo_pedidos.sql) não foi instalado; depois dele ela é interna.
do $$
declare
  f text;
  lista text[] := array[
    -- usadas pelas regras de segurança (RLS), pelas views e pelas telas
    'public.fn_perfil()', 'public.fn_pode_ver_local(integer)', 'public.fn_pode_operar_local(integer)',
    'public.fn_rotulo_chip(text)', 'public.fn_hoje()', 'public.fn_local_responsavel(public.solicitacao)',
    'public.fn_pode_cancelar(public.solicitacao)', 'public.definir_visualizacao(jsonb)',
    -- chamadas pelo app
    'public.registrar_movimentacao(jsonb)', 'public.confirmar_recebimento(bigint)',
    'public.cancelar_transferencia(bigint,text)', 'public.estornar_movimentacao(bigint,text)',
    'public.criar_pedido_transferencia(jsonb)', 'public.criar_solicitacao(jsonb)', 'public.aceitar_solicitacao(bigint)',
    'public.atender_solicitacao(bigint,jsonb)', 'public.cancelar_solicitacao(bigint)', 'public.trocar_chip(jsonb)'];
begin
  if to_regprocedure('public.criar_pedido_transferencia(jsonb)') is null then
    lista := lista || 'public.criar_transferencia(jsonb)'::text;
  end if;
  foreach f in array lista loop
    if to_regprocedure(f) is not null then
      execute 'grant execute on function ' || to_regprocedure(f)::regprocedure::text || ' to authenticated';
    end if;
  end loop;
end $$;

-- Conferência: as funções internas não podem ficar liberadas para usuário logado nem anônimo.
do $$ declare v text; begin
  select string_agg(p.proname, ', ') into v
    from pg_proc p
   where p.pronamespace = 'public'::regnamespace
     and (p.proname in ('fn_gravar_itens', 'fn_verificar_saldo', 'fn_travar_locais', 'fn_auditar', 'fn_novo_usuario',
                        'fn_data_movimento', 'fn_verificar_dedicado_inteiro', 'fn_itens_dedicado', 'fn_nome_unidade',
                        'fn_gravar_itens_pedido', 'fn_perfil_real', 'fn_simulacao', 'fn_tecnico_atual', 'fn_local_do_usuario')
          or (p.proname = 'criar_transferencia' and to_regprocedure('public.criar_pedido_transferencia(jsonb)') is not null))
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
  if v is not null then raise exception 'Funções internas ainda liberadas: %', v; end if;
end $$;

commit;

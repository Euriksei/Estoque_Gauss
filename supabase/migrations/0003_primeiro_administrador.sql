-- Migração 0003: o primeiro cadastro do sistema vira administrador ativo; os seguintes entram inativos
-- como "consulta" até um administrador liberar. Também cria a linha de usuário para contas que já existiam
-- no login do Supabase sem registro na tabela (backfill).

create or replace function public.fn_novo_usuario() returns trigger
language plpgsql security definer set search_path = public as $$
declare primeiro boolean;
begin
  -- Trava para dois cadastros simultâneos não virarem ambos administradores.
  perform pg_advisory_xact_lock(hashtext('primeiro_administrador'));
  select not exists (select 1 from usuario) into primeiro;
  insert into usuario (id, nome, email, perfil, ativo)
  values (new.id, coalesce(new.raw_user_meta_data->>'nome', split_part(new.email, '@', 1)), new.email,
          case when primeiro then 'admin'::perfil_acesso else 'consulta'::perfil_acesso end,
          primeiro)
  on conflict (id) do nothing;
  return new;
end $$;

-- Contas que existem no login mas não na tabela: a mais antiga vira administrador se ainda não houver nenhum.
insert into usuario (id, nome, email, perfil, ativo)
select u.id, coalesce(u.raw_user_meta_data->>'nome', split_part(u.email, '@', 1)), u.email,
       case when not exists (select 1 from usuario where perfil = 'admin') and
                 u.id = (select id from auth.users order by created_at limit 1)
            then 'admin'::perfil_acesso else 'consulta'::perfil_acesso end,
       not exists (select 1 from usuario where perfil = 'admin') and
                 u.id = (select id from auth.users order by created_at limit 1)
from auth.users u
where not exists (select 1 from usuario x where x.id = u.id);

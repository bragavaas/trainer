-- ============================================================
-- TRAINER · schema inicial
-- Rodar no SQL Editor do projeto Supabase "Trainer".
-- Idempotente: pode rodar de novo sem quebrar.
-- ============================================================

create extension if not exists pgcrypto;

-- ------------------------------------------------------------
-- 1. TABELAS
-- ------------------------------------------------------------

create table if not exists public.config (
  user_id           uuid primary key references auth.users(id) on delete cascade,
  quinta_referencia date not null default '2026-09-17',
  peso_corporal     numeric(5,1) not null default 116.5,
  updated_at        timestamptz not null default now()
);

create table if not exists public.treinos (
  user_id   uuid not null references auth.users(id) on delete cascade,
  id        text not null,                       -- 'A', 'B', 'C'
  descricao text not null default '',
  ordem     smallint not null default 0,
  primary key (user_id, id)
);

create table if not exists public.exercicios (
  id        uuid primary key default gen_random_uuid(),
  user_id   uuid not null references auth.users(id) on delete cascade,
  treino_id text not null,
  nome      text not null,
  series    smallint not null default 3 check (series between 1 and 10),
  assistido boolean not null default false,       -- gravitron: carga = peso - assistencia
  ordem     smallint not null default 0,
  ativo     boolean not null default true,
  foreign key (user_id, treino_id) references public.treinos(user_id, id) on delete cascade,
  unique (user_id, treino_id, nome)
);

create table if not exists public.sessoes (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  data         date not null,
  treino_id    text not null,
  com_quem     text not null default 'Sozinho'
               check (com_quem in ('Sozinho','Com MM','Com Motta','Tropa reunida')),
  obs          text not null default '',
  interrompida boolean not null default false,
  motivo       text not null default '',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  foreign key (user_id, treino_id) references public.treinos(user_id, id)
);
create index if not exists sessoes_user_data_idx on public.sessoes (user_id, data desc);

create table if not exists public.series (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  sessao_id   uuid not null references public.sessoes(id) on delete cascade,
  exercicio   text not null,                      -- nome no momento (templates mudam)
  ordem       smallint not null default 0,        -- ordem do exercicio na sessao
  numero      smallint not null,                  -- numero da serie dentro do exercicio
  carga       numeric(6,2) not null check (carga >= 0),
  reps        smallint not null check (reps >= 0),
  rir         smallint not null check (rir between 0 and 5),
  assistencia numeric(6,2),                       -- so para exercicios assistidos
  unique (sessao_id, exercicio, numero)
);
create index if not exists series_user_idx on public.series (user_id);

create table if not exists public.cardio (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  data         date not null,
  modalidade   text not null check (modalidade in
               ('esteira-caminhada','esteira-inclinada','esteira-corrida','bike','rua-caminhada','rua-corrida')),
  tempo_min    smallint not null check (tempo_min > 0),
  distancia_km numeric(5,2),
  inclinacao   numeric(4,1) not null default 0,
  obs          text not null default '',
  created_at   timestamptz not null default now()
);
create index if not exists cardio_user_data_idx on public.cardio (user_id, data desc);

create table if not exists public.diario (
  user_id uuid not null references auth.users(id) on delete cascade,
  data    date not null,
  passos  integer check (passos >= 0),
  peso    numeric(5,1) check (peso > 0),
  updated_at timestamptz not null default now(),
  primary key (user_id, data)
);

-- ------------------------------------------------------------
-- 2. RLS: cada usuario so ve e escreve o que e dele
-- ------------------------------------------------------------

alter table public.config     enable row level security;
alter table public.treinos    enable row level security;
alter table public.exercicios enable row level security;
alter table public.sessoes    enable row level security;
alter table public.series     enable row level security;
alter table public.cardio     enable row level security;
alter table public.diario     enable row level security;

do $$
declare t text;
begin
  foreach t in array array['config','treinos','exercicios','sessoes','series','cardio','diario'] loop
    execute format('drop policy if exists %I_own on public.%I', t, t);
    execute format(
      'create policy %I_own on public.%I for all to authenticated
         using (user_id = auth.uid()) with check (user_id = auth.uid())', t, t);
  end loop;
end $$;

-- ------------------------------------------------------------
-- 3. updated_at automatico
-- ------------------------------------------------------------

create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end $$;

drop trigger if exists sessoes_touch on public.sessoes;
create trigger sessoes_touch before update on public.sessoes
  for each row execute function public.touch_updated_at();

drop trigger if exists config_touch on public.config;
create trigger config_touch before update on public.config
  for each row execute function public.touch_updated_at();

drop trigger if exists diario_touch on public.diario;
create trigger diario_touch before update on public.diario
  for each row execute function public.touch_updated_at();

-- ------------------------------------------------------------
-- 4. SEED por usuario: roda quando a conta e criada
-- ------------------------------------------------------------

create or replace function public.seed_novo_usuario()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.config (user_id) values (new.id) on conflict do nothing;

  insert into public.treinos (user_id, id, descricao, ordem) values
    (new.id, 'A', 'Peito e tríceps', 1),
    (new.id, 'B', 'Costas e bíceps', 2),
    (new.id, 'C', 'Pernas',          3)
  on conflict do nothing;

  insert into public.exercicios (user_id, treino_id, nome, series, assistido, ordem) values
    (new.id, 'A', 'Supino reto barra',               3, false, 1),
    (new.id, 'A', 'Supino inclinado halter',         3, false, 2),
    (new.id, 'A', 'Cross polia alta',                3, false, 3),
    (new.id, 'A', 'Tríceps corda',                   3, false, 4),
    (new.id, 'A', 'Tríceps kickback',                3, false, 5),
    (new.id, 'B', 'Puxada alta anatômico',           3, false, 1),
    (new.id, 'B', 'Pull up gravitron',               3, true,  2),
    (new.id, 'B', 'Remada máquina unilateral',       3, false, 3),
    (new.id, 'B', 'Rosca barra W',                   3, false, 4),
    (new.id, 'B', 'Rosca scott martelo',             3, false, 5),
    (new.id, 'B', 'Rosca banco inclinado 45 halter', 3, false, 6),
    (new.id, 'C', 'Leg press',                       4, false, 1),
    (new.id, 'C', 'Agachamento livre',               4, false, 2),
    (new.id, 'C', 'Cadeira flexora unilateral',      3, false, 3),
    (new.id, 'C', 'Stiff',                           4, false, 4),
    (new.id, 'C', 'Mesa flexora',                    4, false, 5)
  on conflict do nothing;

  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.seed_novo_usuario();

-- ------------------------------------------------------------
-- 5. VIEWS de analise (herdam o RLS das tabelas base)
-- ------------------------------------------------------------

-- D+N por data: (data - quinta_referencia) mod 7
-- 0=quinta 1=sexta 2=sabado 3=domingo 4=segunda 5=terca 6=quarta
create or replace view public.v_sessoes with (security_invoker = true) as
select
  s.id, s.user_id, s.data, s.treino_id, s.com_quem, s.interrompida, s.motivo, s.obs,
  ((s.data - c.quinta_referencia) % 7 + 7) % 7               as d_plus_n,
  (array['Quinta','Sexta','Sábado','Domingo','Segunda','Terça','Quarta'])
    [((s.data - c.quinta_referencia) % 7 + 7) % 7 + 1]      as dia_aplicacao,
  extract(isoyear from s.data)::int                         as iso_ano,
  extract(week    from s.data)::int                         as iso_semana,
  date_trunc('week', s.data)::date                          as semana_inicio,
  count(r.id)                                               as n_series,
  coalesce(sum(r.carga * r.reps), 0)                        as volume_carga,
  round(avg(r.rir), 2)                                      as rir_medio,
  round(avg(r.carga * r.reps), 1)                           as volume_por_serie
from public.sessoes s
join public.config c on c.user_id = s.user_id
left join public.series r on r.sessao_id = s.id
group by s.id, c.quinta_referencia;

create or replace view public.v_semanas with (security_invoker = true) as
select
  user_id, semana_inicio, iso_ano, iso_semana,
  count(*)                                                  as sessoes,
  sum(n_series)                                             as series,
  sum(volume_carga)                                         as volume_total,
  sum(volume_carga) filter (where treino_id = 'A')          as vol_a,
  sum(volume_carga) filter (where treino_id = 'B')          as vol_b,
  sum(volume_carga) filter (where treino_id = 'C')          as vol_c,
  round(avg(rir_medio), 2)                                  as rir_medio,
  count(*) filter (where interrompida)                      as interrompidas
from public.v_sessoes
group by user_id, semana_inicio, iso_ano, iso_semana;

create or replace view public.v_por_dn with (security_invoker = true) as
select
  v.user_id, v.d_plus_n, v.dia_aplicacao,
  count(r.id)                                               as series,
  round(avg(r.carga * r.reps), 1)                           as volume_por_serie,
  round(avg(r.rir), 2)                                      as rir_medio
from public.v_sessoes v
join public.series r on r.sessao_id = v.id
group by v.user_id, v.d_plus_n, v.dia_aplicacao;

create or replace view public.v_por_exercicio with (security_invoker = true) as
select
  s.user_id, s.data, s.treino_id, s.com_quem, r.exercicio,
  count(*)                                                  as series,
  max(r.carga)                                              as carga_max,
  sum(r.carga * r.reps)                                     as volume,
  round(avg(r.rir), 2)                                      as rir_medio
from public.sessoes s
join public.series r on r.sessao_id = s.id
group by s.user_id, s.data, s.treino_id, s.com_quem, r.exercicio;

create or replace view public.v_por_companhia with (security_invoker = true) as
select
  user_id, com_quem, treino_id,
  count(*)                                                  as sessoes,
  round(avg(volume_carga), 0)                               as volume_medio,
  round(avg(rir_medio), 2)                                  as rir_medio
from public.v_sessoes
group by user_id, com_quem, treino_id;

-- ------------------------------------------------------------
-- 6. Views expostas via API para o usuario autenticado
-- ------------------------------------------------------------
grant select on public.v_sessoes, public.v_semanas, public.v_por_dn,
                public.v_por_exercicio, public.v_por_companhia to authenticated;

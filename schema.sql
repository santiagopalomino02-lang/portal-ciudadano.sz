-- Portal Ciudadano del Reino de Sanza
-- Ejecuta este archivo completo en Supabase > SQL Editor > New query.

create type public.app_role as enum ('citizen', 'admin');
create type public.procedure_status as enum ('pending', 'in_review', 'approved', 'rejected', 'additional_documents');
create type public.payment_status as enum ('pending', 'paid', 'late');
create type public.civic_type as enum ('survey', 'referendum', 'plebiscite');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  cui text unique not null,
  full_name text not null,
  role public.app_role not null default 'citizen',
  citizenship_type text default 'Ciudadano Permanente',
  birth_date date,
  contact_email text,
  phone text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, cui, full_name, contact_email)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'cui', split_part(new.email, '@', 1)),
    coalesce(new.raw_user_meta_data ->> 'full_name', 'Ciudadano sin nombre'),
    new.raw_user_meta_data ->> 'contact_email'
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users for each row execute procedure public.handle_new_user();

create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

create table public.procedures (
  id uuid primary key default gen_random_uuid(),
  citizen_id uuid not null references public.profiles(id) on delete cascade,
  procedure_type text not null,
  description text not null,
  contact_email text not null,
  contact_phone text,
  status public.procedure_status not null default 'pending',
  admin_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.documents (
  id uuid primary key default gen_random_uuid(),
  citizen_id uuid not null references public.profiles(id) on delete cascade,
  document_type text not null,
  document_number text,
  issued_at date,
  expires_at date,
  storage_path text,
  message text,
  status text not null default 'issued',
  created_at timestamptz not null default now()
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  citizen_id uuid not null references public.profiles(id) on delete cascade,
  concept text not null,
  payment_type text not null,
  amount numeric(12,2) not null check (amount >= 0),
  due_date date,
  status public.payment_status not null default 'pending',
  receipt_path text,
  paid_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  citizen_id uuid references public.profiles(id) on delete cascade,
  title text not null,
  message text not null,
  priority text not null default 'normal',
  sent_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table public.civic_activities (
  id uuid primary key default gen_random_uuid(),
  activity_type public.civic_type not null,
  title text not null,
  description text not null,
  closes_at timestamptz not null,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table public.civic_options (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.civic_activities(id) on delete cascade,
  option_text text not null,
  display_order smallint not null default 0
);

create table public.civic_votes (
  id uuid primary key default gen_random_uuid(),
  activity_id uuid not null references public.civic_activities(id) on delete cascade,
  option_id uuid not null references public.civic_options(id) on delete cascade,
  citizen_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(activity_id, citizen_id)
);

create table public.proposals (
  id uuid primary key default gen_random_uuid(),
  citizen_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  status text not null default 'received',
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;
alter table public.procedures enable row level security;
alter table public.documents enable row level security;
alter table public.payments enable row level security;
alter table public.notifications enable row level security;
alter table public.civic_activities enable row level security;
alter table public.civic_options enable row level security;
alter table public.civic_votes enable row level security;
alter table public.proposals enable row level security;

create policy "profiles: self or admin" on public.profiles for select to authenticated using (id = auth.uid() or public.is_admin());
create policy "profiles: admin manages" on public.profiles for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "procedures: citizen reads own or admin" on public.procedures for select to authenticated using (citizen_id = auth.uid() or public.is_admin());
create policy "procedures: citizen creates own" on public.procedures for insert to authenticated with check (citizen_id = auth.uid());
create policy "procedures: admin updates" on public.procedures for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "documents: citizen reads own or admin" on public.documents for select to authenticated using (citizen_id = auth.uid() or public.is_admin());
create policy "documents: admin manages" on public.documents for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "payments: citizen reads own or admin" on public.payments for select to authenticated using (citizen_id = auth.uid() or public.is_admin());
create policy "payments: admin manages" on public.payments for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "notifications: citizen reads own or global or admin" on public.notifications for select to authenticated using (citizen_id = auth.uid() or citizen_id is null or public.is_admin());
create policy "notifications: admin manages" on public.notifications for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "activities: authenticated reads" on public.civic_activities for select to authenticated using (true);
create policy "activities: admin manages" on public.civic_activities for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "options: authenticated reads" on public.civic_options for select to authenticated using (true);
create policy "options: admin manages" on public.civic_options for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy "votes: citizen reads own or admin" on public.civic_votes for select to authenticated using (citizen_id = auth.uid() or public.is_admin());
create policy "votes: citizen votes once" on public.civic_votes for insert to authenticated with check (citizen_id = auth.uid());
create policy "proposals: citizen reads own or admin" on public.proposals for select to authenticated using (citizen_id = auth.uid() or public.is_admin());
create policy "proposals: citizen creates own" on public.proposals for insert to authenticated with check (citizen_id = auth.uid());
create policy "proposals: admin updates" on public.proposals for update to authenticated using (public.is_admin()) with check (public.is_admin());

insert into storage.buckets (id, name, public) values ('citizen-documents', 'citizen-documents', false)
on conflict (id) do nothing;
create policy "storage: own documents or admin reads" on storage.objects for select to authenticated using (bucket_id = 'citizen-documents' and (owner_id = auth.uid()::text or public.is_admin()));
create policy "storage: authenticated uploads" on storage.objects for insert to authenticated with check (bucket_id = 'citizen-documents' and owner_id = auth.uid()::text);
create policy "storage: admin manages" on storage.objects for all to authenticated using (bucket_id = 'citizen-documents' and public.is_admin()) with check (bucket_id = 'citizen-documents' and public.is_admin());

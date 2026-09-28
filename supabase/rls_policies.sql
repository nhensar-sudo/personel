-- ============================================================================
-- Personel — Satır Bazlı Güvenlik (RLS) Politikaları (Faz 2 / Gün 9)
-- ============================================================================
-- Genel prensip:
--   - Görüntüleme (SELECT): herkese açık (giriş yapmadan da okunabilir) —
--     mevcut canlı uygulamanın davranışıyla tutarlı, "indirme herkese açık"
--     kuralını korur.
--   - Yazma (INSERT/UPDATE/DELETE): idareci sadece kendi kurumunda,
--     süper admin her kurumda, öğretmen hiçbir zaman.
--   - İstisna: nöbet & servis notları — herkes (öğretmen dahil) ekleyebilir,
--     ama SADECE ekleyen kişi silebilir.
--
-- Bu dosyayı schema.sql'den SONRA, SQL Editor'da çalıştırın.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Yardımcı fonksiyonlar
-- ----------------------------------------------------------------------------
create or replace function is_super_admin()
returns boolean as $$
  select coalesce((select rol from personel where auth_user_id = auth.uid()) = 'super_admin', false);
$$ language sql stable;

create or replace function my_kurum_id()
returns uuid as $$
  select kurum_id from personel where auth_user_id = auth.uid();
$$ language sql stable;

create or replace function is_idareci_or_admin()
returns boolean as $$
  select coalesce((select rol from personel where auth_user_id = auth.uid()) in ('idareci', 'super_admin'), false);
$$ language sql stable;

create or replace function can_write_kurum(target_kurum_id uuid)
returns boolean as $$
  select is_super_admin() or (is_idareci_or_admin() and target_kurum_id = my_kurum_id());
$$ language sql stable;

-- ----------------------------------------------------------------------------
-- KURUMLAR
-- ----------------------------------------------------------------------------
alter table kurumlar enable row level security;

create policy "kurumlar_herkes_okur" on kurumlar for select
  using (true);

create policy "kurumlar_sadece_super_admin_yazar" on kurumlar for all
  using (is_super_admin())
  with check (is_super_admin());

-- ----------------------------------------------------------------------------
-- PERSONEL
-- ----------------------------------------------------------------------------
alter table personel enable row level security;

-- Not: Giriş ekranı, kimlik doğrulamadan ÖNCE isimden e-posta üretmek için bu
-- tabloyu okur — bu yüzden SELECT herkese açık kalmalı (isimler zaten mevcut
-- uygulamada da herkese görünür durumda).
create policy "personel_herkes_okur" on personel for select
  using (true);

-- INSERT/UPDATE/DELETE yalnızca Edge Function'lar (service role) üzerinden
-- yapılır — burada bilerek hiçbir yazma politikası tanımlanmıyor, yani
-- normal (anon/authenticated) istemciler personel tablosuna asla yazamaz.

-- ----------------------------------------------------------------------------
-- DERS ADLARI
-- ----------------------------------------------------------------------------
alter table ders_adlari enable row level security;

create policy "ders_adlari_herkes_okur" on ders_adlari for select
  using (true);

create policy "ders_adlari_idareci_yazar" on ders_adlari for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

-- ----------------------------------------------------------------------------
-- DERS PROGRAMI
-- ----------------------------------------------------------------------------
alter table ders_programi enable row level security;

create policy "ders_programi_herkes_okur" on ders_programi for select
  using (true);

create policy "ders_programi_idareci_yazar" on ders_programi for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

-- ----------------------------------------------------------------------------
-- NÖBET ÇİZELGESİ
-- ----------------------------------------------------------------------------
alter table nobet_cizelgesi enable row level security;

create policy "nobet_herkes_okur" on nobet_cizelgesi for select
  using (true);

create policy "nobet_idareci_yazar" on nobet_cizelgesi for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

-- ----------------------------------------------------------------------------
-- RESMİ TATİLLER
-- ----------------------------------------------------------------------------
alter table resmi_tatiller enable row level security;

create policy "tatiller_herkes_okur" on resmi_tatiller for select
  using (true);

create policy "tatiller_idareci_yazar" on resmi_tatiller for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

-- ----------------------------------------------------------------------------
-- SINAVLAR
-- ----------------------------------------------------------------------------
alter table sinavlar enable row level security;

create policy "sinavlar_herkes_okur" on sinavlar for select
  using (true);

create policy "sinavlar_idareci_yazar" on sinavlar for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

-- ----------------------------------------------------------------------------
-- NÖBET & SERVİS NOT DEFTERİ — özel kural: herkes ekler, sadece ekleyen siler
-- ----------------------------------------------------------------------------
alter table notlar enable row level security;

create policy "notlar_herkes_okur" on notlar for select
  using (true);

create policy "notlar_giris_yapan_ekler" on notlar for insert
  with check (
    olusturan_id = (select id from personel where auth_user_id = auth.uid())
    and kurum_id = my_kurum_id()
  );

create policy "notlar_sadece_ekleyen_siler" on notlar for delete
  using (olusturan_id = (select id from personel where auth_user_id = auth.uid()));

-- ----------------------------------------------------------------------------
-- DUYURULAR
-- ----------------------------------------------------------------------------
alter table duyurular enable row level security;

create policy "duyurular_herkes_okur" on duyurular for select
  using (true);

create policy "duyurular_idareci_yazar" on duyurular for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

-- Duyuru okuma kaydı: herkes kendi okuma kaydını ekleyip görebilir
alter table duyuru_okumalar enable row level security;

create policy "duyuru_okuma_kendi_kaydi" on duyuru_okumalar for all
  using (personel_id = (select id from personel where auth_user_id = auth.uid()))
  with check (personel_id = (select id from personel where auth_user_id = auth.uid()));

-- ----------------------------------------------------------------------------
-- KURUL VE KOMİSYONLAR
-- ----------------------------------------------------------------------------
alter table kurullar enable row level security;

create policy "kurullar_herkes_okur" on kurullar for select
  using (true);

create policy "kurullar_idareci_yazar" on kurullar for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

alter table kurul_uyeleri enable row level security;

create policy "kurul_uyeleri_herkes_okur" on kurul_uyeleri for select
  using (true);

create policy "kurul_uyeleri_idareci_yazar" on kurul_uyeleri for all
  using (can_write_kurum((select kurum_id from kurullar where id = kurul_id)))
  with check (can_write_kurum((select kurum_id from kurullar where id = kurul_id)));

-- ----------------------------------------------------------------------------
-- BELİRLİ GÜN VE HAFTALAR
-- ----------------------------------------------------------------------------
alter table belirli_gunler enable row level security;

create policy "belirli_gunler_herkes_okur" on belirli_gunler for select
  using (true);

create policy "belirli_gunler_idareci_yazar" on belirli_gunler for all
  using (can_write_kurum(kurum_id))
  with check (can_write_kurum(kurum_id));

alter table belirli_gun_gorevlileri enable row level security;

create policy "belirli_gun_gorevlileri_herkes_okur" on belirli_gun_gorevlileri for select
  using (true);

create policy "belirli_gun_gorevlileri_idareci_yazar" on belirli_gun_gorevlileri for all
  using (can_write_kurum((select kurum_id from belirli_gunler where id = belirli_gun_id)))
  with check (can_write_kurum((select kurum_id from belirli_gunler where id = belirli_gun_id)));

-- ----------------------------------------------------------------------------
-- İŞLEM KAYDI (audit log) — yalnızca idareci/süper admin okuyabilir,
-- yazma istemciden değil, service role'den (Gün 11) yapılacak
-- ----------------------------------------------------------------------------
alter table islem_kayitlari enable row level security;

create policy "islem_kayitlari_idareci_okur" on islem_kayitlari for select
  using (is_super_admin() or (is_idareci_or_admin() and kurum_id = my_kurum_id()));

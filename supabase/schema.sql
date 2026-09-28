-- ============================================================================
-- Personel — Veritabanı Şeması (Faz 2 / Gün 4)
-- ============================================================================
-- Çok kurumlu (multi-tenant) yapı: her tablo kurum_id taşır, veriler kurum
-- bazında izole edilir. RLS (Row Level Security) politikaları Gün 6-9'da
-- (auth sistemi kurulunca) tamamlanacak; burada tablo yapısı + temel
-- kısıtlamalar + izolasyonun iskeleti hazırlanıyor.
--
-- Çalıştırma sırası önemlidir (foreign key bağımlılıkları yüzünden) —
-- bu dosyayı olduğu gibi, baştan sona, Supabase SQL Editor'da çalıştırın.
-- ============================================================================

create extension if not exists "pgcrypto"; -- gen_random_uuid() için

-- ----------------------------------------------------------------------------
-- 1. KURUMLAR (okullar) — Süper Admin panelinden yönetilir
-- ----------------------------------------------------------------------------
create table kurumlar (
  id            uuid primary key default gen_random_uuid(),
  ad            text not null,                    -- "Yağcıllı Ortaokulu"
  alt_baslik    text,                              -- "Yağcıllı Ortaokulu Yönetim Sistemi" gibi
  aktif         boolean not null default true,
  created_at    timestamptz not null default now()
);

-- ----------------------------------------------------------------------------
-- 2. PERSONEL — hem idareciler hem öğretmenler burada, rol alanıyla ayrılır
-- ----------------------------------------------------------------------------
create type personel_rolu as enum ('super_admin', 'idareci', 'ogretmen');

create table personel (
  id              uuid primary key default gen_random_uuid(),
  kurum_id        uuid references kurumlar(id) on delete cascade,  -- super_admin için null olabilir
  auth_user_id    uuid unique,                     -- Supabase Auth kullanıcısıyla eşleşir (Gün 6-8'de bağlanacak)
  ad_soyad        text not null,
  brans           text,                            -- "Fen Bilimleri", "Matematik" vb.
  rol             personel_rolu not null default 'ogretmen',
  sifre_degistirildi boolean not null default false, -- ilk girişte zorunlu şifre değişimi takibi
  aktif           boolean not null default true,
  created_at      timestamptz not null default now(),

  constraint personel_kurum_gerekli check (rol = 'super_admin' or kurum_id is not null)
);

create index idx_personel_kurum on personel(kurum_id);

-- ----------------------------------------------------------------------------
-- 3. DERS ADLARI SÖZLÜĞÜ (kod -> tam ad), kurum bazlı
-- ----------------------------------------------------------------------------
create table ders_adlari (
  id          uuid primary key default gen_random_uuid(),
  kurum_id    uuid not null references kurumlar(id) on delete cascade,
  kod         text not null,                       -- "FEN", "MAT" vb.
  ad          text not null,                        -- "Fen Bilimleri"
  unique (kurum_id, kod)
);

-- ----------------------------------------------------------------------------
-- 4. DERS PROGRAMI — her satır bir öğretmenin bir gün/saatteki dersi
-- ----------------------------------------------------------------------------
create type haftanin_gunu as enum ('Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma');

create table ders_programi (
  id            uuid primary key default gen_random_uuid(),
  kurum_id      uuid not null references kurumlar(id) on delete cascade,
  ogretmen_id   uuid not null references personel(id) on delete cascade,
  gun           haftanin_gunu not null,
  saat          smallint not null check (saat between 1 and 7),
  sinif         text not null,                     -- "5/A", "Anasınıfı" vb.
  ders_kodu     text not null,
  updated_at    timestamptz not null default now(),

  unique (kurum_id, ogretmen_id, gun, saat)          -- bir öğretmen aynı saatte iki yerde olamaz
);

create index idx_ders_programi_kurum on ders_programi(kurum_id);
create index idx_ders_programi_sinif on ders_programi(kurum_id, sinif);

-- ----------------------------------------------------------------------------
-- 5. NÖBET ÇİZELGESİ
-- ----------------------------------------------------------------------------
create table nobet_cizelgesi (
  id                  uuid primary key default gen_random_uuid(),
  kurum_id            uuid not null references kurumlar(id) on delete cascade,
  tarih               date not null,
  bahce_ogretmen_id   uuid references personel(id) on delete set null,
  bina_ogretmen_id    uuid references personel(id) on delete set null,
  updated_at          timestamptz not null default now(),

  unique (kurum_id, tarih)
);

create index idx_nobet_kurum_tarih on nobet_cizelgesi(kurum_id, tarih);

-- ----------------------------------------------------------------------------
-- 6. RESMİ TATİLLER (Gün 18'de nöbet dağıtıcıya bağlanacak)
-- ----------------------------------------------------------------------------
create table resmi_tatiller (
  id          uuid primary key default gen_random_uuid(),
  kurum_id    uuid not null references kurumlar(id) on delete cascade,
  tarih       date not null,
  aciklama    text,                                 -- "Cumhuriyet Bayramı", "Yarıyıl Tatili" vb.
  unique (kurum_id, tarih)
);

-- ----------------------------------------------------------------------------
-- 7. SINAVLAR
-- ----------------------------------------------------------------------------
create type sinav_tipi as enum ('sinav1', 'sinav2', 'proje1', 'proje2');

create table sinavlar (
  id          uuid primary key default gen_random_uuid(),
  kurum_id    uuid not null references kurumlar(id) on delete cascade,
  sinif       text not null,
  brans       text not null,
  donem       smallint not null check (donem in (1, 2)),
  sinav_no    sinav_tipi not null,
  tarih       date not null,
  created_at  timestamptz not null default now(),

  unique (kurum_id, sinif, brans, donem, sinav_no)
);

-- ----------------------------------------------------------------------------
-- 8. NÖBET & SERVİS NOT DEFTERİ — silme yetkisi yalnızca ekleyen kişide
-- ----------------------------------------------------------------------------
create table notlar (
  id            uuid primary key default gen_random_uuid(),
  kurum_id      uuid not null references kurumlar(id) on delete cascade,
  tarih         date not null,
  servis        text,
  not_metni     text,
  olusturan_id  uuid not null references personel(id) on delete cascade,
  created_at    timestamptz not null default now()
);

create index idx_notlar_kurum on notlar(kurum_id, created_at desc);

-- ----------------------------------------------------------------------------
-- 9. DUYURULAR + okunma takibi (bildirim rozeti için)
-- ----------------------------------------------------------------------------
create table duyurular (
  id            uuid primary key default gen_random_uuid(),
  kurum_id      uuid not null references kurumlar(id) on delete cascade,
  baslik        text not null,
  icerik        text not null,
  olusturan_id  uuid not null references personel(id) on delete cascade,
  created_at    timestamptz not null default now()
);

create index idx_duyurular_kurum on duyurular(kurum_id, created_at desc);

create table duyuru_okumalar (
  duyuru_id     uuid not null references duyurular(id) on delete cascade,
  personel_id   uuid not null references personel(id) on delete cascade,
  okundu_at     timestamptz not null default now(),
  primary key (duyuru_id, personel_id)
);

-- ----------------------------------------------------------------------------
-- 10. KURUL VE KOMİSYONLAR
-- ----------------------------------------------------------------------------
create table kurullar (
  id          uuid primary key default gen_random_uuid(),
  kurum_id    uuid not null references kurumlar(id) on delete cascade,
  ad          text not null,                        -- "Zümre Başkanları Kurulu" vb.
  aciklama    text
);

create table kurul_uyeleri (
  kurul_id      uuid not null references kurullar(id) on delete cascade,
  personel_id   uuid not null references personel(id) on delete cascade,
  gorev         text,                                 -- "Başkan", "Üye" vb. (opsiyonel)
  primary key (kurul_id, personel_id)
);

-- ----------------------------------------------------------------------------
-- 11. BELİRLİ GÜN VE HAFTALAR — kurul/komisyonla aynı üçlü görünüm mantığı
-- ----------------------------------------------------------------------------
create table belirli_gunler (
  id          uuid primary key default gen_random_uuid(),
  kurum_id    uuid not null references kurumlar(id) on delete cascade,
  ad          text not null,                         -- "Kızılay Haftası", "Öğretmenler Günü" vb.
  baslangic   date,
  bitis       date
);

create table belirli_gun_gorevlileri (
  belirli_gun_id  uuid not null references belirli_gunler(id) on delete cascade,
  personel_id     uuid not null references personel(id) on delete cascade,
  gorev           text,
  primary key (belirli_gun_id, personel_id)
);

-- ----------------------------------------------------------------------------
-- 12. İŞLEM KAYDI (audit log) — kim, ne zaman, neyi değiştirdi/sildi
-- ----------------------------------------------------------------------------
create table islem_kayitlari (
  id            uuid primary key default gen_random_uuid(),
  kurum_id      uuid references kurumlar(id) on delete set null,  -- süper admin işlemlerinde null olabilir
  personel_id   uuid references personel(id) on delete set null,
  islem_tipi    text not null,                       -- 'ekle' | 'guncelle' | 'sil'
  tablo_adi     text not null,                       -- 'ders_programi', 'nobet_cizelgesi' vb.
  kayit_id      uuid,
  detay         jsonb,                                -- değişen alanlar / eski-yeni değer
  created_at    timestamptz not null default now()
);

create index idx_islem_kayitlari_kurum on islem_kayitlari(kurum_id, created_at desc);

-- ============================================================================
-- ROW LEVEL SECURITY
-- ============================================================================
-- Gün 9'da tamamlandı — gerçek politikalar supabase/rls_policies.sql
-- dosyasında. Bu dosyayı schema.sql'den SONRA çalıştırın.

create or replace function current_personel()
returns personel as $$
  select * from personel where auth_user_id = auth.uid() limit 1;
$$ language sql stable;

-- ============================================================================
-- Personel — İşlem Kaydı (Audit Log) Tetikleyicileri (Faz 2 / Gün 11)
-- ============================================================================
-- Genel yaklaşım: veritabanı tetikleyicileri (trigger) kullanılıyor, uygulama
-- kodunun her yerde "bunu da logla" diye hatırlamasına gerek yok — ister
-- tarayıcıdan (RLS ile), ister Edge Function'dan (service role ile) gelsin,
-- her INSERT/UPDATE/DELETE otomatik olarak islem_kayitlari'na düşer.
--
-- Bu dosyayı schema.sql ve rls_policies.sql'den SONRA çalıştırın.
-- ============================================================================

create or replace function log_islem()
returns trigger as $$
declare
  actor_id uuid;
  affected_kurum uuid;
begin
  select id into actor_id from personel where auth_user_id = auth.uid();

  if TG_OP = 'DELETE' then
    affected_kurum := OLD.kurum_id;
  else
    affected_kurum := NEW.kurum_id;
  end if;

  insert into islem_kayitlari (kurum_id, personel_id, islem_tipi, tablo_adi, kayit_id, detay)
  values (
    affected_kurum,
    actor_id,
    case TG_OP when 'INSERT' then 'ekle' when 'UPDATE' then 'guncelle' when 'DELETE' then 'sil' end,
    TG_TABLE_NAME,
    case TG_OP when 'DELETE' then OLD.id else NEW.id end,
    case TG_OP when 'DELETE' then to_jsonb(OLD) else to_jsonb(NEW) end
  );

  return null; -- AFTER trigger olduğu için dönüş değeri kullanılmıyor
end;
$$ language plpgsql security definer set search_path = public;

-- islem_kayitlari tablosuna doğrudan yazma izni YOK (RLS'de bilerek tanımlamadık)
-- — bu fonksiyon SECURITY DEFINER olduğu için trigger üzerinden yazabiliyor,
-- yani logları sadece bu mekanizma oluşturabilir, istemci asla doğrudan yazamaz.

create trigger trg_log_personel after insert or update or delete on personel for each row execute function log_islem();
create trigger trg_log_ders_programi after insert or update or delete on ders_programi for each row execute function log_islem();
create trigger trg_log_ders_adlari after insert or update or delete on ders_adlari for each row execute function log_islem();
create trigger trg_log_nobet_cizelgesi after insert or update or delete on nobet_cizelgesi for each row execute function log_islem();
create trigger trg_log_resmi_tatiller after insert or update or delete on resmi_tatiller for each row execute function log_islem();
create trigger trg_log_sinavlar after insert or update or delete on sinavlar for each row execute function log_islem();
create trigger trg_log_notlar after insert or update or delete on notlar for each row execute function log_islem();
create trigger trg_log_duyurular after insert or update or delete on duyurular for each row execute function log_islem();
create trigger trg_log_kurullar after insert or update or delete on kurullar for each row execute function log_islem();
create trigger trg_log_belirli_gunler after insert or update or delete on belirli_gunler for each row execute function log_islem();

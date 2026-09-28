// Giriş yapmış bir idareci/süper admin tarafından çağrılır (JWT zorunlu).
// İdareci sadece kendi kurumu için hesap açabilir; süper admin herhangi bir
// kurum için açabilir. Şifre her zaman ad-soyad kuralından otomatik üretilir
// (manuel override yok) — kullanıcı ilk girişten sonra kendi şifresini
// değiştirebilir.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function turkishFold(str: string): string {
  return String(str)
    .toLocaleLowerCase("tr")
    .replace(/ç/g, "c").replace(/ğ/g, "g").replace(/ı/g, "i")
    .replace(/ö/g, "o").replace(/ş/g, "s").replace(/ü/g, "u")
    .replace(/[^a-z]/g, "");
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Giriş yapmalısın." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: callerAuth, error: callerAuthErr } = await callerClient.auth.getUser();
    if (callerAuthErr || !callerAuth.user) {
      return new Response(JSON.stringify({ error: "Geçersiz oturum." }), {
        status: 401,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: callerPersonel, error: callerPersonelErr } = await admin
      .from("personel")
      .select("id, kurum_id, rol")
      .eq("auth_user_id", callerAuth.user.id)
      .single();
    if (callerPersonelErr || !callerPersonel) {
      return new Response(JSON.stringify({ error: "Personel kaydın bulunamadı." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (!["idareci", "super_admin"].includes(callerPersonel.rol)) {
      return new Response(JSON.stringify({ error: "Bu işlem için yetkin yok." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const body = await req.json();
    const ad_soyad: string = body.ad_soyad;
    const rol: string = body.rol; // 'idareci' | 'ogretmen'
    const brans: string | null = body.brans ?? null;
    let kurum_id: string = body.kurum_id;

    if (!ad_soyad || !["idareci", "ogretmen"].includes(rol)) {
      return new Response(JSON.stringify({ error: "ad_soyad ve gecerli bir rol (idareci/ogretmen) gerekli." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // İdareci sadece kendi kurumu için hesap açabilir — body'deki kurum_id güvenlik gereği yok sayılır.
    if (callerPersonel.rol === "idareci") {
      kurum_id = callerPersonel.kurum_id;
    }
    if (!kurum_id) {
      return new Response(JSON.stringify({ error: "kurum_id gerekli." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: existing } = await admin
      .from("personel")
      .select("id")
      .eq("kurum_id", kurum_id)
      .eq("ad_soyad", ad_soyad)
      .eq("aktif", true)
      .maybeSingle();
    if (existing) {
      return new Response(JSON.stringify({ error: `"${ad_soyad}" için bu kurumda zaten aktif bir hesap var.` }), {
        status: 409,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: personelRow, error: insertErr } = await admin
      .from("personel")
      .insert({ kurum_id, ad_soyad, rol, brans, aktif: true })
      .select("id")
      .single();
    if (insertErr) throw insertErr;

    const email = `${personelRow.id}@yagcilli.personel.local`;
    const gecici_sifre = turkishFold(ad_soyad);
    const { data: authUser, error: authErr } = await admin.auth.admin.createUser({
      email,
      password: gecici_sifre,
      email_confirm: true,
    });
    if (authErr) {
      await admin.from("personel").delete().eq("id", personelRow.id);
      throw authErr;
    }

    const { error: updateErr } = await admin
      .from("personel")
      .update({ auth_user_id: authUser.user.id })
      .eq("id", personelRow.id);
    if (updateErr) throw updateErr;

    return new Response(JSON.stringify({ ok: true, ad_soyad, gecici_sifre, personel_id: personelRow.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message ?? String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

// Giriş yapmış bir idareci/süper admin tarafından çağrılır (JWT zorunlu).
// Bir personelin şifresini ad-soyad kuralına göre sıfırlar (örn. şifremi unuttum
// durumunda idarecinin kullanacağı akış). İdareci sadece kendi kurumundaki
// personelin şifresini sıfırlayabilir; süper admin herhangi birininkini.
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
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const callerClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: authHeader } } });
    const { data: callerAuth } = await callerClient.auth.getUser();
    if (!callerAuth.user) {
      return new Response(JSON.stringify({ error: "Geçersiz oturum." }), {
        status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: callerPersonel } = await admin.from("personel").select("id, kurum_id, rol").eq("auth_user_id", callerAuth.user.id).single();
    if (!callerPersonel || !["idareci", "super_admin"].includes(callerPersonel.rol)) {
      return new Response(JSON.stringify({ error: "Bu işlem için yetkin yok." }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { personel_id } = await req.json();
    const { data: hedef } = await admin.from("personel").select("id, ad_soyad, kurum_id, auth_user_id").eq("id", personel_id).single();
    if (!hedef) {
      return new Response(JSON.stringify({ error: "Personel bulunamadı." }), {
        status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }
    if (callerPersonel.rol === "idareci" && hedef.kurum_id !== callerPersonel.kurum_id) {
      return new Response(JSON.stringify({ error: "Sadece kendi kurumundaki personelin şifresini sıfırlayabilirsin." }), {
        status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const yeniSifre = turkishFold(hedef.ad_soyad);
    const { error: updateErr } = await admin.auth.admin.updateUserById(hedef.auth_user_id, { password: yeniSifre });
    if (updateErr) throw updateErr;

    return new Response(JSON.stringify({ ok: true, ad_soyad: hedef.ad_soyad, yeni_sifre: yeniSifre }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message ?? String(err) }), {
      status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

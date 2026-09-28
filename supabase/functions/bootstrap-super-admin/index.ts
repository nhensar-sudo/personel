// Tek seferlik kurulum: sistemde hiç süper admin yoksa, ilk süper admin hesabını
// oluşturur. Zaten bir süper admin varsa 403 döner ve kendini kilitler.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { count, error: countErr } = await admin
      .from("personel")
      .select("id", { count: "exact", head: true })
      .eq("rol", "super_admin");

    if (countErr) throw countErr;
    if ((count ?? 0) > 0) {
      return new Response(JSON.stringify({ error: "Zaten bir süper admin hesabı kurulu." }), {
        status: 403,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { ad_soyad, sifre } = await req.json();
    if (!ad_soyad || !sifre || String(sifre).length < 6) {
      return new Response(JSON.stringify({ error: "ad_soyad ve en az 6 karakterlik bir sifre gerekli." }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const { data: personelRow, error: insertErr } = await admin
      .from("personel")
      .insert({ kurum_id: null, ad_soyad, rol: "super_admin", aktif: true })
      .select("id")
      .single();
    if (insertErr) throw insertErr;

    const email = `${personelRow.id}@yagcilli.personel.local`;
    const { data: authUser, error: authErr } = await admin.auth.admin.createUser({
      email,
      password: sifre,
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

    return new Response(JSON.stringify({ ok: true, personel_id: personelRow.id }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: err.message ?? String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

async function hashCode(code: string): Promise<string> {
  const data = new TextEncoder().encode(code);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(hash);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  try {
    const body = await req.json();
    const email = String(body?.email ?? "").trim().toLowerCase();
    const code = String(body?.code ?? "").trim();
    const newPassword = String(body?.newPassword ?? "");

    if (!email || !code || newPassword.length < 8) {
      return new Response(JSON.stringify({ ok: false, message: "Invalid request" }), { status: 400 });
    }

    const { data: userRow, error } = await supabase.from('users').select('id').eq('email', email).maybeSingle();
    if (error || !userRow) {
      return new Response(JSON.stringify({ ok: false, message: "Invalid code" }), { status: 400 });
    }

    const codeHash = await hashCode(code);
    const { data: otpRow, error: otpError } = await supabase
      .from("password_reset_otps")
      .select("id, expires_at, used_at")
      .eq("user_id", userRow.id)
      .eq("code_hash", codeHash)
      .maybeSingle();

    if (otpError || !otpRow) {
      return new Response(JSON.stringify({ ok: false, message: "Invalid code" }), { status: 400 });
    }
    if (otpRow.used_at) {
      return new Response(JSON.stringify({ ok: false, message: "Code already used" }), { status: 400 });
    }
    if (new Date(otpRow.expires_at) < new Date()) {
      return new Response(JSON.stringify({ ok: false, message: "Code expired" }), { status: 400 });
    }

    const { error: updateError } = await supabase.auth.admin.updateUserById(
      userRow.id,
      { password: newPassword },
    );
    if (updateError) {
      return new Response(JSON.stringify({ ok: false, message: "Failed to update password" }), { status: 400 });
    }

    await supabase
      .from("password_reset_otps")
      .update({ used_at: new Date().toISOString() })
      .eq("id", otpRow.id);

    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (_e) {
    return new Response(JSON.stringify({ ok: false, message: "Failed to reset password" }), { status: 500 });
  }
});

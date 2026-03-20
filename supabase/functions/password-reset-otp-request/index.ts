import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.1";
import nodemailer from "npm:nodemailer@6.9.12";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GMAIL_USER = Deno.env.get("GMAIL_USER") ?? "";
const GMAIL_APP_PASSWORD = Deno.env.get("GMAIL_APP_PASSWORD") ?? "";
const APP_NAME = Deno.env.get("APP_NAME") ?? "AnonPro";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false },
});

function generateOtp(): string {
  const value = Math.floor(100000 + Math.random() * 900000);
  return String(value);
}

async function hashCode(code: string): Promise<string> {
  const data = new TextEncoder().encode(code);
  const hash = await crypto.subtle.digest("SHA-256", data);
  const bytes = new Uint8Array(hash);
  return Array.from(bytes).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function renderEmailHtml(code: string): string {
  return `
  <!doctype html>
  <html>
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width, initial-scale=1" />
      <title>Reset Your ${APP_NAME} Password</title>
    </head>
    <body style="margin:0;padding:0;background:#f6f7fb;font-family:Arial,Helvetica,sans-serif;color:#111;">
      <table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f6f7fb;padding:24px 0;">
        <tr>
          <td align="center">
            <table role="presentation" width="600" cellspacing="0" cellpadding="0" style="background:#ffffff;border-radius:12px;overflow:hidden;box-shadow:0 10px 30px rgba(0,0,0,0.08);">
              <tr>
                <td style="padding:24px 28px;background:#0b0f1a;color:#ffffff;">
                  <div style="font-size:18px;font-weight:700;letter-spacing:0.5px;">${APP_NAME}</div>
                </td>
              </tr>
              <tr>
                <td style="padding:32px 28px;">
                  <h2 style="margin:0 0 12px;font-size:20px;">Reset Your Password</h2>
                  <p style="margin:0 0 16px;line-height:1.5;color:#444;">
                    Use the code below to reset your ${APP_NAME} password. This code expires in 10 minutes.
                  </p>
                  <div style="font-size:24px;letter-spacing:6px;font-weight:700;color:#1f7aff;background:#f1f5ff;padding:12px 16px;border-radius:8px;display:inline-block;">
                    ${code}
                  </div>
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
  </html>`;
}

async function sendEmail(toEmail: string, code: string): Promise<void> {
  if (!GMAIL_USER || !GMAIL_APP_PASSWORD) {
    throw new Error("SMTP is not configured: missing GMAIL_USER or GMAIL_APP_PASSWORD");
  }

  const transporter = nodemailer.createTransport({
    service: "gmail",
    auth: {
      user: GMAIL_USER,
      pass: GMAIL_APP_PASSWORD,
    },
  });

  await transporter.sendMail({
    from: `"${APP_NAME}" <${GMAIL_USER}>`,
    to: toEmail,
    subject: `Reset Your ${APP_NAME} Password`,
    text: `Your ${APP_NAME} password reset code is: ${code}. It expires in 10 minutes.`,
    html: renderEmailHtml(code),
  });
}

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }
  try {
    const body = await req.json();
    const email = String(body?.email ?? "").trim().toLowerCase();
    if (!email || !email.includes("@")) {
      console.log("[OTP] Invalid email format: " + email);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    const { data: userRow, error } = await supabase.from('users').select('id').eq('email', email).maybeSingle();
    if (error || !userRow) {
      console.log("[OTP] User not found or DB error for email: " + email);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    const code = generateOtp();
    const codeHash = await hashCode(code);
    const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString();

    await supabase.from("password_reset_otps").delete().eq("user_id", userRow.id);
    const { error: insertError } = await supabase.from("password_reset_otps").insert({
      user_id: userRow.id,
      code_hash: codeHash,
      expires_at: expiresAt,
    });
    if (insertError) {
      console.error("[OTP] DB Insert error: " + insertError.message);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }

    try {
      await sendEmail(email, code);
      console.log("[OTP] Success: sent email to " + email);
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    } catch (smtpError) {
      console.error("[OTP] SMTP Error: " + (smtpError instanceof Error ? smtpError.message : String(smtpError)));
      return new Response(JSON.stringify({ ok: true }), { status: 200 });
    }
  } catch (e) {
    console.error("[OTP] Global Error: " + (e instanceof Error ? e.message : String(e)));
    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  }
});

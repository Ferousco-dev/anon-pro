import { serve } from "https://deno.land/std@0.192.0/http/server.ts";

const encoder = new TextEncoder();

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// ImageKit requires HMAC-SHA1(key=privateKey, message=token+expire)
async function hmacSha1Hex(key: string, message: string): Promise<string> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(key),
    { name: "HMAC", hash: "SHA-1" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", cryptoKey, encoder.encode(message));
  return Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (req) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // .trim() is critical — Supabase secrets often have trailing newlines
    const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY")?.trim();
    const publicKey  = Deno.env.get("IMAGEKIT_PUBLIC_KEY")?.trim();

    if (!privateKey || !publicKey) {
      return new Response(
        JSON.stringify({ error: "Missing ImageKit env vars" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const token  = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 600; // 10 min window

    // HMAC-SHA1: key = privateKey, message = token + expire
    const signature = await hmacSha1Hex(privateKey, token + expire);

    // Debug logging — remove after confirming uploads work
    console.log("[imagekit-sig] publicKey:", publicKey);
    console.log("[imagekit-sig] token:", token);
    console.log("[imagekit-sig] expire:", expire);
    console.log("[imagekit-sig] signature:", signature);

    return new Response(
      JSON.stringify({ token, expire, signature, publicKey }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "Cache-Control": "no-store", // never cache signatures
        },
      },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ error: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});

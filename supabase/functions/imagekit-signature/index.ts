import { serve } from "https://deno.land/std@0.192.0/http/server.ts";

const encoder = new TextEncoder();

async function sha1Hex(input: string): Promise<string> {
  const hash = await crypto.subtle.digest("SHA-1", encoder.encode(input));
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

serve(async (_req) => {
  try {
    const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY");
    const publicKey = Deno.env.get("IMAGEKIT_PUBLIC_KEY");
    if (!privateKey || !publicKey) {
      return new Response("Missing ImageKit env vars", { status: 500 });
    }

    const token = crypto.randomUUID();
    const expire = Math.floor(Date.now() / 1000) + 60;
    const signature = await sha1Hex(`${token}${expire}${privateKey}`);

    return new Response(
      JSON.stringify({ token, expire, signature, publicKey }),
      { headers: { "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: (e as Error).message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

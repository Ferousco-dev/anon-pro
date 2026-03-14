import { serve } from "https://deno.land/std@0.192.0/http/server.ts";

serve(async (req) => {
  try {
    const privateKey = Deno.env.get("IMAGEKIT_PRIVATE_KEY");
    if (!privateKey) {
      return new Response("Missing ImageKit env vars", { status: 500 });
    }

    const payload = await req.json();
    const fileId = payload?.fileId;
    if (!fileId) {
      return new Response("Missing fileId", { status: 400 });
    }

    const auth = btoa(`${privateKey}:`);
    const response = await fetch(
      `https://api.imagekit.io/v1/files/${fileId}`,
      {
        method: "DELETE",
        headers: { Authorization: `Basic ${auth}` },
      },
    );

    if (!response.ok) {
      const err = await response.text();
      return new Response(err, { status: response.status });
    }

    return new Response(JSON.stringify({ ok: true }), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ ok: false, error: (e as Error).message }),
      { status: 500, headers: { "Content-Type": "application/json" } },
    );
  }
});

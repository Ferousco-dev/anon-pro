import { serve } from "https://deno.land/std@0.192.0/http/server.ts";

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri: string;
  project_id: string;
};

const encoder = new TextEncoder();

function base64Url(input: string | Uint8Array) {
  const bytes = typeof input === "string" ? encoder.encode(input) : input;
  const bin = Array.from(bytes, (b) => String.fromCharCode(b)).join("");
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function signJwt(sa: ServiceAccount) {
  const header = { alg: "RS256", typ: "JWT" };
  const now = Math.floor(Date.now() / 1000);
  const payload = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: sa.token_uri,
    iat: now,
    exp: now + 3600,
  };

  const headerB64 = base64Url(JSON.stringify(header));
  const payloadB64 = base64Url(JSON.stringify(payload));
  const data = `${headerB64}.${payloadB64}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(data),
  );

  return `${data}.${base64Url(new Uint8Array(signature))}`;
}

function pemToDer(pem: string) {
  const b64 = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function getAccessToken(sa: ServiceAccount) {
  const assertion = await signJwt(sa);
  const res = await fetch(sa.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const json = await res.json();
  if (!res.ok) {
    throw new Error(json.error_description ?? "Failed to get access token");
  }
  return json.access_token as string;
}

async function sendToToken(
  projectId: string,
  accessToken: string,
  token: string,
  title: string,
  body: string,
  data: Record<string, string>,
  sound: string,
) {
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token,
          notification: { title, body },
          data,
          android: {
            notification: { sound },
          },
          apns: {
            payload: {
              aps: {
                sound,
              },
            },
          },
          webpush: {
            notification: {
              title,
              body,
              icon: "/icons/Icon-192.png",
              badge: "/icons/Icon-192.png",
              sound,
            },
          },
        },
      }),
    },
  );

  if (!res.ok) {
    const err = await res.text();
    throw new Error(err);
  }
}

serve(async (req) => {
  try {
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!saRaw) {
      return new Response("Missing service account secret", { status: 500 });
    }
    const sa = JSON.parse(saRaw) as ServiceAccount;

    const payload = await req.json();
    const {
      token,
      tokens,
      title,
      body,
      data = {},
      sound = "default",
    } = payload;

    if (!title || !body) {
      return new Response("Missing title/body", { status: 400 });
    }

    const accessToken = await getAccessToken(sa);
    const list: string[] = Array.isArray(tokens)
      ? tokens
      : token
        ? [token]
        : [];

    if (list.length === 0) {
      return new Response("No token(s) provided", { status: 400 });
    }

    for (const t of list) {
      await sendToToken(sa.project_id, accessToken, t, title, body, data, sound);
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

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

function normalizeAndroidSound(sound: string) {
  const trimmed = sound.trim();
  if (!trimmed) return trimmed;
  const name = trimmed.split("/").pop() ?? trimmed;
  const dotIndex = name.lastIndexOf(".");
  return dotIndex > 0 ? name.slice(0, dotIndex) : name;
}

function normalizeIosSound(sound: string) {
  const trimmed = sound.trim();
  if (!trimmed) return trimmed;
  return trimmed.split("/").pop() ?? trimmed;
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
  dataOnly: boolean,
  channelId?: string,
  imageUrl?: string,
) {
  const androidSound = normalizeAndroidSound(sound);
  const iosSound = normalizeIosSound(sound);
  const trimmedChannelId = channelId?.trim();
  const trimmedImage = imageUrl?.trim();
  const androidNotification: Record<string, unknown> = {};
  if (androidSound) {
    androidNotification.sound = androidSound;
  }
  if (trimmedChannelId) {
    androidNotification.channel_id = trimmedChannelId;
  }
  if (trimmedImage) {
    androidNotification.image = trimmedImage;
  }

  const apnsPayload: Record<string, unknown> = {
    aps: iosSound ? { sound: iosSound } : {},
  };
  const apns: Record<string, unknown> = {
    payload: apnsPayload,
  };
  if (trimmedImage) {
    apns.fcm_options = { image: trimmedImage };
  }

  const message: Record<string, unknown> = {
    token,
    data,
    android: dataOnly
      ? { priority: "HIGH" }
      : { notification: androidNotification },
    apns: dataOnly ? { headers: { "apns-priority": "10" } } : apns,
    webpush: dataOnly
      ? { headers: { Urgency: "high" } }
      : {
          notification: {
            title,
            body,
            icon: "/icons/Icon-192.png",
            badge: "/icons/Icon-192.png",
            sound,
            ...(trimmedImage ? { image: trimmedImage } : {}),
          },
        },
  };

  if (!dataOnly) {
    message.notification = {
      title,
      body,
      ...(trimmedImage ? { image: trimmedImage } : {}),
    };
  }

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
          ...message,
        },
      }),
    },
  );

  if (!res.ok) {
    const err = await res.text();
    throw new Error(err);
  }
}

async function sendToTopic(
  projectId: string,
  accessToken: string,
  topic: string,
  title: string,
  body: string,
  data: Record<string, string>,
  sound: string,
  dataOnly: boolean,
  channelId?: string,
  imageUrl?: string,
) {
  const androidSound = normalizeAndroidSound(sound);
  const iosSound = normalizeIosSound(sound);
  const trimmedChannelId = channelId?.trim();
  const trimmedImage = imageUrl?.trim();
  const androidNotification: Record<string, unknown> = {};
  if (androidSound) {
    androidNotification.sound = androidSound;
  }
  if (trimmedChannelId) {
    androidNotification.channel_id = trimmedChannelId;
  }
  if (trimmedImage) {
    androidNotification.image = trimmedImage;
  }

  const apnsPayload: Record<string, unknown> = {
    aps: iosSound ? { sound: iosSound } : {},
  };
  const apns: Record<string, unknown> = {
    payload: apnsPayload,
  };
  if (trimmedImage) {
    apns.fcm_options = { image: trimmedImage };
  }

  const message: Record<string, unknown> = {
    topic,
    data,
    android: dataOnly
      ? { priority: "HIGH" }
      : { notification: androidNotification },
    apns: dataOnly ? { headers: { "apns-priority": "10" } } : apns,
    webpush: dataOnly
      ? { headers: { Urgency: "high" } }
      : {
          notification: {
            title,
            body,
            icon: "/icons/Icon-192.png",
            badge: "/icons/Icon-192.png",
            sound,
            ...(trimmedImage ? { image: trimmedImage } : {}),
          },
        },
  };

  if (!dataOnly) {
    message.notification = {
      title,
      body,
      ...(trimmedImage ? { image: trimmedImage } : {}),
    };
  }

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
          ...message,
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
      topic,
      title,
      body,
      data = {},
      sound = "default",
      data_only = false,
      channel_id,
      image,
    } = payload;

    if (!data_only && (!title || !body)) {
      return new Response("Missing title/body", { status: 400 });
    }

    const normalizedData: Record<string, string> = {};
    if (data && typeof data === "object") {
      for (const [key, value] of Object.entries(data)) {
        if (value === null || value === undefined) continue;
        normalizedData[key] =
          typeof value === "string" ? value : String(value);
      }
    }

    const accessToken = await getAccessToken(sa);
    const list: string[] = Array.isArray(tokens)
      ? tokens
      : token
        ? [token]
        : [];

    const channelId =
      typeof channel_id === "string" && channel_id.trim().length > 0
        ? channel_id.trim()
        : undefined;
    const imageUrl =
      typeof image === "string" && image.trim().length > 0
        ? image.trim()
        : undefined;

    if (topic && typeof topic === "string" && topic.trim().length > 0) {
      await sendToTopic(
        sa.project_id,
        accessToken,
        topic.trim(),
        title,
        body,
        normalizedData,
        sound,
        data_only === true,
        channelId,
        imageUrl,
      );

      return new Response(JSON.stringify({ ok: true }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    if (list.length === 0) {
      return new Response("No token(s) or topic provided", { status: 400 });
    }

    for (const t of list) {
      await sendToToken(
        sa.project_id,
        accessToken,
        t,
        title,
        body,
        normalizedData,
        sound,
        data_only === true,
        channelId,
        imageUrl,
      );
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

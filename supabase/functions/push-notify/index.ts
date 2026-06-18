// Supabase Edge Function: push-notify
//
// Triggered by Database Webhooks on `order_items` (UPDATE) and
// `cash_register_sessions` (UPDATE). Resolves the event → business, looks up
// that business's device tokens, and sends an FCM HTTP v1 push to each.
//
// Required secrets (supabase secrets set ...):
//   SUPABASE_URL                 (provided automatically)
//   SUPABASE_SERVICE_ROLE_KEY    (provided automatically)
//   FCM_PROJECT_ID               your Firebase project id
//   FCM_SERVICE_ACCOUNT          the full service-account JSON (one line)
//
// Events pushed: producto anulado (order_items.status -> void),
// cierre de caja, and caja descuadrada (cash close with a non-zero difference).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const FCM_PROJECT_ID = Deno.env.get("FCM_PROJECT_ID")!;
const SERVICE_ACCOUNT = JSON.parse(Deno.env.get("FCM_SERVICE_ACCOUNT") ?? "{}");

const admin = createClient(SUPABASE_URL, SERVICE_ROLE);

// ── Google OAuth access token from the service account (RS256 JWT) ──
let cached: { token: string; exp: number } | null = null;

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cached && cached.exp - 60 > now) return cached.token;

  const claim = {
    iss: SERVICE_ACCOUNT.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const enc = (o: unknown) => b64url(new TextEncoder().encode(JSON.stringify(o)));
  const unsigned = `${enc({ alg: "RS256", typ: "JWT" })}.${enc(claim)}`;
  const key = await importKey(SERVICE_ACCOUNT.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const json = await res.json();
  cached = { token: json.access_token, exp: now + 3600 };
  return json.access_token;
}

function b64url(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

// ── Event resolution: webhook payload → { businessId, title, body } | null ──
type Notif = { businessId: string; title: string; body: string };

async function buildEvent(payload: any): Promise<Notif | null> {
  const { table, type, record, old_record } = payload ?? {};
  if (type !== "UPDATE" || !record) return null;

  if (table === "order_items") {
    if (record.status !== "void" || old_record?.status === "void") return null;
    // orders has no business_id; it lives on table_sessions (orders.session_id → table_sessions).
    const { data } = await admin
      .from("orders")
      .select("table_sessions!inner(business_id)")
      .eq("id", record.order_id)
      .maybeSingle();
    const businessId = (data as any)?.table_sessions?.business_id;
    if (!businessId) return null;
    const qty = record.qty ?? record.quantity ?? 1;
    return {
      businessId,
      title: "Producto anulado",
      body: `${qty} x ${record.product_name ?? "Producto"} fue anulado.`,
    };
  }

  if (table === "cash_register_sessions") {
    const justClosed = record.closed_at && !old_record?.closed_at;
    const becameClosed = record.status === "closed" && old_record?.status !== "closed";
    if (!justClosed && !becameClosed) return null;
    const { data } = await admin
      .from("cash_registers").select("business_id").eq("id", record.cash_register_id).maybeSingle();
    if (!data?.business_id) return null;

    const diff = Number(record.difference ?? 0);
    if (Math.abs(diff) > 0.009) {
      return {
        businessId: data.business_id,
        title: "⚠️ Caja descuadrada",
        body: `Cierre con ${diff < 0 ? "faltante" : "sobrante"} de RD$ ${Math.abs(diff).toFixed(2)}.`,
      };
    }
    return {
      businessId: data.business_id,
      title: "Cierre de caja",
      body: "Se realizó un cierre de caja.",
    };
  }

  return null;
}

// ── Fan-out to the business's device tokens, pruning stale ones ──
async function sendToBusiness(n: Notif): Promise<{ sent: number; pruned: number }> {
  const { data: rows } = await admin
    .from("device_tokens").select("token").eq("business_id", n.businessId);
  if (!rows?.length) return { sent: 0, pruned: 0 };

  const accessToken = await getAccessToken();
  const stale: string[] = [];
  let sent = 0;

  for (const { token } of rows) {
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${FCM_PROJECT_ID}/messages:send`,
      {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: n.title, body: n.body },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    if (res.ok) sent++;
    else if (res.status === 404 || res.status === 400) stale.push(token); // unregistered / invalid
  }

  if (stale.length) await admin.from("device_tokens").delete().in("token", stale);
  return { sent, pruned: stale.length };
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    const event = await buildEvent(payload);
    if (!event) return Response.json({ skipped: true });
    return Response.json(await sendToBusiness(event));
  } catch (e) {
    return Response.json({ error: String(e) }, { status: 500 });
  }
});

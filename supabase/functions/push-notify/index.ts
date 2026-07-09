// Supabase Edge Function: push-notify
//
// Two entry paths (same fan-out to a business's device tokens via FCM HTTP v1):
//   1. Database Webhooks on `order_items` (UPDATE) and `cash_register_sessions`
//      (UPDATE) → resolves the event → business → push (producto anulado,
//      cierre de caja, caja descuadrada).
//   2. Daily billing-reminder sweep, invoked by pg_cron with the service-role
//      bearer and body {"kind":"billing_reminder_sweep"}. Calls the SQL RPC
//      `fn_billing_reminders_due` (who + message) and pushes each reminder.
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

// ── Event resolution: webhook payload → Notif | null ──
// eventType keys match the notification_preferences table + Dart NotificationEventType.
type Notif = { businessId: string; eventType: string; title: string; body: string };

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
    console.log(`[push-notify] order_items void order_id=${record.order_id} -> business=${businessId ?? "NULL"}`);
    if (!businessId) return null;
    const qty = record.qty ?? record.quantity ?? 1;
    return {
      businessId,
      eventType: "item_voided",
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
    console.log(`[push-notify] cash close register=${record.cash_register_id} -> business=${data?.business_id ?? "NULL"}`);
    if (!data?.business_id) return null;

    const diff = Number(record.difference ?? 0);
    if (Math.abs(diff) > 0.009) {
      return {
        businessId: data.business_id,
        eventType: "cash_mismatch",
        title: "⚠️ Caja descuadrada",
        body: `Cierre con ${diff < 0 ? "faltante" : "sobrante"} de RD$ ${Math.abs(diff).toFixed(2)}.`,
      };
    }
    return {
      businessId: data.business_id,
      eventType: "cash_closed",
      title: "Cierre de caja",
      body: "Se realizó un cierre de caja.",
    };
  }

  return null;
}

// ── Fan-out to the business's device tokens, pruning stale ones ──
// Returns per-token FCM verdicts so callers (and the logs) can see exactly what
// FCM/APNs said — `sent` only counts HTTP 200 from FCM, which is NOT proof the
// push reached the device. The `results` array surfaces the real error codes
// (UNREGISTERED, THIRD_PARTY_AUTH_ERROR, SENDER_ID_MISMATCH, etc.).
type SendResult = {
  token: string;
  platform: string | null;
  status: number;
  ok: boolean;
  fcm: unknown;
};

async function sendToBusiness(
  n: Notif,
): Promise<{ sent: number; pruned: number; results: SendResult[] }> {
  // Recipients = every owner/admin who belongs to this business — so a user who
  // manages several businesses gets each one's alerts on their device, no matter
  // which business the app currently has selected. We fan out by MEMBERSHIP, not
  // by the token's stored business_id.
  const { data: members } = await admin
    .from("user_businesses")
    .select("user_id")
    .eq("business_id", n.businessId)
    .in("role", ["owner", "admin"]);
  let userIds = [...new Set((members ?? []).map((m: any) => m.user_id).filter(Boolean))];
  console.log(
    `[push-notify] business=${n.businessId} event=${n.eventType} members=${userIds.length} title="${n.title}"`,
  );
  if (!userIds.length) return { sent: 0, pruned: 0, results: [] };

  // Opt-out preferences: drop users who turned THIS event off for THIS business.
  const { data: off } = await admin
    .from("notification_preferences")
    .select("user_id")
    .eq("business_id", n.businessId)
    .eq("event_type", n.eventType)
    .eq("enabled", false)
    .in("user_id", userIds);
  const disabled = new Set((off ?? []).map((p: any) => p.user_id));
  if (disabled.size) userIds = userIds.filter((u) => !disabled.has(u));
  if (!userIds.length) {
    console.log(`[push-notify] all ${disabled.size} member(s) disabled event=${n.eventType}`);
    return { sent: 0, pruned: 0, results: [] };
  }

  const { data: rows } = await admin
    .from("device_tokens").select("token, platform").in("user_id", userIds);
  console.log(
    `[push-notify] tokens=${rows?.length ?? 0} (recipients=${userIds.length}, disabled=${disabled.size})`,
  );
  if (!rows?.length) return { sent: 0, pruned: 0, results: [] };

  const accessToken = await getAccessToken();
  const stale: string[] = [];
  const results: SendResult[] = [];
  let sent = 0;

  for (const { token, platform } of rows) {
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
            // Be explicit for iOS so a terminated app still shows the banner +
            // sound (don't rely on FCM auto-filling aps.alert).
            apns: {
              headers: { "apns-priority": "10" },
              payload: {
                aps: {
                  alert: { title: n.title, body: n.body },
                  sound: "default",
                },
              },
            },
          },
        }),
      },
    );
    const bodyText = await res.text();
    let fcm: unknown = bodyText;
    try { fcm = JSON.parse(bodyText); } catch { /* keep raw text */ }
    const tail = `…${token.slice(-12)}`;
    console.log(
      `[push-notify] fcm token=${tail} platform=${platform ?? "?"} status=${res.status} body=${bodyText.slice(0, 500)}`,
    );
    results.push({ token: tail, platform: platform ?? null, status: res.status, ok: res.ok, fcm });
    if (res.ok) sent++;
    else if (res.status === 404 || res.status === 400) stale.push(token); // unregistered / invalid
  }

  if (stale.length) await admin.from("device_tokens").delete().in("token", stale);
  console.log(`[push-notify] done business=${n.businessId} sent=${sent} pruned=${stale.length}`);
  return { sent, pruned: stale.length, results };
}

// ── Billing reminder sweep (invoked daily by pg_cron) ──
// SQL decides who to notify today + the message (fn_billing_reminders_due);
// we just fan out to each business's device tokens. Service-role only.
async function runBillingReminderSweep(): Promise<unknown> {
  const { data, error } = await admin.rpc("fn_billing_reminders_due");
  if (error) throw error;
  const rows = (data ?? []) as Array<{ business_id: string; title: string; body: string }>;
  let businesses = 0;
  let sent = 0;
  for (const row of rows) {
    if (!row.business_id) continue;
    const r = await sendToBusiness({
      businessId: row.business_id,
      eventType: "billing_reminder",
      title: row.title,
      body: row.body,
    });
    businesses++;
    sent += r.sent;
  }
  return { kind: "billing_reminder_sweep", businesses, sent };
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    console.log(
      `[push-notify] req table=${payload?.table ?? "-"} type=${payload?.type ?? "-"} kind=${payload?.kind ?? "-"}`,
    );

    // Cron-driven billing reminders: gated to the service role (the cron sends
    // the service_role key as the bearer). Checked before any DB read.
    if (payload?.kind === "billing_reminder_sweep") {
      const auth = req.headers.get("Authorization") ?? "";
      if (auth !== `Bearer ${SERVICE_ROLE}`) {
        return Response.json({ error: "unauthorized" }, { status: 401 });
      }
      return Response.json(await runBillingReminderSweep());
    }

    // Debug helper: send a test push straight to a business's devices without
    // needing a real DB event. Body: {"kind":"test_push","businessId":"<uuid>"}.
    // Returns the per-token FCM verdicts. Remove once push is confirmed working.
    if (payload?.kind === "test_push" && payload?.businessId) {
      return Response.json(
        await sendToBusiness({
          businessId: String(payload.businessId),
          // Defaults to "test" (no toggle → always sends). Pass a real eventType
          // (e.g. "cash_closed") to verify per-business preference gating.
          eventType: String(payload.eventType ?? "test"),
          title: payload.title ?? "Prueba de notificación",
          body: payload.body ?? "Si ves esto, el push llega al teléfono. ✅",
        }),
      );
    }

    // Default path: Database Webhook events (order_items / cash_register_sessions).
    const event = await buildEvent(payload);
    if (!event) return Response.json({ skipped: true });
    return Response.json(await sendToBusiness(event));
  } catch (e) {
    console.log(`[push-notify] ERROR ${String(e)}`);
    return Response.json({ error: String(e) }, { status: 500 });
  }
});

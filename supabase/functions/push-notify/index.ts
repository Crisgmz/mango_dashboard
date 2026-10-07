// Supabase Edge Function: push-notify
//
// Three entry paths (same fan-out to a business's device tokens via FCM HTTP v1):
//   1. Database trigger/webhook on `cash_register_sessions` (UPDATE) → resolves
//      the event → business → push (cierre de caja, caja descuadrada).
//   2. {"kind":"notification_event","event_id":…} from the AFTER INSERT trigger
//      on `notification_events` (migration 20261007_0001), service-role bearer:
//      producto quitado después de cocina, orden anulada, venta anulada. SQL
//      already decided whether and to whom; we wait for the reason to land,
//      take the final text from `fn_notification_event_refresh` and send once.
//   3. Daily sweeps invoked by pg_cron with the service-role bearer:
//      {"kind":"billing_reminder_sweep"} → RPC `fn_billing_reminders_due`
//      {"kind":"low_stock_sweep"}        → RPC `fn_low_stock_alerts_due`
//      The RPC decides who + message; we fan out to each business's devices.
//
// Required secrets (supabase secrets set ...):
//   SUPABASE_URL                 (provided automatically)
//   SUPABASE_SERVICE_ROLE_KEY    (provided automatically)
//   FCM_PROJECT_ID               your Firebase project id
//   FCM_SERVICE_ACCOUNT          the full service-account JSON (one line)
//
// `order_items` webhooks (the old per-item "producto anulado") are ignored:
// they pushed once per item and missed deleted items and voided open orders.

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
// `data` travels as the FCM data payload (string values only); the app uses
// `event_id` to avoid showing the same notification_event twice.
type Notif = {
  businessId: string;
  eventType: string;
  title: string;
  body: string;
  data?: Record<string, string>;
};

async function buildEvent(payload: any): Promise<Notif | null> {
  const { table, type, record, old_record } = payload ?? {};
  if (type !== "UPDATE" || !record) return null;

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
            ...(n.data ? { data: n.data } : {}),
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

// ── Cron sweeps (invoked daily by pg_cron) ──
// SQL decides who to notify today + the message (the RPC); we just fan out to
// each business's device tokens. Service-role only. Same shape for billing
// reminders and low-stock alerts.
async function runSweep(kind: string, rpc: string, eventType: string): Promise<unknown> {
  const { data, error } = await admin.rpc(rpc);
  if (error) throw error;
  const rows = (data ?? []) as Array<{ business_id: string; title: string; body: string }>;
  let businesses = 0;
  let sent = 0;
  for (const row of rows) {
    if (!row.business_id) continue;
    const r = await sendToBusiness({
      businessId: row.business_id,
      eventType,
      title: row.title,
      body: row.body,
    });
    businesses++;
    sent += r.sent;
  }
  return { kind, businesses, sent };
}

// ── notification_events (anulaciones / productos quitados) ──
// The POS writes the reason, the operator (PIN) and the approver right AFTER
// deleting/voiding, and removals made within 5 s are appended to the same
// event while it is unclaimed (fn_notif_add_removed_items). Wait past that
// window, claim, then let SQL rebuild the final text. The Dart side waits a bit
// longer (NotificationService._eventTextDelay).
const EVENT_TEXT_DELAY_MS = 6000;

type EventRow = {
  id: string;
  business_id: string;
  event_type: string;
  title: string;
  body: string;
};

async function runNotificationEvent(eventId: string, wait = true): Promise<unknown> {
  if (wait) await new Promise((resolve) => setTimeout(resolve, EVENT_TEXT_DELAY_MS));

  // Claim first: a retried request never pushes the same event twice, and no
  // more removals get appended to it after this point.
  const { data: claimed, error: claimError } = await admin
    .from("notification_events")
    .update({ pushed_at: new Date().toISOString() })
    .eq("id", eventId)
    .is("pushed_at", null)
    .select("id, business_id, event_type, title, body");
  if (claimError) throw claimError;
  const stored = ((claimed ?? []) as EventRow[])[0];
  if (!stored) return { skipped: "already_pushed_or_missing" };

  // Final text (reason/approver); falls back to the stored text.
  let row: EventRow = stored;
  const { data, error } = await admin.rpc("fn_notification_event_refresh", {
    p_event_id: eventId,
  });
  if (error) {
    console.log(`[push-notify] refresh failed event=${eventId}: ${error.message}`);
  } else {
    row = ((data ?? []) as EventRow[])[0] ?? stored;
  }

  return await sendToBusiness({
    businessId: row.business_id,
    eventType: row.event_type,
    title: row.title,
    body: row.body,
    data: {
      event_id: String(row.id),
      event_type: String(row.event_type),
      business_id: String(row.business_id),
    },
  });
}

Deno.serve(async (req) => {
  try {
    const payload = await req.json();
    console.log(
      `[push-notify] req table=${payload?.table ?? "-"} type=${payload?.type ?? "-"} kind=${payload?.kind ?? "-"}`,
    );

    // Cron-driven sweeps: gated to the service role (the cron sends the
    // service_role key as the bearer). Checked before any DB read.
    const sweeps: Record<string, { rpc: string; eventType: string }> = {
      billing_reminder_sweep: { rpc: "fn_billing_reminders_due", eventType: "billing_reminder" },
      low_stock_sweep: { rpc: "fn_low_stock_alerts_due", eventType: "stock_low" },
    };
    const sweep = sweeps[payload?.kind as string];
    const isServiceRole = (req.headers.get("Authorization") ?? "") === `Bearer ${SERVICE_ROLE}`;
    if (sweep) {
      if (!isServiceRole) {
        return Response.json({ error: "unauthorized" }, { status: 401 });
      }
      return Response.json(await runSweep(payload.kind, sweep.rpc, sweep.eventType));
    }

    // notification_events trigger (pg_net, service-role bearer).
    if (payload?.kind === "notification_event") {
      if (!isServiceRole) {
        return Response.json({ error: "unauthorized" }, { status: 401 });
      }
      if (!payload?.event_id) {
        return Response.json({ error: "event_id required" }, { status: 400 });
      }
      return Response.json(await runNotificationEvent(String(payload.event_id)));
    }

    // Retry cron (private.fn_run_notification_event_sweep): events older than
    // a minute that never got pushed (lost call, function restarting…).
    if (payload?.kind === "notification_event_sweep") {
      if (!isServiceRole) {
        return Response.json({ error: "unauthorized" }, { status: 401 });
      }
      const now = Date.now();
      const { data: pending, error } = await admin
        .from("notification_events")
        .select("id")
        .is("pushed_at", null)
        .lt("created_at", new Date(now - 60_000).toISOString())
        .gt("created_at", new Date(now - 2 * 3600_000).toISOString())
        .order("created_at")
        .limit(50);
      if (error) throw error;
      const results = [];
      for (const { id } of (pending ?? []) as Array<{ id: string }>) {
        results.push(await runNotificationEvent(String(id), false));
      }
      return Response.json({ kind: payload.kind, retried: results.length, results });
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

    // Default path: Database Webhook events (cash_register_sessions; the old
    // order_items webhook is skipped — see the header).
    const event = await buildEvent(payload);
    if (!event) return Response.json({ skipped: true });
    return Response.json(await sendToBusiness(event));
  } catch (e) {
    console.log(`[push-notify] ERROR ${String(e)}`);
    return Response.json({ error: String(e) }, { status: 500 });
  }
});

// supabase/functions/verify-receipt/index.ts
// Supabase Edge Function — StoreKit 2 receipt cross-validation
//
// Called by ReceiptValidationService.swift after purchases and periodically.
// Compares the client's active StoreKit 2 product IDs against the server-side
// subscription state (profiles.tier) and corrects mismatches.
//
// Auth model (since 20 Apr 2026 Clerk migration):
//   - Client (iOS) sends `Authorization: Bearer <Clerk JWT>` (template "supabase")
//   - We verify the JWT signature against Clerk JWKS
//   - We extract `sub` (Clerk user id, e.g. "user_xxx...")
//   - We map clerk_id → profiles.id (UUID) via service-role client
//   - The `user_id` field in the body is IGNORED (defense against forged bodies)
//
// TODO P1: validate Apple JWS signature on receipts (StoreKit 2) — currently relies on Clerk JWT only.
//          Until then, premium tier corrections rely on (a) authenticated Clerk user
//          and (b) RevenueCat webhooks as primary source of truth. Consider sending
//          the `signedTransaction` JWS from iOS and verifying against Apple's
//          public keys (https://developer.apple.com/documentation/appstoreservernotifications/jwstransactiondecodedpayload).
//
// Deploy: supabase functions deploy verify-receipt --project-ref ftwfxdfkghkemnpwtzlu

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jwtVerify, createRemoteJWKSet } from "https://esm.sh/jose@5";

// CORS allowlist — iOS native does NOT send an Origin header, so requests
// without Origin pass through. If Origin is present and not in this allowlist,
// we reject with 403 (browser-originated cross-site requests).
const ALLOWED_ORIGINS = new Set<string>([
  "https://www.healthmap.fr",
  "https://healthmap.fr",
]);

function buildCorsHeaders(origin: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
  if (origin && ALLOWED_ORIGINS.has(origin)) {
    headers["Access-Control-Allow-Origin"] = origin;
  }
  return headers;
}

// Product IDs that grant premium access (must match App Store Connect)
const PREMIUM_PRODUCT_IDS = new Set([
  "fr.healthmap.premium.monthly",
  "fr.healthmap.premium.annual",
  "fr.healthmap.premium.lifetime",
]);

// Clerk JWKS — cached by `jose` across invocations (warm Edge instances).
const CLERK_JWKS_URL = "https://clerk.healthmap.fr/.well-known/jwks.json";
const clerkJWKS = createRemoteJWKSet(new URL(CLERK_JWKS_URL));

/**
 * SHA-256 → first 8 hex chars. Used to redact UUIDs in logs (PII).
 */
async function hashIdForLog(id: string): Promise<string> {
  const data = new TextEncoder().encode(id);
  const digest = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return hex.slice(0, 8);
}

/**
 * Verify the Clerk JWT and return its `sub` (Clerk user id, e.g. "user_xxx...").
 * Throws on missing/invalid/expired token.
 */
async function verifyClerkJWT(authHeader: string | null): Promise<string> {
  if (!authHeader || !authHeader.toLowerCase().startsWith("bearer ")) {
    throw new Error("missing_authorization_header");
  }
  const token = authHeader.slice(7).trim();
  if (!token) {
    throw new Error("empty_bearer_token");
  }
  const { payload } = await jwtVerify(token, clerkJWKS, {
    // Clerk's "supabase" JWT template uses standard `sub` (Clerk user id).
    // We don't pin issuer/audience here because the template is configurable;
    // signature validity against the Clerk JWKS is the security boundary.
  });
  if (typeof payload.sub !== "string" || payload.sub.length === 0) {
    throw new Error("jwt_missing_sub");
  }
  return payload.sub;
}

serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  const corsHeaders = buildCorsHeaders(origin);

  // Reject browser cross-site requests with disallowed Origin.
  // iOS native clients send no Origin header and pass through.
  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return new Response(
      JSON.stringify({ error: "Origin not allowed" }),
      { status: 403, headers: { "Content-Type": "application/json" } }
    );
  }

  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // 1. Verify Clerk JWT and extract `sub` (Clerk user id)
    let clerkUserId: string;
    try {
      clerkUserId = await verifyClerkJWT(req.headers.get("authorization"));
    } catch (authErr) {
      console.warn("verify-receipt auth failure:", String(authErr));
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 2. Parse body — IGNORE any user_id field (defense against forgery)
    const body = await req.json().catch(() => ({} as Record<string, unknown>));
    const active_product_ids = Array.isArray(body?.active_product_ids)
      ? (body.active_product_ids as unknown[]).filter((x): x is string => typeof x === "string")
      : [];
    // Note: body.user_id is intentionally ignored. The authenticated Clerk
    // identity is the only trusted source.

    // 3. Initialize Supabase admin client (service-role)
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // 4. Map Clerk user id → profiles.id (UUID) via clerk_id column
    const { data: profileByClerk, error: clerkLookupError } = await supabase
      .from("profiles")
      .select("id, tier")
      .eq("clerk_id", clerkUserId)
      .maybeSingle();

    if (clerkLookupError) {
      console.error("verify-receipt clerk_id lookup error:", clerkLookupError.message);
      return new Response(
        JSON.stringify({ error: "Profile lookup failed" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }
    if (!profileByClerk) {
      // No profile row matches this Clerk user — treat as unauthorized rather
      // than 404, to avoid leaking existence info.
      console.warn(`verify-receipt: no profile for clerk_id (hash=${await hashIdForLog(clerkUserId)})`);
      return new Response(
        JSON.stringify({ error: "Unauthorized" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const profileUUID: string = profileByClerk.id;
    const profileHash = await hashIdForLog(profileUUID);

    // 5. Check if any active product ID grants premium
    const hasPremiumProduct = active_product_ids.some(
      (id: string) => PREMIUM_PRODUCT_IDS.has(id)
    );

    // Without Apple JWS validation, premium product IDs from the client are
    // self-asserted. Log a warning so this is auditable until P1 lands.
    if (hasPremiumProduct) {
      console.warn(
        `verify-receipt: premium product asserted without Apple JWS validation ` +
        `(profile=${profileHash}, products=${active_product_ids.join(",")})`
      );
    }

    const serverTier: string = profileByClerk.tier || "free";
    const expectedTier = hasPremiumProduct ? "premium" : "free";
    let corrected = false;

    // Idempotent correction: client has premium receipt but server says free.
    // Re-call with same receipt → tier already premium → no update, corrected=false.
    if (hasPremiumProduct && serverTier === "free") {
      const { error: updateError } = await supabase
        .from("profiles")
        .update({ tier: "premium", updated_at: new Date().toISOString() })
        .eq("id", profileUUID);

      if (!updateError) {
        corrected = true;
        console.log(`Tier corrected to premium for profile=${profileHash}`);
      } else {
        console.error(`Tier update failed for profile=${profileHash}:`, updateError.message);
      }
    }

    // No auto-downgrade — RevenueCat webhooks handle subscription expiry.
    // This branch only logs for monitoring.
    if (!hasPremiumProduct && serverTier === "premium") {
      console.warn(`Possible tier mismatch for profile=${profileHash}: server=premium, client has no premium products`);
    }

    return new Response(
      JSON.stringify({
        valid: true,
        tier: corrected ? expectedTier : serverTier,
        corrected,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    console.error("verify-receipt error:", err);
    return new Response(
      JSON.stringify({ error: "Internal server error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

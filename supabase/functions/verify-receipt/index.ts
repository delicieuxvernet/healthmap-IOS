// supabase/functions/verify-receipt/index.ts
// Supabase Edge Function v5 — 2026-08-07 : réconciliation ACTIVE via RevenueCat.
//
// Historique :
//   v4 (2026-06-14) : read-only — la faille d'auto-promotion (product ids
//   auto-déclarés, pas de validation JWS Apple) était colmatée en n'écrivant
//   plus jamais le tier. Mais plus RIEN ne l'écrivait : le webhook RevenueCat
//   est resté sans secret (401 systématique) jusqu'au 7 août — un abonné payant
//   restait `free` côté serveur (quotas gratuits, 3 scans/j au lieu de 30).
//
//   v5 : le tier est réconcilié contre les SERVEURS RevenueCat (source de
//   confiance : RC a lui-même validé le receipt auprès d'Apple). Zéro confiance
//   au body client. Montée ET descente de tier (en l'absence d'événement
//   webhook, c'est l'unique chemin de retour à free après expiration).
//
// Auth (inchangée, v4) : Supabase Auth d'abord (iOS), Clerk JWKS en repli (web).
// Le body est ignoré pour toute décision ; `user_id` n'est jamais lu.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { jwtVerify, createRemoteJWKSet } from "https://esm.sh/jose@5";
import { rcCandidateIds, shouldWriteTier, targetTier } from "./logic.ts";

const CLERK_ISSUER = "https://clerk.healthmap.fr";
const CLERK_AUDIENCE = "authenticated";
const CLERK_JWKS_URL = `${CLERK_ISSUER}/.well-known/jwks.json`;
const clerkJWKS = createRemoteJWKSet(new URL(CLERK_JWKS_URL));

// Clé PUBLIQUE SDK RevenueCat (appl_) : suffisante pour lire un subscriber.
const RC_API_KEY = Deno.env.get("REVENUECAT_API_KEY") ?? "";

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

async function hashIdForLog(id: string): Promise<string> {
  const data = new TextEncoder().encode(id);
  const digest = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
  return hex.slice(0, 8);
}

class AuthError extends Error {
  status: number;
  constructor(message: string, status = 401) { super(message); this.name = "AuthError"; this.status = status; }
}

// deno-lint-ignore no-explicit-any
async function verifyAuthAndResolveProfile(authHeader: string | null, admin: any) {
  if (!authHeader || !authHeader.toLowerCase().startsWith("bearer ")) throw new AuthError("missing_bearer_token");
  const token = authHeader.slice(7).trim();
  if (!token) throw new AuthError("empty_bearer_token");

  // Chemin A : Supabase Auth (iOS, depuis 2026-06-08)
  try {
    const { data, error } = await admin.auth.getUser(token);
    if (!error && data?.user?.id) {
      const authUserId = data.user.id as string;
      const { data: profile, error: pErr } = await admin
        .from("profiles")
        .select("id, email, auth_user_id, clerk_id, stripe_customer_id, stripe_subscription_id, tier")
        .eq("auth_user_id", authUserId)
        .maybeSingle();
      if (!pErr && profile) {
        return { profileId: profile.id as string, authUserId, linkage: profile, authMethod: "supabase" as const };
      }
    }
  } catch (err) {
    console.warn("supabase auth path threw:", String(err));
  }

  // Chemin B : Clerk JWKS (web)
  try {
    const result = await jwtVerify(token, clerkJWKS, { issuer: CLERK_ISSUER, audience: CLERK_AUDIENCE });
    const payload = result.payload as Record<string, unknown>;
    const clerkId = typeof payload.sub === "string" ? payload.sub : "";
    if (!clerkId) throw new AuthError("jwt_missing_sub");
    const { data: profile, error } = await admin
      .from("profiles")
      .select("id, email, auth_user_id, clerk_id, stripe_customer_id, stripe_subscription_id, tier")
      .eq("clerk_id", clerkId)
      .maybeSingle();
    if (error) throw new AuthError("profile_lookup_failed", 500);
    if (!profile) throw new AuthError("unauthorized");
    return { profileId: profile.id as string, authUserId: profile.auth_user_id as string | null, linkage: profile, authMethod: "clerk" as const };
  } catch (err) {
    if (err instanceof AuthError) throw err;
    throw new AuthError("unauthorized");
  }
}

/** Lit l'entitlement « premium » RevenueCat sous le premier app_user_id qui en
 *  porte un. iOS identifie avec `session.user.id.uuidString` (MAJUSCULES) ; les
 *  candidats couvrent aussi la casse basse et le profileId (historique). NB :
 *  GET subscribers/{id} crée un subscriber vierge si inconnu — sans effet de
 *  bord gênant (aucun achat attaché), la lecture reste fiable. */
async function fetchRcPremium(candidates: string[]): Promise<{ ent: { expires_date: string | null; product_identifier?: string } | undefined; degraded: boolean }> {
  if (!RC_API_KEY) return { ent: undefined, degraded: true };
  let degraded = false;
  for (const id of candidates) {
    try {
      const r = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(id)}`, {
        headers: { Authorization: `Bearer ${RC_API_KEY}`, "X-Platform": "ios" },
      });
      if (!r.ok) { degraded = true; continue; }
      const body = await r.json();
      const ent = body?.subscriber?.entitlements?.premium;
      if (ent) return { ent, degraded: false };
    } catch (err) {
      console.warn("revenuecat fetch failed:", String(err));
      degraded = true;
    }
  }
  return { ent: undefined, degraded };
}

serve(async (req: Request) => {
  const origin = req.headers.get("origin");
  const corsHeaders = buildCorsHeaders(origin);

  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return new Response(JSON.stringify({ error: "Origin not allowed" }), { status: 403, headers: { "Content-Type": "application/json" } });
  }
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let resolved: Awaited<ReturnType<typeof verifyAuthAndResolveProfile>>;
    try {
      resolved = await verifyAuthAndResolveProfile(req.headers.get("authorization"), supabase);
    } catch (authErr) {
      console.warn("verify-receipt auth failure:", String(authErr));
      const status = authErr instanceof AuthError ? authErr.status : 401;
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Body consommé mais JAMAIS utilisé pour décider (compat client v4).
    await req.json().catch(() => ({}));

    const serverTier = (resolved.linkage?.tier as string) || "free";
    const hasStripe = Boolean(resolved.linkage?.stripe_subscription_id);
    const profileHash = await hashIdForLog(resolved.profileId);

    const { ent, degraded } = await fetchRcPremium(rcCandidateIds(resolved.authUserId, resolved.profileId));
    if (degraded && !ent) {
      // RevenueCat injoignable : on ne décide rien, l'app garde le tier actuel.
      return new Response(
        JSON.stringify({ valid: true, tier: serverTier, corrected: false, degraded: true }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    const target = targetTier(ent, new Date());
    let corrected = false;
    if (shouldWriteTier(serverTier, target, hasStripe)) {
      const { error: upErr } = await supabase
        .from("profiles")
        .update({ tier: target, subscription_status: target === "free" ? "expired" : "active" })
        .eq("id", resolved.profileId);
      if (upErr) {
        console.error(`verify-receipt: tier update failed (${serverTier} -> ${target}) profile=${profileHash}: ${upErr.message}`);
      } else {
        corrected = true;
        console.log(`verify-receipt: tier ${serverTier} -> ${target} (RevenueCat) profile=${profileHash}`);
      }
    }

    return new Response(
      JSON.stringify({ valid: true, tier: corrected ? target : serverTier, corrected }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (err) {
    console.error("verify-receipt error:", err);
    return new Response(JSON.stringify({ error: "Internal server error" }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});

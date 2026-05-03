// supabase/functions/verify-receipt/index.ts
// Supabase Edge Function — StoreKit 2 receipt cross-validation
//
// Called by ReceiptValidationService.swift after purchases and periodically.
// Compares the client's active StoreKit 2 product IDs against the server-side
// subscription state (profiles.tier) and corrects mismatches.
//
// Deploy: supabase functions deploy verify-receipt

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Product IDs that grant premium access (must match App Store Connect)
const PREMIUM_PRODUCT_IDS = new Set([
  "fr.healthmap.premium.monthly",
  "fr.healthmap.premium.annual",
  "fr.healthmap.premium.lifetime",
]);

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { user_id, active_product_ids, app_version, timestamp } = await req.json();

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "user_id required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Initialize Supabase admin client
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Check if any active product ID grants premium
    const hasPremiumProduct = (active_product_ids || []).some(
      (id: string) => PREMIUM_PRODUCT_IDS.has(id)
    );

    // Load current server-side tier
    const { data: profile, error: fetchError } = await supabase
      .from("profiles")
      .select("tier")
      .eq("id", user_id)
      .single();

    if (fetchError) {
      console.error("Profile fetch error:", fetchError);
      return new Response(
        JSON.stringify({ error: "Profile fetch failed", detail: fetchError.message }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const serverTier = profile?.tier || "free";
    const expectedTier = hasPremiumProduct ? "premium" : "free";
    let corrected = false;

    // Correct mismatch: client has premium receipt but server says free
    if (hasPremiumProduct && serverTier === "free") {
      const { error: updateError } = await supabase
        .from("profiles")
        .update({ tier: "premium", updated_at: new Date().toISOString() })
        .eq("id", user_id);

      if (!updateError) {
        corrected = true;
        console.log(`Tier corrected to premium for ${user_id} (products: ${active_product_ids})`);
      }
    }

    // Correct mismatch: no premium receipt but server says premium
    // Note: we do NOT auto-downgrade here — RevenueCat webhooks handle
    // subscription expiry. This path only logs for monitoring.
    if (!hasPremiumProduct && serverTier === "premium") {
      console.warn(`Possible tier mismatch for ${user_id}: server=premium, client has no premium products`);
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

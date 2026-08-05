// supabase/functions/verify-receipt/logic.ts
// Fonctions pures de la réconciliation tier ↔ RevenueCat (testables sans réseau).

/** Mapping produit App Store → valeur de `profiles.tier` (contrainte CHECK :
 *  free / weekly / monthly / annual — mêmes valeurs que revenuecat-webhook). */
export function tierFromProduct(productId: string | null | undefined): string | null {
  if (!productId) return null;
  const p = productId.toLowerCase();
  if (p === "healthmap_weekly") return "weekly";
  if (p === "healthmap_monthly") return "monthly";
  if (p === "healthmap_annual") return "annual";
  if (p.includes("annual") || p.includes("year")) return "annual";
  if (p.includes("month")) return "monthly";
  if (p.includes("week")) return "weekly";
  return null;
}

export interface RcEntitlement {
  expires_date: string | null;
  product_identifier?: string;
}

/** L'entitlement est-il actif à l'instant `now` ? (expires_date null = à vie) */
export function entitlementActive(ent: RcEntitlement | undefined, now: Date): boolean {
  if (!ent) return false;
  if (ent.expires_date === null || ent.expires_date === undefined) return true;
  const exp = Date.parse(ent.expires_date);
  return Number.isFinite(exp) && exp > now.getTime();
}

/** Tier cible d'après l'entitlement « premium » RevenueCat. */
export function targetTier(ent: RcEntitlement | undefined, now: Date): string {
  if (!entitlementActive(ent, now)) return "free";
  return tierFromProduct(ent?.product_identifier) ?? "monthly";
}

/**
 * Décide s'il faut écrire `profiles.tier`.
 * - Jamais d'écriture si le profil est géré par Stripe (web) : le webhook
 *   Stripe fait foi, on ne clobbe pas un abonné web depuis le chemin iOS.
 * - Jamais d'écriture si le tier actuel n'est pas une valeur gérée par
 *   RevenueCat (free/weekly/monthly/annual) : valeur inconnue = on n'y touche pas.
 */
const RC_MANAGED_TIERS = new Set(["free", "weekly", "monthly", "annual"]);

export function shouldWriteTier(
  currentTier: string,
  target: string,
  hasStripeSubscription: boolean,
): boolean {
  if (hasStripeSubscription) return false;
  if (!RC_MANAGED_TIERS.has(currentTier)) return false;
  if (!RC_MANAGED_TIERS.has(target)) return false;
  return currentTier !== target;
}

/** Candidats app_user_id RevenueCat, du plus probable au moins probable.
 *  iOS identifie avec `session.user.id.uuidString` (MAJUSCULES) ; on couvre
 *  aussi la casse basse et le profileId (variantes historiques). */
export function rcCandidateIds(authUserId: string | null, profileId: string): string[] {
  const out: string[] = [];
  const push = (v: string | null | undefined) => {
    if (v && !out.includes(v)) out.push(v);
  };
  push(authUserId?.toUpperCase());
  push(authUserId ?? undefined);
  push(profileId.toUpperCase());
  push(profileId);
  return out;
}

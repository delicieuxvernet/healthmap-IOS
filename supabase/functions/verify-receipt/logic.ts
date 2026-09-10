// supabase/functions/verify-receipt/logic.ts
// Fonctions pures de la réconciliation tier ↔ RevenueCat (testables sans réseau).

/** Mapping produit App Store → valeur de `profiles.tier` (contrainte CHECK :
 *  free / weekly / monthly / annual — mêmes valeurs que revenuecat-webhook).
 *
 *  Depuis le 18 août 2026, seuls l'hebdo et l'annuel sont vendus : le mensuel
 *  a disparu du paywall et du catalogue chargé par l'app. Les entrées
 *  « monthly » restent volontairement ici — on ne déclasse JAMAIS un abonné
 *  existant : si un reçu mensuel se présentait un jour, il doit rester
 *  reconnu comme premium plutôt que de retomber en `free`. */
export function tierFromProduct(productId: string | null | undefined): string | null {
  if (!productId) return null;
  const p = productId.toLowerCase();
  if (p === "healthmap_weekly") return "weekly";
  // Produit retiré de la vente le 18 août 2026, mapping conservé par sécurité.
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

/** Une souscription du bloc `subscriber.subscriptions` de RevenueCat. */
export interface RcSubscription {
  expires_date?: string | null;
  unsubscribe_detected_at?: string | null;
  billing_issues_detected_at?: string | null;
  refunded_at?: string | null;
}

/**
 * Abonnement encore couvert à l'instant `now` ? Un désabonnement programmé
 * (`unsubscribe_detected_at`) NE ferme PAS l'accès : la période déjà payée
 * court jusqu'à `expires_date`. Un remboursement, si.
 */
export function subscriptionActive(
  sub: RcSubscription | undefined,
  now: Date,
): boolean {
  if (!sub) return false;
  if (sub.refunded_at) return false;
  if (sub.expires_date === null || sub.expires_date === undefined) return true;
  const exp = Date.parse(sub.expires_date);
  return Number.isFinite(exp) && exp > now.getTime();
}

/**
 * Produit ACHETÉ encore couvert, d'après le bloc `subscriptions` — le repli
 * quand l'entitlement « premium » ne dit rien.
 *
 * Incident du 25 août 2026 : `healthmap_weekly` n'était rattaché à aucun
 * entitlement dans le tableau de bord RevenueCat. Les 9 abonnés avaient donc
 * `entitlements: {}` alors que `subscriptions.healthmap_weekly` courait
 * jusqu'à leur 14e jour. Cette fonction ne lisant QUE des données validées par
 * RevenueCat auprès d'Apple, elle n'ouvre aucune faille d'auto-promotion : le
 * corps de la requête cliente reste ignoré.
 */
export function produitCouvert(
  subscriptions: Record<string, RcSubscription> | undefined,
  now: Date,
): string | null {
  if (!subscriptions) return null;
  let meilleur: { id: string; rang: number } | null = null;
  for (const [productId, sub] of Object.entries(subscriptions)) {
    if (!subscriptionActive(sub, now)) continue;
    if (!tierFromProduct(productId)) continue;
    // À plusieurs abonnements couverts (changement de formule), on garde le
    // plus engageant : annuel > mensuel > hebdo.
    const rang = productId.includes("annual")
      ? 3
      : productId.includes("month")
      ? 2
      : 1;
    if (!meilleur || rang > meilleur.rang) meilleur = { id: productId, rang };
  }
  return meilleur?.id ?? null;
}

/**
 * Tier cible d'après RevenueCat : l'entitlement « premium » d'abord, puis les
 * souscriptions réellement en cours. Ne renvoie « free » que si les DEUX
 * sources sont muettes — un mauvais rattachement de produit ne doit jamais
 * redescendre un payeur.
 */
export function targetTier(
  ent: RcEntitlement | undefined,
  now: Date,
  subscriptions?: Record<string, RcSubscription>,
): string {
  if (entitlementActive(ent, now)) {
    return tierFromProduct(ent?.product_identifier) ?? "monthly";
  }
  const achete = produitCouvert(subscriptions, now);
  if (achete) return tierFromProduct(achete) ?? "monthly";
  return "free";
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

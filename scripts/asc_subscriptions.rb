#!/usr/bin/env ruby
# Pilote les abonnements App Store via l'API officielle App Store Connect.
# L'éditeur de prix de l'UI App Store Connect (shadow DOM) n'est pas automatisable ;
# l'API, elle, expose prix/localisations/disponibilité ET renvoie l'erreur exacte
# si un accord (ex. vérification DSA) bloque l'écriture.
#
#   MODE=audit : lit et rapporte l'état complet des abonnements (aucune écriture)
#   MODE=apply : fixe les prix validés (4,99 € mensuel / 30 € annuel, base FRA,
#                autres territoires égalisés par Apple), crée localisation fr-FR et
#                disponibilité manquantes, essai gratuit 7 j — puis relit l'état.
#   MODE=offers : crée les codes promo (NAIA = 3 mois offerts / LANCEMENT50 = -50%).

require "base64"
require "digest"
require "jwt"
require "json"
require "net/http"
require "openssl"

BUNDLE_ID = "fr.healthmap.app"
TARGETS = {
  "healthmap_monthly" => { price: "4.99",  name: "Kiwio Mensuel", period: "ONE_MONTH" },
  "healthmap_annual"  => { price: "50.00", name: "Kiwio Annuel",  period: "ONE_YEAR"  },
}.freeze
MODE = (ENV["MODE"] || "audit").downcase
BASE = "https://api.appstoreconnect.apple.com"

KEY = OpenSSL::PKey::EC.new(File.read(ENV.fetch("ASC_KEY_PATH")))

def token
  now = Time.now.to_i
  JWT.encode(
    { iss: ENV.fetch("ASC_ISSUER_ID"), iat: now, exp: now + 900, aud: "appstoreconnect-v1" },
    KEY, "ES256", { kid: ENV.fetch("ASC_KEY_ID") }
  )
end

def req(method, path, body = nil)
  uri = path.start_with?("http") ? URI(path) : URI(BASE + path)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.read_timeout = 60
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
  r = klass.new(uri)
  r["Authorization"] = "Bearer #{token}"
  r["Content-Type"] = "application/json"
  r.body = JSON.generate(body) if body
  res = http.request(r)
  parsed =
    if res.body.nil? || res.body.empty?
      nil
    else
      begin
        JSON.parse(res.body)
      rescue JSON::ParserError
        res.body
      end
    end
  [res.code.to_i, parsed]
end

def get_all(path)
  data = []
  url = path
  while url
    code, body = req(:get, url)
    abort_with("GET #{url}", code, body) unless code == 200
    data.concat(body["data"])
    url = body.dig("links", "next")
  end
  data
end

def abort_with(what, code, body)
  puts "ERREUR FATALE #{what} -> HTTP #{code}"
  puts(body.is_a?(String) ? body : JSON.pretty_generate(body))
  exit 1
end

# Écritures : on log l'erreur complète (c'est le diagnostic recherché) sans avorter,
# pour dérouler toutes les étapes et avoir l'image complète en un run.
def write(what, method, path, body)
  code, resp = req(method, path, body)
  if (200..299).cover?(code)
    puts "  OK  #{what} (HTTP #{code})"
    [true, resp]
  else
    puts "  ÉCHEC #{what} -> HTTP #{code}"
    puts(resp.is_a?(String) ? resp : JSON.pretty_generate(resp))
    [false, resp]
  end
end

def sub_snapshot(sub_id)
  code, body = req(:get, "/v1/subscriptions/#{sub_id}")
  return { error: code } unless code == 200
  a = body["data"]["attributes"]
  snap = {
    id: sub_id, name: a["name"], productId: a["productId"], state: a["state"],
    period: a["subscriptionPeriod"], groupLevel: a["groupLevel"],
  }

  locs = get_all("/v1/subscriptions/#{sub_id}/subscriptionLocalizations?limit=50")
  snap[:localizations] = locs.map { |l| l["attributes"].slice("locale", "name", "state") }

  code, pr = req(:get, "/v1/subscriptions/#{sub_id}/prices?filter[territory]=FRA&include=subscriptionPricePoint&limit=200")
  snap[:prices_fra] =
    if code == 200
      incl = (pr["included"] || []).to_h { |i| [i["id"], i] }
      pr["data"].map do |p|
        pp_id = p.dig("relationships", "subscriptionPricePoint", "data", "id")
        { startDate: p.dig("attributes", "startDate"), preserved: p.dig("attributes", "preserved"),
          customerPrice: incl.dig(pp_id, "attributes", "customerPrice") }
      end
    else
      { error: code, body: pr }
    end

  # Nombre de prix tous territoires confondus : ~175 attendus quand la grille est
  # complète ; 1 = prix base seul, jamais égalisé (cause plausible de MISSING_METADATA).
  snap[:pricesAllTerritoriesCount] = get_all("/v1/subscriptions/#{sub_id}/prices?limit=200").size

  code, av = req(:get, "/v1/subscriptions/#{sub_id}/subscriptionAvailability")
  snap[:availability] = code == 200 ? { availableInNewTerritories: av.dig("data", "attributes", "availableInNewTerritories") } : "aucune (HTTP #{code})"

  offers = get_all("/v1/subscriptions/#{sub_id}/introductoryOffers?limit=200")
  snap[:introOffers] = offers.map { |o| o["attributes"].slice("duration", "offerMode", "numberOfPeriods") }.uniq
  snap[:introOfferTerritoriesCount] = offers.size

  # HTTP 200 avec data:null = pas de screenshot ; un screenshot réservé mais
  # jamais committé (AWAITING_UPLOAD) compte aussi comme métadonnée manquante.
  code, shot = req(:get, "/v1/subscriptions/#{sub_id}/appStoreReviewScreenshot")
  snap[:reviewScreenshot] =
    if code == 200 && shot["data"]
      { id: shot["data"]["id"] }.merge(shot["data"]["attributes"] || {})
    else
      "absent (HTTP #{code})"
    end
  snap
end

def upload_review_screenshot(sub_id, png_path)
  bytes = File.binread(png_path)
  ok, resp = write("réservation screenshot (#{bytes.bytesize} o)", :post, "/v1/subscriptionAppStoreReviewScreenshots",
    { data: { type: "subscriptionAppStoreReviewScreenshots",
              attributes: { fileName: File.basename(png_path), fileSize: bytes.bytesize },
              relationships: { subscription: { data: { type: "subscriptions", id: sub_id } } } } })
  return false unless ok

  shot_id = resp["data"]["id"]
  (resp["data"]["attributes"]["uploadOperations"] || []).each do |op|
    uri = URI(op["url"])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    put = Net::HTTP::Put.new(uri)
    (op["requestHeaders"] || []).each { |h| put[h["name"]] = h["value"] }
    put.body = bytes[op["offset"], op["length"]]
    res = http.request(put)
    unless (200..299).cover?(res.code.to_i)
      puts "  ÉCHEC upload chunk -> HTTP #{res.code} #{res.body.to_s[0, 300]}"
      return false
    end
  end

  ok, = write("commit screenshot", :patch, "/v1/subscriptionAppStoreReviewScreenshots/#{shot_id}",
    { data: { type: "subscriptionAppStoreReviewScreenshots", id: shot_id,
              attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } } })
  ok
end

# Upload d'une capture d'écran de fiche App Store (appScreenshots) :
# réservation -> PUT des chunks -> commit MD5. Renvoie l'id ou nil.
def upload_app_screenshot(set_id, png_path)
  bytes = File.binread(png_path)
  ok, resp = write("réservation #{File.basename(png_path)} (#{bytes.bytesize} o)", :post, "/v1/appScreenshots",
    { data: { type: "appScreenshots",
              attributes: { fileName: File.basename(png_path), fileSize: bytes.bytesize },
              relationships: { appScreenshotSet: { data: { type: "appScreenshotSets", id: set_id } } } } })
  return nil unless ok

  sid = resp["data"]["id"]
  (resp["data"]["attributes"]["uploadOperations"] || []).each do |op|
    uri = URI(op["url"])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    put = Net::HTTP::Put.new(uri)
    (op["requestHeaders"] || []).each { |h| put[h["name"]] = h["value"] }
    put.body = bytes[op["offset"], op["length"]]
    res = http.request(put)
    unless (200..299).cover?(res.code.to_i)
      puts "  ÉCHEC chunk -> HTTP #{res.code} #{res.body.to_s[0, 200]}"
      return nil
    end
  end

  ok2, = write("commit #{File.basename(png_path)}", :patch, "/v1/appScreenshots/#{sid}",
    { data: { type: "appScreenshots", id: sid,
              attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } } })
  ok2 ? sid : nil
end

# Renvoie [id, prix_réel] du point de prix FRA le plus proche de `price`
# (Apple n'a pas toujours un point exact, ex. 30,00 € → 29,99 €). Nil si aucun.
def find_price_point(sub_id, price)
  target = price.to_f
  best = nil
  url = "/v1/subscriptions/#{sub_id}/pricePoints?filter[territory]=FRA&limit=200&fields[subscriptionPricePoints]=customerPrice"
  while url
    code, body = req(:get, url)
    abort_with("pricePoints", code, body) unless code == 200
    body["data"].each do |p|
      cp = p.dig("attributes", "customerPrice")
      next unless cp
      dist = (cp.to_f - target).abs
      best = { id: p["id"], price: cp, dist: dist } if best.nil? || dist < best[:dist]
    end
    url = body.dig("links", "next")
  end
  best ? [best[:id], best[:price]] : nil
end

# ── Helpers codes promo (offer codes) ───────────────────────────────────────
# Grille [ [territoire, pricePointId], ... ] pour un prix cible, depuis les
# égalisations du point FRA le plus proche. Renvoie [grid, prix_FRA_retenu].
# Le territoire d'un price point est encodé dans son id (base64 de
# {"s":sub,"t":TERRITOIRE,"p":num}) — plus fiable que de demander la relation.
def territory_of(price_point_id)
  JSON.parse(Base64.decode64(price_point_id))["t"]
rescue StandardError
  nil
end

def offer_price_grid(sub_id, target_price)
  found = find_price_point(sub_id, target_price)
  return [[], nil] if found.nil?
  fra_id, real = found
  grid = { (territory_of(fra_id) || "FRA") => fra_id }
  eqs = get_all("/v1/subscriptionPricePoints/#{fra_id}/equalizations?limit=200&fields[subscriptionPricePoints]=customerPrice")
  eqs.each do |p|
    terr = territory_of(p["id"])
    grid[terr] ||= p["id"] if terr
  end
  [grid.to_a, real]
end

# Un offer code exige une relation prices avec, PAR territoire, un
# subscriptionOfferCodePrices (territory + price point) placé dans `included`
# et référencé par un id de corrélation client (ici "p-<territoire>").
# Apple exige un id de corrélation local au format ${...} pour la création inline.
# FREE_TRIAL : subscriptionPricePoint DOIT être absent (offre gratuite, aucun prix) ;
# PAY_AS_YOU_GO / PAY_UP_FRONT : on fournit le point de prix réduit par territoire.
def build_offer_prices(grid, with_price_point)
  data = grid.map { |terr, _| { type: "subscriptionOfferCodePrices", id: "${#{terr}}" } }
  included = grid.map do |terr, pp_id|
    rel = { territory: { data: { type: "territories", id: terr } } }
    rel[:subscriptionPricePoint] = { data: { type: "subscriptionPricePoints", id: pp_id } } if with_price_point
    { type: "subscriptionOfferCodePrices", id: "${#{terr}}", relationships: rel }
  end
  [data, included]
end

def create_offer_code(sub_id, name, attrs, grid)
  prices_data, included = build_offer_prices(grid, attrs[:offerMode] != "FREE_TRIAL")
  write("offer code « #{name} » (#{grid.size} territoires)", :post, "/v1/subscriptionOfferCodes",
    { data: { type: "subscriptionOfferCodes",
              attributes: attrs.merge(name: name),
              relationships: {
                subscription: { data: { type: "subscriptions", id: sub_id } },
                prices: { data: prices_data } } },
      included: included })
end

# `active` est interdit à la création (il devient contrôlable en PATCH ensuite).
def create_custom_code(offer_code_id, code, n, expiration)
  write("custom code « #{code} » x#{n}", :post, "/v1/subscriptionOfferCodeCustomCodes",
    { data: { type: "subscriptionOfferCodeCustomCodes",
              attributes: { customCode: code, numberOfCodes: n, expirationDate: expiration },
              relationships: { offerCode: { data: { type: "subscriptionOfferCodes", id: offer_code_id } } } } })
end

def custom_codes_of(offer_code_id)
  code, body = req(:get, "/v1/subscriptionOfferCodes/#{offer_code_id}/customCodes?limit=200")
  code == 200 ? body["data"].map { |c| c.dig("attributes", "customCode") } : []
end

# ── 1. App + groupes ─────────────────────────────────────────────────────────
code, body = req(:get, "/v1/apps?filter[bundleId]=#{BUNDLE_ID}")
abort_with("apps", code, body) unless code == 200 && body["data"]&.any?
app_id = body["data"][0]["id"]
puts "App #{BUNDLE_ID} -> #{app_id} | MODE=#{MODE}"

# ── MODE app-audit : état de préparation à la soumission App Store ──────────
if MODE == "app-audit"
  report = { appId: app_id }

  code, v = req(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=5&fields[appStoreVersions]=versionString,appStoreState,platform,createdDate,releaseType")
  report[:versions] = code == 200 ? v["data"].map { |x| x["attributes"].merge("id" => x["id"]) } : { error: code, body: v }

  code, b = req(:get, "/v1/builds?filter[app]=#{app_id}&sort=-uploadedDate&limit=5&fields[builds]=version,processingState,expired,uploadedDate")
  report[:builds] = code == 200 ? b["data"].map { |x| x["attributes"] } : { error: code, body: b }

  if report[:versions].is_a?(Array)
    report[:versions].each do |ver|
      vid = ver["id"]
      code, rd = req(:get, "/v1/appStoreVersions/#{vid}/appStoreReviewDetail")
      ver["reviewDetail"] = code == 200 && rd["data"] ? rd["data"]["attributes"] : "absent (HTTP #{code})"

      code, bld = req(:get, "/v1/appStoreVersions/#{vid}/build?fields[builds]=version,processingState")
      ver["buildAttached"] = code == 200 && bld["data"] ? bld["data"]["attributes"] : "aucun (HTTP #{code})"

      locs = get_all("/v1/appStoreVersions/#{vid}/appStoreVersionLocalizations?limit=10")
      ver["localizations"] = locs.map do |l|
        entry = { locale: l.dig("attributes", "locale"),
                  hasDescription: !l.dig("attributes", "description").to_s.empty?,
                  hasKeywords: !l.dig("attributes", "keywords").to_s.empty? }
        sets = get_all("/v1/appStoreVersionLocalizations/#{l["id"]}/appScreenshotSets?limit=20")
        entry[:screenshotSets] = sets.map do |s|
          shots = get_all("/v1/appScreenshotSets/#{s["id"]}/appScreenshots?limit=20")
          { displayType: s.dig("attributes", "screenshotDisplayType"), count: shots.size }
        end
        entry
      end
    end
  end

  # Questionnaire confidentialité (App Privacy) : le chemin exact n'est pas
  # documenté — on sonde les candidats plausibles et on rapporte lequel répond.
  report[:privacyProbes] = {}
  ["/v1/apps/#{app_id}/dataUsages?limit=5",
   "/v1/apps/#{app_id}/appDataUsages?limit=5",
   "/v1/appDataUsages?filter[app]=#{app_id}&limit=5",
   "/v1/apps/#{app_id}/appDataUsageCategories?limit=5",
   "/v1/appDataUsageCategories?limit=5"].each do |path|
    code, resp = req(:get, path)
    report[:privacyProbes][path] =
      if code == 200
        { count: resp["data"].is_a?(Array) ? resp["data"].size : 1,
          sample: resp["data"].is_a?(Array) ? resp["data"].first(2) : resp["data"] }
      else
        "HTTP #{code} #{resp.is_a?(Hash) ? resp.dig("errors", 0, "detail") : resp.to_s[0, 120]}"
      end
  end

  puts "\n===== APP AUDIT ====="
  puts JSON.pretty_generate(report)
  exit 0
end

# ── MODE apply-app : infos review + rattache le dernier build à la v1.0 ─────
if MODE == "apply-app"
  code, v = req(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=1&filter[appStoreState]=PREPARE_FOR_SUBMISSION")
  abort_with("appStoreVersions", code, v) unless code == 200 && v["data"]&.any?
  version_id = v["data"][0]["id"]
  puts "Version éditable : #{v["data"][0].dig("attributes", "versionString")} (#{version_id})"

  # Sortie MANUELLE (choix Arthur) : l'app ne devient PAS publique automatiquement
  # à l'approbation ; Arthur déclenche la mise en ligne. releaseType = MANUAL.
  write("sortie manuelle (releaseType=MANUAL)", :patch, "/v1/appStoreVersions/#{version_id}",
    { data: { type: "appStoreVersions", id: version_id, attributes: { releaseType: "MANUAL" } } })

  # Infos App Review : contact + compte démo (compte de test partagé du repo,
  # celui que les reviewers utiliseront). Le téléphone reste à compléter.
  code, rd = req(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")
  review_attrs = {
    contactFirstName: "Arthur",
    contactLastName: "Vernet",
    contactEmail: "contact@healthmap.fr",
    contactPhone: ENV["REVIEW_CONTACT_PHONE"].to_s,
    demoAccountName: "audit-a@test.com",
    demoAccountPassword: ENV["DEMO_ACCOUNT_PASSWORD"].to_s,
    demoAccountRequired: true,
    notes: "Application en francais. Compte demo fourni (profil complet avec bilan). " \
           "L'abonnement Kiwio Premium (mensuel/annuel) se teste depuis l'onglet Profil " \
           "ou une section Premium du bilan.",
  }
  review_attrs.delete(:contactPhone) if review_attrs[:contactPhone].empty?
  review_attrs.delete(:demoAccountPassword) if review_attrs[:demoAccountPassword].empty?

  if code == 200 && rd["data"]
    detail_id = rd["data"]["id"]
    write("mise à jour des infos review", :patch, "/v1/appStoreReviewDetails/#{detail_id}",
      { data: { type: "appStoreReviewDetails", id: detail_id, attributes: review_attrs } })
  else
    write("création des infos review", :post, "/v1/appStoreReviewDetails",
      { data: { type: "appStoreReviewDetails", attributes: review_attrs,
                relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })
  end

  # Rattache le dernier build traité (VALID) à la version
  code, b = req(:get, "/v1/builds?filter[app]=#{app_id}&filter[processingState]=VALID&sort=-uploadedDate&limit=1")
  if code == 200 && b["data"]&.any?
    build = b["data"][0]
    puts "Dernier build VALID : ##{build.dig("attributes", "version")}"
    write("rattachement du build ##{build.dig("attributes", "version")}", :patch,
      "/v1/appStoreVersions/#{version_id}/relationships/build",
      { data: { type: "builds", id: build["id"] } })
  else
    puts "Aucun build VALID trouvé (HTTP #{code})"
  end

  code, rd = req(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")
  puts "\n===== ÉTAT FINAL REVIEW DETAIL ====="
  puts JSON.pretty_generate(code == 200 ? rd["data"] : rd)
  exit 0
end

# ── MODE offers : codes promo (NAIA = 3 mois offerts / mensuel, LANCEMENT50 = -50% 1re année / annuel) ──
if MODE == "offers"
  groups = get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200")
  subs = {}
  groups.each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      subs[s.dig("attributes", "productId")] = s["id"]
    end
  end
  monthly = subs["healthmap_monthly"]
  annual  = subs["healthmap_annual"]
  abort_with("offers", 0, "abonnements introuvables") unless monthly && annual
  puts "Mensuel : #{monthly} | Annuel : #{annual}"

  # Expiration des codes ~18 mois (Time.now = vrai Ruby CI, pas le sandbox Workflow).
  expiration = (Time.now + 550 * 24 * 3600).strftime("%Y-%m-%d")

  # Nettoyage : LANCEMENT50 était sur le mensuel ; le code passe sur l'annuel
  # (aucun code redeemable minté → suppression sûre, best-effort).
  legacy = {}
  get_all("/v1/subscriptions/#{monthly}/offerCodes?limit=200").each { |o| legacy[o.dig("attributes", "name")] = o["id"] }
  if (old_id = legacy["LANCEMENT50 - -50% 3 mois"])
    uri = URI(BASE + "/v1/subscriptionOfferCodes/#{old_id}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    del = Net::HTTP::Delete.new(uri)
    del["Authorization"] = "Bearer #{token}"
    puts "Nettoyage ancienne LANCEMENT50 (mensuel) -> HTTP #{http.request(del).code}"
  end

  offers = [
    { sub: monthly, name: "NAIA - 3 mois offerts", code: "NAIA", redemptions: 20, target: nil,
      attrs: { offerMode: "FREE_TRIAL", duration: "THREE_MONTHS", numberOfPeriods: 1,
               customerEligibilities: %w[NEW EXISTING EXPIRED], offerEligibility: "STACK_WITH_INTRO_OFFERS" } },
    # -50% sur l'annuel : 1re année à ~25 € (au lieu de 50 €), puis 50 €/an.
    { sub: annual, name: "LANCEMENT50 annuel - -50% 1re annee", code: "LANCEMENT50", redemptions: 100, target: "25.00",
      attrs: { offerMode: "PAY_AS_YOU_GO", duration: "ONE_YEAR", numberOfPeriods: 1,
               customerEligibilities: %w[NEW EXPIRED], offerEligibility: "STACK_WITH_INTRO_OFFERS" } },
  ]

  failures = []
  pending = []
  offers.each do |o|
    label = o[:sub] == annual ? "annuel" : "mensuel"
    puts "\n--- #{o[:code]} (#{label}) ---"
    existing = {}
    get_all("/v1/subscriptions/#{o[:sub]}/offerCodes?limit=200").each { |x| existing[x.dig("attributes", "name")] = x["id"] }
    oc_id = existing[o[:name]]
    if oc_id
      puts "  offer code déjà présent (#{oc_id})"
    else
      # Grille de prix : prix réduit pour un -50%, prix de base sinon (essai gratuit).
      grid, real = offer_price_grid(o[:sub], o[:target] || TARGETS["healthmap_monthly"][:price])
      if grid.empty?
        puts "  ÉCHEC aucun point de prix pour la cible"
        failures << "#{o[:code]}: prix"
        next
      end
      puts "  prix par période retenu (FRA) : #{real} €" if o[:target]
      ok, resp = create_offer_code(o[:sub], o[:name], o[:attrs], grid)
      (failures << "#{o[:code]}: offer code"; next) unless ok
      oc_id = resp["data"]["id"]
    end

    # Custom code (idempotent) : ne créer que s'il manque encore.
    if custom_codes_of(oc_id).include?(o[:code])
      puts "  custom code « #{o[:code]} » déjà présent"
    else
      okc, resp = create_custom_code(oc_id, o[:code], o[:redemptions], expiration)
      unless okc
        codes = resp.is_a?(Hash) ? (resp["errors"] || []).map { |e| e["code"] } : []
        if codes.any? { |c| c.to_s.include?("APP_STATE_INVALID") || c.to_s.include?("SALABLE_STATE_INVALID") }
          # Apple refuse de générer un code redeemable tant que l'app/abonnement
          # n'est pas approuvé. Campagne prête ; code à générer post-approbation.
          puts "  ⏳ code « #{o[:code]} » en attente d'approbation de l'app (re-lancer ce mode après)"
          pending << o[:code]
        else
          failures << "#{o[:code]}: custom code"
        end
      end
    end
  end

  # Relit les codes custom sur les 2 abonnements
  puts "\n===== ÉTAT FINAL OFFER CODES ====="
  [monthly, annual].uniq.each do |sub_id|
    code, body = req(:get, "/v1/subscriptions/#{sub_id}/offerCodes?include=customCodes&limit=200")
    next unless code == 200
    (body["included"] || []).select { |i| i["type"] == "subscriptionOfferCodeCustomCodes" }.each do |c|
      a = c["attributes"]
      puts "  code=#{a["customCode"]} usages=#{a["numberOfCodes"]} expire=#{a["expirationDate"]} actif=#{a["active"]}"
    end
  end
  puts "\n===== RÉSUMÉ ====="
  puts "Campagnes offer codes : #{offers.map { |o| o[:name] }.join(" | ")}"
  puts "En attente d'approbation app (codes à générer après) : #{pending.join(", ")}" unless pending.empty?
  puts "Échecs : #{failures.join(" | ")}" unless failures.empty?
  puts "Tout est prêt." if failures.empty? && pending.empty?
  exit 0
end

# ── MODE screenshots : upload des captures de la fiche App Store (ordre inclus) ──
if MODE == "screenshots"
  display_type = ENV["DISPLAY_TYPE"] || "APP_IPHONE_67"
  code, v = req(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=1&filter[appStoreState]=PREPARE_FOR_SUBMISSION")
  abort_with("appStoreVersions", code, v) unless code == 200 && v["data"]&.any?
  version_id = v["data"][0]["id"]
  locs = get_all("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=20")
  loc = locs.find { |l| l.dig("attributes", "locale").to_s.start_with?("fr") } || locs[0]
  loc_id = loc["id"]
  puts "Version #{version_id} | Localisation #{loc.dig("attributes", "locale")} (#{loc_id}) | displayType #{display_type}"

  sets = get_all("/v1/appStoreVersionLocalizations/#{loc_id}/appScreenshotSets?limit=50")
  set = sets.find { |s| s.dig("attributes", "screenshotDisplayType") == display_type }
  if set
    set_id = set["id"]
    purge = get_all("/v1/appScreenshotSets/#{set_id}/appScreenshots?limit=50")
    puts "Set existant #{display_type} (#{set_id}) — purge de #{purge.size} captures pour re-upload propre"
    purge.each do |sc|
      uri = URI(BASE + "/v1/appScreenshots/#{sc["id"]}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      del = Net::HTTP::Delete.new(uri)
      del["Authorization"] = "Bearer #{token}"
      http.request(del)
    end
  else
    ok, resp = write("création set #{display_type}", :post, "/v1/appScreenshotSets",
      { data: { type: "appScreenshotSets",
                attributes: { screenshotDisplayType: display_type },
                relationships: { appStoreVersionLocalization: { data: { type: "appStoreVersionLocalizations", id: loc_id } } } } })
    exit 1 unless ok
    set_id = resp["data"]["id"]
  end

  files = Dir.glob(File.join(__dir__, "appstore_screens", "final_*.png")).sort
  puts "#{files.size} captures à uploader :"
  ids = []
  files.each do |png|
    id = upload_app_screenshot(set_id, png)
    ids << id if id
  end

  # Ordre d'affichage sur la fiche = ordre des fichiers (final_01..09).
  if ids.size > 1
    write("ordre des #{ids.size} captures", :patch, "/v1/appScreenshotSets/#{set_id}/relationships/appScreenshots",
      { data: ids.map { |i| { type: "appScreenshots", id: i } } })
  end

  puts "\n===== ÉTAT FINAL CAPTURES ====="
  get_all("/v1/appScreenshotSets/#{set_id}/appScreenshots?limit=50&fields[appScreenshots]=fileName,assetDeliveryState").each do |s|
    puts "  #{s.dig("attributes", "fileName")} -> #{s.dig("attributes", "assetDeliveryState", "state")}"
  end
  puts "#{ids.size}/#{files.size} uploadées"
  exit 0
end

# ── MODE submit : conformité export + soumission de la version à App Review ──
if MODE == "submit"
  code, v = req(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=1&filter[appStoreState]=PREPARE_FOR_SUBMISSION")
  unless code == 200 && v["data"]&.any?
    code, v = req(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=1&sort=-createdDate")
  end
  abort_with("appStoreVersions", code, v) unless code == 200 && v["data"]&.any?
  version_id = v["data"][0]["id"]
  puts "Version : #{v["data"][0].dig("attributes", "versionString")} (#{version_id}) état=#{v["data"][0].dig("attributes", "appStoreState")}"

  # Conformité export : si le build attaché n'a pas de déclaration de chiffrement,
  # on en crée une EXEMPTE (l'app n'utilise que du HTTPS/TLS standard).
  code, b = req(:get, "/v1/appStoreVersions/#{version_id}/build")
  build_id = b.dig("data", "id")
  if build_id
    code, ed = req(:get, "/v1/builds/#{build_id}/appEncryptionDeclaration")
    if code == 200 && ed["data"]
      puts "Conformité export : déjà présente (#{ed.dig("data", "attributes", "appEncryptionDeclarationState")})"
    else
      # App exempte : uniquement du chiffrement standard OS (HTTPS/TLS), aucun
      # algorithme propriétaire ni tiers → containsProprietary/ThirdParty = false.
      ok, resp = write("déclaration de chiffrement (exempte)", :post, "/v1/appEncryptionDeclarations",
        { data: { type: "appEncryptionDeclarations",
                  attributes: { appDescription: "Kiwio — application de nutrition. HTTPS/TLS standard uniquement.",
                                availableOnFrenchStore: true,
                                containsProprietaryCryptography: false,
                                containsThirdPartyCryptography: false,
                                platform: "IOS" },
                  relationships: { app: { data: { type: "apps", id: app_id } } } } })
      if ok
        decl_id = resp["data"]["id"]
        write("rattachement build↔déclaration", :post, "/v1/appEncryptionDeclarations/#{decl_id}/relationships/builds",
          { data: [{ type: "builds", id: build_id }] })
      end
    end
  end

  # 1) Soumission : réutiliser une soumission ouverte, sinon en créer une.
  sub_id = nil
  code, existing = req(:get, "/v1/apps/#{app_id}/reviewSubmissions?filter[state]=READY_FOR_REVIEW&limit=10")
  if code == 200 && existing["data"]&.any?
    sub_id = existing["data"][0]["id"]
    puts "Soumission ouverte réutilisée : #{sub_id}"
  else
    ok, resp = write("création de la soumission", :post, "/v1/reviewSubmissions",
      { data: { type: "reviewSubmissions",
                attributes: { platform: "IOS" },
                relationships: { app: { data: { type: "apps", id: app_id } } } } })
    sub_id = resp["data"]["id"] if ok
  end
  abort_with("reviewSubmissions", 0, "impossible de créer/trouver une soumission") unless sub_id

  # 2) Ajouter la version comme item
  ok, = write("ajout de la version à la soumission", :post, "/v1/reviewSubmissionItems",
    { data: { type: "reviewSubmissionItems",
              relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: sub_id } },
                               appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })

  # 3) Soumettre
  write("SOUMISSION à Apple (submitted=true)", :patch, "/v1/reviewSubmissions/#{sub_id}",
    { data: { type: "reviewSubmissions", id: sub_id, attributes: { submitted: true } } })

  code, s = req(:get, "/v1/reviewSubmissions/#{sub_id}")
  puts "\n===== ÉTAT SOUMISSION ====="
  puts JSON.pretty_generate(code == 200 ? s["data"]["attributes"] : s)
  exit 0
end

groups = get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200")
abort_with("subscriptionGroups", 0, "aucun groupe d'abonnement") if groups.empty?

report = { mode: MODE, appId: app_id, groups: [] }
all_subs = {}
groups.each do |g|
  g_locs = get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptionGroupLocalizations?limit=50")
  subs = get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50")
  subs.each { |s| all_subs[s.dig("attributes", "productId")] = { id: s["id"], group: g["id"] } }
  report[:groups] << {
    id: g["id"], referenceName: g.dig("attributes", "referenceName"),
    localizations: g_locs.map { |l| l["attributes"].slice("locale", "name", "state") },
    subscriptions: subs.map { |s| sub_snapshot(s["id"]) },
  }
end

puts "\n===== ÉTAT ====="
puts JSON.pretty_generate(report)

exit 0 unless MODE == "apply"

# ── 2. APPLY ─────────────────────────────────────────────────────────────────
puts "\n===== APPLY ====="
group_id = groups[0]["id"]
failures = []

# Nom public du groupe requis pour "Prêt à soumettre"
if report[:groups][0][:localizations].empty?
  ok, = write("localisation fr-FR du groupe", :post, "/v1/subscriptionGroupLocalizations",
    { data: { type: "subscriptionGroupLocalizations",
              attributes: { locale: "fr-FR", name: "Kiwio Premium" },
              relationships: { subscriptionGroup: { data: { type: "subscriptionGroups", id: group_id } } } } })
  failures << "localisation groupe" unless ok
end

TARGETS.each do |product_id, spec|
  puts "\n--- #{product_id} ---"
  entry = all_subs[product_id]

  if entry.nil?
    ok, resp = write("création de l'abonnement", :post, "/v1/subscriptions",
      { data: { type: "subscriptions",
                attributes: { name: spec[:name], productId: product_id,
                              subscriptionPeriod: spec[:period], familySharable: false, groupLevel: 1 },
                relationships: { group: { data: { type: "subscriptionGroups", id: group_id } } } } })
    (failures << "#{product_id}: création" ; next) unless ok
    entry = { id: resp["data"]["id"] }
  end
  sub_id = entry[:id]
  snap = sub_snapshot(sub_id)

  # Localisation fr-FR
  if snap[:localizations].none? { |l| l["locale"].to_s.start_with?("fr") }
    ok, = write("localisation fr-FR", :post, "/v1/subscriptionLocalizations",
      { data: { type: "subscriptionLocalizations",
                attributes: { locale: "fr-FR", name: spec[:name], description: "Kiwio Premium : scans illimités, analyses complètes." },
                relationships: { subscription: { data: { type: "subscriptions", id: sub_id } } } } })
    failures << "#{product_id}: localisation" unless ok
  end

  # Prix : base France, puis égalisation explicite sur tous les territoires —
  # un prix base seul laisse l'abonnement en MISSING_METADATA.
  found = find_price_point(sub_id, spec[:price])
  if found.nil?
    puts "  ÉCHEC aucun price point FRA proche de #{spec[:price]}"
    failures << "#{product_id}: price point introuvable"
  else
    pp_id, real_price = found
    puts "  cible #{spec[:price]} € → point de prix FRA retenu #{real_price} €"
    current = snap[:prices_fra].is_a?(Array) ? snap[:prices_fra].map { |p| p[:customerPrice] } : []
    if current.include?(real_price)
      puts "  OK  prix FRA déjà à #{real_price} €"
    else
      ok, = write("prix FRA #{real_price} €", :post, "/v1/subscriptionPrices",
        { data: { type: "subscriptionPrices",
                  relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                   subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: pp_id } } } } })
      failures << "#{product_id}: prix base" unless ok
    end

    # Aligne toute la grille sur le prix base validé : on pose les points de prix
    # égalisés absents de la grille courante (idempotent — un changement de prix
    # base laisse sinon les autres territoires sur l'ancien prix).
    target_ids = get_all("/v1/subscriptionPricePoints/#{pp_id}/equalizations?limit=200&fields[subscriptionPricePoints]=customerPrice")
      .map { |e| e["id"] }
    current_pp_ids = []
    url = "/v1/subscriptions/#{sub_id}/prices?limit=200&fields[subscriptionPrices]=subscriptionPricePoint&include=subscriptionPricePoint&fields[subscriptionPricePoints]=customerPrice"
    while url
      code, body = req(:get, url)
      abort_with("prices (grille)", code, body) unless code == 200
      body["data"].each { |p| current_pp_ids << p.dig("relationships", "subscriptionPricePoint", "data", "id") }
      url = body.dig("links", "next")
    end
    missing = target_ids - current_pp_ids
    if missing.empty?
      puts "  OK  grille alignée sur #{spec[:price]} € (#{current_pp_ids.uniq.size} points de prix)"
    else
      ok_n = ko_n = 0
      first_error = nil
      missing.each do |eq_id|
        code, resp = req(:post, "/v1/subscriptionPrices",
          { data: { type: "subscriptionPrices",
                    relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                     subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: eq_id } } } } })
        if (200..299).cover?(code)
          ok_n += 1
        else
          ko_n += 1
          first_error ||= [code, resp]
        end
      end
      puts "  alignement grille : #{ok_n} OK, #{ko_n} en échec (sur #{missing.size})"
      if first_error
        puts "  première erreur d'alignement -> HTTP #{first_error[0]}"
        puts(first_error[1].is_a?(String) ? first_error[1] : JSON.pretty_generate(first_error[1]))
      end
      failures << "#{product_id}: alignement grille (#{ko_n} échecs)" if ko_n > 0
    end
  end

  # Disponibilité : tous les territoires
  unless snap[:availability].is_a?(Hash)
    territories = get_all("/v1/territories?limit=200").map { |t| t["id"] }
    ok, = write("disponibilité (#{territories.size} territoires)", :post, "/v1/subscriptionAvailabilities",
      { data: { type: "subscriptionAvailabilities",
                attributes: { availableInNewTerritories: true },
                relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                 availableTerritories: { data: territories.map { |t| { type: "territories", id: t } } } } } })
    failures << "#{product_id}: disponibilité" unless ok
  end

  # Essai gratuit 7 j (best effort) : tentative globale, sinon par territoire
  if snap[:introOffers].empty?
    ok, = write("essai gratuit 7 j (tous territoires)", :post, "/v1/subscriptionIntroductoryOffers",
      { data: { type: "subscriptionIntroductoryOffers",
                attributes: { duration: "ONE_WEEK", offerMode: "FREE_TRIAL", numberOfPeriods: 1 },
                relationships: { subscription: { data: { type: "subscriptions", id: sub_id } } } } })
    unless ok
      territories = get_all("/v1/territories?limit=200").map { |t| t["id"] }
      ok_n = 0
      territories.each do |t|
        code, = req(:post, "/v1/subscriptionIntroductoryOffers",
          { data: { type: "subscriptionIntroductoryOffers",
                    attributes: { duration: "ONE_WEEK", offerMode: "FREE_TRIAL", numberOfPeriods: 1 },
                    relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                     territory: { data: { type: "territories", id: t } } } } })
        ok_n += 1 if (200..299).cover?(code)
      end
      puts "  essai 7 j par territoire : #{ok_n}/#{territories.size} OK"
      failures << "#{product_id}: essai 7 j" if ok_n == 0
    end
  end

  # Screenshot review : requis pour sortir de MISSING_METADATA
  shot = snap[:reviewScreenshot]
  needs_upload =
    if shot.is_a?(String)
      true # absent
    elsif shot.dig("assetDeliveryState", "state") == "COMPLETE"
      false
    else
      # réservation jamais finalisée (AWAITING_UPLOAD / FAILED) : suppression puis ré-upload
      uri = URI(BASE + "/v1/subscriptionAppStoreReviewScreenshots/#{shot[:id]}")
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      del = Net::HTTP::Delete.new(uri)
      del["Authorization"] = "Bearer #{token}"
      res = http.request(del)
      puts "  suppression screenshot non finalisé -> HTTP #{res.code}"
      true
    end
  if needs_upload
    png = ENV["REVIEW_SCREENSHOT_PATH"]
    if png && File.exist?(png)
      failures << "#{product_id}: screenshot review" unless upload_review_screenshot(sub_id, png)
    else
      puts "  screenshot review manquant et REVIEW_SCREENSHOT_PATH non fourni"
      failures << "#{product_id}: screenshot review (aucun PNG)"
    end
  else
    puts "  OK  screenshot review déjà complet"
  end
end

# ── 3. État final ────────────────────────────────────────────────────────────
puts "\n===== ÉTAT FINAL ====="
final = {}
TARGETS.each_key do |product_id|
  entry = all_subs[product_id]
  final[product_id] = entry ? sub_snapshot(entry[:id]) : "ABSENT"
end
# Recharge la liste au cas où un abonnement vient d'être créé
if final.value?("ABSENT")
  groups.each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      pid = s.dig("attributes", "productId")
      final[pid] = sub_snapshot(s["id"]) if final[pid] == "ABSENT"
    end
  end
end
puts JSON.pretty_generate(final)

puts "\n===== RÉSUMÉ ====="
if failures.empty?
  puts "Toutes les écritures ont réussi."
else
  puts "Écritures en échec : #{failures.join(" | ")}"
end

#!/usr/bin/env ruby
# Pilote les abonnements App Store via l'API officielle App Store Connect.
# L'éditeur de prix de l'UI App Store Connect (shadow DOM) n'est pas automatisable ;
# l'API, elle, expose prix/localisations/disponibilité ET renvoie l'erreur exacte
# si un accord (ex. vérification DSA) bloque l'écriture.
#
#   MODE=audit : lit et rapporte l'état complet des abonnements (aucune écriture)
#   MODE=apply : fixe les prix validés (0,99 € hebdo / 4,99 € mensuel /
#                50 € annuel, base FRA,
#                autres territoires égalisés par Apple), crée localisation fr-FR et
#                disponibilité manquantes, essai gratuit 7 j, rafraîchit la capture
#                App Review si son checksum change — puis relit l'état.
#   MODE=offers : crée les codes promo (NAIA = 3 mois offerts / LANCEMENT50 = -50%).

require "base64"
require "digest"
require "jwt"
require "json"
require "net/http"
require "openssl"

BUNDLE_ID = "fr.healthmap.app"
TARGETS = {
  # Même service Premium, seules la durée et la facturation changent :
  # Apple recommande donc le même niveau pour obtenir un crossgrade.
  "healthmap_weekly"  => { price: "0.99",  name: "Kiwio Hebdo",   period: "ONE_WEEK",  level: 1 },
  "healthmap_monthly" => { price: "4.99",  name: "Kiwio Mensuel", period: "ONE_MONTH", level: 1 },
  "healthmap_annual"  => { price: "50.00", name: "Kiwio Annuel",  period: "ONE_YEAR",  level: 1 },
}.freeze
SUBSCRIPTION_DESCRIPTION = "Kiwio Premium : jusqu’à 30 scans par jour, tendances et plan détaillés.".freeze
# ONLY_PRODUCT : si défini, apply ne configure QUE ce produit (les autres intacts).
ONLY_PRODUCT = ENV["ONLY_PRODUCT"].to_s.strip
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
  klass = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch,
            delete: Net::HTTP::Delete }.fetch(method)
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

# États d'une version App Store qui restent ÉDITABLES / re-soumissibles.
# Après un refus Apple la version passe REJECTED (pas PREPARE_FOR_SUBMISSION) :
# on doit quand même pouvoir la retrouver pour rattacher un build et re-soumettre.
EDITABLE_VERSION_STATES = %w[
  PREPARE_FOR_SUBMISSION DEVELOPER_REJECTED REJECTED METADATA_REJECTED
  INVALID_BINARY PENDING_CONTRACT
].freeze

# Retourne [version_id, attributes] de la version éditable (1.0), ou nil.
def find_editable_version(app_id)
  code, v = req(:get, "/v1/apps/#{app_id}/appStoreVersions?limit=10" \
    "&fields[appStoreVersions]=versionString,appStoreState,platform,releaseType")
  return nil unless code == 200 && v["data"]&.any?
  hit = v["data"].find { |x| EDITABLE_VERSION_STATES.include?(x.dig("attributes", "appStoreState")) }
  hit ||= v["data"][0]
  [hit["id"], hit["attributes"]]
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
  snap[:localizations] = locs.map do |l|
    a = l["attributes"]
    { locale: a["locale"], name: a["name"], state: a["state"], hasDescription: !a["description"].to_s.strip.empty? }
  end

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
  if code == 200 && av["data"]
    avail_id = av.dig("data", "id")
    terr_count = get_all("/v1/subscriptionAvailabilities/#{avail_id}/availableTerritories?limit=200&fields[territories]=currency").size
    snap[:availability] = { id: avail_id,
                            availableInNewTerritories: av.dig("data", "attributes", "availableInNewTerritories"),
                            territoriesCount: terr_count }
  else
    snap[:availability] = "aucune (HTTP #{code})"
  end

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
# ── MODE fix-subs : corrige la config des abonnements (défauts deep-audit) ──
#    1) reviewNote : App Review y cherche le chemin de l'achat dans l'app —
#       vide sur les 3 abos, en cause directe dans le refus 2.1(b).
#    2) libellés : espaces parasites en début/fin.
#    3) tente ensuite la re-soumission : modifier l'abonnement lui-même crée
#       une « pending version », ce que le re-upload de screenshot ne faisait pas.
if MODE == "fix-subs"
  note = <<~NOTE.strip
    HOW TO REACH THIS SUBSCRIPTION IN THE APP (demo account: audit-b@test.com)
    1. Launch the app and sign in with the demo account.
    2. Open the "Bilan" tab (first tab).
    3. Tap the "Kiwio Premium" card shown on that screen — the paywall opens.
       (Alternative path: profile icon at the TOP-RIGHT of the Bilan tab >
       "Passer a Premium".)
    The paywall lists the Kiwio Premium subscriptions with their name, duration
    and price, and has "Restaurer mes achats" plus links to the Terms of Use
    (EULA) and Privacy Policy. The app has NO "Profil" tab.
  NOTE

  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      sid = s["id"]
      pid = s.dig("attributes", "productId")
      nom = s.dig("attributes", "name").to_s

      write("note de review + libellé (#{pid})", :patch, "/v1/subscriptions/#{sid}",
        { data: { type: "subscriptions", id: sid,
                  attributes: { name: nom.strip, reviewNote: note } } })

      get_all("/v1/subscriptions/#{sid}/subscriptionLocalizations?limit=50").each do |l|
        ln = l.dig("attributes", "name").to_s
        next if ln == ln.strip
        write("nom d'affichage sans espace parasite (#{pid}/#{l.dig("attributes", "locale")})",
          :patch, "/v1/subscriptionLocalizations/#{l["id"]}",
          { data: { type: "subscriptionLocalizations", id: l["id"],
                    attributes: { name: ln.strip } } })
      end
    end
  end

  # La modification a-t-elle rouvert une version soumissible ?
  puts "\n--- tentative de re-soumission des abonnements ---"
  soumis = []
  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      next unless s.dig("attributes", "state") == "READY_TO_SUBMIT"
      pid = s.dig("attributes", "productId")
      okc, = write("soumission abonnement #{pid}", :post, "/v1/subscriptionSubmissions",
        { data: { type: "subscriptionSubmissions",
                  relationships: { subscription: { data: { type: "subscriptions", id: s["id"] } } } } })
      soumis << pid if okc
    end
  end
  puts "\nAbonnements soumis : #{soumis.empty? ? "AUCUN — le bouton Resubmit de l'UI reste nécessaire" : soumis.join(", ")}"
  exit 0
end

# ── MODE deep-audit : diagnostic COMPLET de la config abonnements ──────────
#    Couvre ce que `audit` ne montre pas : note de review par abo, partage
#    familial, accords (Paid Apps), disponibilité de l'app, cohérence des
#    localisations, propreté des libellés. Lecture seule.
if MODE == "deep-audit"
  problemes = []
  infos = []

  # 1) Accords (Paid Apps) — cause n°1 d'un paywall vide chez le reviewer.
  ["/v1/agreements?limit=50", "/v1/paidApplicationsAgreements?limit=50"].each do |path|
    code, resp = req(:get, path)
    infos << "accords #{path} -> HTTP #{code} #{code == 200 ? JSON.generate(resp["data"]).slice(0, 400) : resp.dig("errors", 0, "detail")}"
  end

  # 2) App : territoires de vente + infos de fiche
  code, av = req(:get, "/v1/apps/#{app_id}/appAvailabilityV2")
  infos << "appAvailabilityV2 -> HTTP #{code}"
  code, ai = req(:get, "/v1/apps/#{app_id}?fields[apps]=name,bundleId,primaryLocale,contentRightsDeclaration")
  if code == 200
    a = ai["data"]["attributes"]
    infos << "app: #{a["name"]} | primaryLocale=#{a["primaryLocale"]} | contentRights=#{a["contentRightsDeclaration"].inspect}"
    @primary_locale = a["primaryLocale"]
  end

  # 3) Groupe d'abonnements + ses localisations
  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    glocs = get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptionGroupLocalizations?limit=50")
    locales = glocs.map { |l| l.dig("attributes", "locale") }
    infos << "groupe « #{g.dig("attributes", "referenceName")} » : localisations = #{locales.join(", ")}"
    if @primary_locale && !locales.include?(@primary_locale)
      problemes << "Groupe d'abonnements : AUCUNE localisation pour la langue principale de l'app (#{@primary_locale}) — présentes : #{locales.join(", ")}"
    end
    glocs.each do |l|
      nom = l.dig("attributes", "name").to_s
      problemes << "Groupe : nom « #{nom} » a un espace en trop en début/fin" if nom != nom.strip
    end

    # 4) Chaque abonnement, en détail
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      sid = s["id"]
      code, full = req(:get, "/v1/subscriptions/#{sid}?fields[subscriptions]=name,productId,state,subscriptionPeriod,familySharable,reviewNote,groupLevel")
      at = code == 200 ? full["data"]["attributes"] : s["attributes"]
      pid = at["productId"]

      infos << "#{pid} : state=#{at["state"]} période=#{at["subscriptionPeriod"]} niveau=#{at["groupLevel"]} familySharable=#{at["familySharable"].inspect} reviewNote=#{at["reviewNote"].to_s.empty? ? "VIDE" : "présente"}"

      problemes << "#{pid} : nom « #{at["name"]} » a un espace en trop en début/fin" if at["name"].to_s != at["name"].to_s.strip
      problemes << "#{pid} : aucune note de review (App Review lit ce champ pour trouver l'achat dans l'app)" if at["reviewNote"].to_s.strip.empty?

      slocs = get_all("/v1/subscriptions/#{sid}/subscriptionLocalizations?limit=50")
      slocales = slocs.map { |l| l.dig("attributes", "locale") }
      if @primary_locale && !slocales.include?(@primary_locale)
        problemes << "#{pid} : aucune localisation pour la langue principale (#{@primary_locale}) — présentes : #{slocales.join(", ")}"
      end
      slocs.each do |l|
        n = l.dig("attributes", "name").to_s
        d = l.dig("attributes", "description").to_s
        problemes << "#{pid} (#{l.dig("attributes", "locale")}) : nom d'affichage « #{n} » a un espace en trop" if n != n.strip
        problemes << "#{pid} (#{l.dig("attributes", "locale")}) : description vide" if d.strip.empty?
      end

      code, shot = req(:get, "/v1/subscriptions/#{sid}/appStoreReviewScreenshot")
      if code != 200 || shot["data"].nil?
        problemes << "#{pid} : AUCUNE capture d'écran de review (obligatoire)"
      elsif shot.dig("data", "attributes", "assetDeliveryState", "state") != "COMPLETE"
        problemes << "#{pid} : capture de review non finalisée (#{shot.dig("data", "attributes", "assetDeliveryState", "state")})"
      end

      offers = get_all("/v1/subscriptions/#{sid}/introductoryOffers?limit=50")
      infos << "#{pid} : #{offers.size} offre(s) d'introduction"

      # Territoires : passer par la ressource subscriptionAvailabilities (le
      # paramètre `include` sur subscriptionAvailability répond 400).
      code, avail = req(:get, "/v1/subscriptions/#{sid}/subscriptionAvailability")
      if code == 200 && avail["data"]
        n = get_all("/v1/subscriptionAvailabilities/#{avail.dig("data", "id")}/availableTerritories?limit=200&fields[territories]=currency").size
        infos << "#{pid} : #{n} territoire(s)"
        problemes << "#{pid} : disponible dans #{n} territoire(s) seulement" if n < 100
      else
        problemes << "#{pid} : aucune disponibilité configurée (HTTP #{code})"
      end
    end
  end

  puts "\n===== INFOS ====="
  infos.each { |i| puts "  · #{i}" }
  puts "\n===== POINTS À CORRIGER (#{problemes.size}) ====="
  if problemes.empty?
    puts "  Aucun défaut détecté par l'API sur la config des abonnements."
  else
    problemes.each { |p| puts "  ⚠️  #{p}" }
  end
  exit 0
end

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

  # Soumissions de review (pour diagnostiquer un refus / une soumission bloquée) :
  # quel submission détient la version + les abonnements, et dans quel état.
  report[:reviewSubmissions] = get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50").map do |s|
    a = s["attributes"]
    items = get_all("/v1/reviewSubmissions/#{s["id"]}/items?limit=50")
    kinds = items.map do |it|
      rel = it["relationships"] || {}
      k = rel.keys.find { |key| rel[key].is_a?(Hash) && rel[key]["data"] }
      k ? "#{k}:#{rel[k]["data"]["id"]}" :
        "relations=#{rel.keys.join(",")};state=#{it.dig("attributes", "state") || "?"}"
    end
    { id: s["id"], state: a["state"], submitted: a["submitted"],
      submittedDate: a["submittedDate"], platform: a["platform"],
      itemsCount: items.size, items: kinds }
  end

  puts "\n===== APP AUDIT ====="
  puts JSON.pretty_generate(report)
  exit 0
end

# ── MODE apply-app : infos review + rattache le dernier build à la v1.0 ─────
if MODE == "apply-app"
  version_id, vattrs = find_editable_version(app_id)
  abort_with("appStoreVersions", 0, "aucune version éditable (1.0) trouvée") unless version_id
  puts "Version éditable : #{vattrs["versionString"]} état=#{vattrs["appStoreState"]} (#{version_id})"

  # Sortie MANUELLE (choix Arthur) : l'app ne devient PAS publique automatiquement
  # à l'approbation ; Arthur déclenche la mise en ligne. releaseType = MANUAL.
  write("sortie manuelle (releaseType=MANUAL)", :patch, "/v1/appStoreVersions/#{version_id}",
    { data: { type: "appStoreVersions", id: version_id, attributes: { releaseType: "MANUAL" } } })

  # Infos App Review : contact + compte démo. ⚠️ audit-b UNIQUEMENT : c'est le
  # seul compte test avec une row auth.users côté Supabase Auth (le chemin
  # d'auth iOS) — audit-a/c sont Clerk-only et NE PEUVENT PAS se connecter
  # dans l'app (cause racine du refus 2.1(b) du 20 juillet 2026).
  code, rd = req(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")
  review_attrs = {
    contactFirstName: "Arthur",
    contactLastName: "Vernet",
    contactEmail: "contact@healthmap.fr",
    contactPhone: ENV["REVIEW_CONTACT_PHONE"].to_s,
    demoAccountName: "audit-b@test.com",
    demoAccountPassword: ENV["DEMO_ACCOUNT_PASSWORD"].to_s,
    demoAccountRequired: true,
    # Mêmes notes longues (EN) que fix-meta — une seule source de vérité :
    # le reviewer est anglophone et le refus 2.1(b) venait en partie de notes
    # imprécises. Ne JAMAIS reposer une version courte qui écrase celle-ci.
    notes: <<~NOTES.strip,
      Kiwio is a French nutrition app. Demo account: audit-b@test.com

      IMPORTANT - the app has NO "Profil" tab. The profile opens as a sheet from
      the profile icon (person symbol) at the TOP-RIGHT of the Bilan tab.

      HOW TO FIND THE IN-APP PURCHASES (2.1(b)) - two paths:
      1. Bilan tab (first tab) > tap the "Kiwio Premium" card visible on the
         screen > the paywall opens.
      2. Bilan tab > profile icon (top-right) > "Passer a Premium".
      The paywall displays the auto-renewable subscriptions of group Kiwio
      Premium with their names, durations and prices: Annual (50 EUR) and
      Weekly (0.99 EUR). Both subscriptions (Weekly and Annual) are submitted
      with this version. The Monthly subscription is NOT part of this
      submission and is not displayed in the app.

      HEALTHKIT (2.5.1): Apple Health is read-only. Path: Bilan tab > profile
      icon (top-right) > "Modifier mon profil" > "Apple Sante" card (imports
      weight, steps and sleep). The Scanner tab also reads active energy (kcal).

      A screen recording captured on a physical iPhone is attached to this
      section: it begins on the Home Screen, launches the app, signs in with
      the demo account, walks through the core features, opens the paywall and
      completes a successful sandbox purchase.

      Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
      Privacy Policy: https://healthmap.fr/privacy
      (Both are also tappable at the bottom of the paywall in-app. The EULA
      link is also included in the App Description, per 3.1.2(c).)
    NOTES
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

# ── MODE attach-video : joint la vidéo sandbox aux infos App Review ─────────
# Apple exige à la resoumission un screen recording (Home Screen → login démo →
# paywall → achat sandbox réussi). VIDEO_PATH = fichier téléchargé par le
# workflow depuis une release GitHub privée. Même patron d'upload que les
# screenshots : réservation → PUT des chunks → commit MD5.
if MODE == "attach-video"
  video_path = ENV["VIDEO_PATH"].to_s
  abort_with("attach-video", 0, "VIDEO_PATH manquant ou introuvable : #{video_path}") unless File.exist?(video_path)

  version_id, vattrs = find_editable_version(app_id)
  abort_with("appStoreVersions", 0, "aucune version éditable (1.0) trouvée") unless version_id
  puts "Version : #{vattrs["versionString"]} état=#{vattrs["appStoreState"]} (#{version_id})"

  code, rd = req(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")
  abort_with("appStoreReviewDetail", code, rd) unless code == 200 && rd["data"]
  detail_id = rd["data"]["id"]

  # Pièces jointes existantes : on les remplace (une seule vidéo de référence).
  code, existing = req(:get, "/v1/appStoreReviewDetails/#{detail_id}/appStoreReviewAttachments?limit=50")
  if code == 200
    (existing["data"] || []).each do |att|
      write("suppression ancienne pièce jointe #{att.dig("attributes", "fileName")}",
        :delete, "/v1/appStoreReviewAttachments/#{att["id"]}", nil)
    end
  end

  bytes = File.binread(video_path)
  ok, resp = write("réservation pièce jointe (#{bytes.bytesize} o)", :post, "/v1/appStoreReviewAttachments",
    { data: { type: "appStoreReviewAttachments",
              attributes: { fileName: File.basename(video_path), fileSize: bytes.bytesize },
              relationships: { appStoreReviewDetail: { data: { type: "appStoreReviewDetails", id: detail_id } } } } })
  exit 1 unless ok

  att_id = resp["data"]["id"]
  (resp["data"]["attributes"]["uploadOperations"] || []).each_with_index do |op, i|
    uri = URI(op["url"])
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    put = Net::HTTP::Put.new(uri)
    (op["requestHeaders"] || []).each { |h| put[h["name"]] = h["value"] }
    put.body = bytes[op["offset"], op["length"]]
    res = http.request(put)
    unless (200..299).cover?(res.code.to_i)
      puts "  ÉCHEC upload chunk #{i + 1} -> HTTP #{res.code} #{res.body.to_s[0, 300]}"
      exit 1
    end
    puts "  chunk #{i + 1} : OK (#{op["length"]} o)"
  end

  ok, = write("commit pièce jointe", :patch, "/v1/appStoreReviewAttachments/#{att_id}",
    { data: { type: "appStoreReviewAttachments", id: att_id,
              attributes: { uploaded: true, sourceFileChecksum: Digest::MD5.hexdigest(bytes) } } })
  exit 1 unless ok

  code, check = req(:get, "/v1/appStoreReviewDetails/#{detail_id}/appStoreReviewAttachments?limit=50")
  puts "\n===== PIÈCES JOINTES APP REVIEW ====="
  puts JSON.pretty_generate(code == 200 ? check["data"].map { |a| a["attributes"] } : check)
  exit 0
end

# ── MODE trim-monthly : retire le Mensuel du brouillon de soumission ────────
# Le paywall (Annuel + shortPlan hebdo) n'affiche JAMAIS le Mensuel : un abo
# soumis mais introuvable dans l'app = refus 2.1(b). Le GET simple des items ne
# révèle pas leurs relations ; on sonde donc les liens de relation un par un
# (/relationships/<nom>) pour identifier l'item du Mensuel, puis on le DELETE.
if MODE == "trim-monthly"
  target_pid = ENV["TRIM_PRODUCT"].to_s.empty? ? "healthmap_monthly" : ENV["TRIM_PRODUCT"]

  # id ASC de l'abonnement visé
  target_sub_id = nil
  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      target_sub_id = s["id"] if s.dig("attributes", "productId") == target_pid
    end
  end
  abort_with("subscriptions", 0, "#{target_pid} introuvable") unless target_sub_id
  puts "Abonnement visé : #{target_pid} → #{target_sub_id}"

  staged = get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50")
    .select { |s| s.dig("attributes", "state") == "READY_FOR_REVIEW" }
    .map { |s| [s, get_all("/v1/reviewSubmissions/#{s["id"]}/items?limit=50")] }
    .find { |_, items| items.size.positive? }
  abort_with("reviewSubmissions", 0, "aucun brouillon avec items") unless staged
  submission, items = staged
  puts "Brouillon #{submission["id"]} : #{items.size} élément(s)"

  # L'id d'un reviewSubmissionItem est du base64 : "<submissionId>|<type>|<référence>".
  # Type observé 6 = version (réf numérique), 19 = groupe, 18 = abonnement — la
  # référence des abonnements est un UUID interne. On le corrèle aux UUID connus
  # de chaque abonnement (screenshot de review, availability, offres d'intro).
  require "base64"
  decoded = items.map do |item|
    raw = item["id"]
    raw_padded = raw + "=" * ((4 - raw.length % 4) % 4)
    plain = Base64.urlsafe_decode64(raw_padded) rescue (Base64.decode64(raw_padded) rescue "")
    parts = plain.split("|")
    puts "  · item #{item["id"][0, 24]}… → décodé : type=#{parts[1]} réf=#{parts[2]}"
    { item: item, type: parts[1], ref: parts[2] }
  end

  # UUID connus pour chaque abonnement du groupe
  sub_uuid_index = {}
  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      pid = s.dig("attributes", "productId")
      uuids = []
      code, shot = req(:get, "/v1/subscriptions/#{s["id"]}/appStoreReviewScreenshot")
      uuids << shot.dig("data", "id") if code == 200 && shot["data"]
      code, av = req(:get, "/v1/subscriptions/#{s["id"]}/subscriptionAvailability")
      uuids << av.dig("data", "id") if code == 200 && av["data"]
      code, intro = req(:get, "/v1/subscriptions/#{s["id"]}/introductoryOffers?limit=200")
      (intro["data"] || []).each { |o| uuids << o["id"] } if code == 200
      uuids.compact.each { |u| sub_uuid_index[u] = pid }
      puts "  · #{pid} : #{uuids.compact.size} UUID connus"
    end
  end

  target_item = nil
  decoded.each do |d|
    pid = sub_uuid_index[d[:ref]]
    next unless pid
    puts "  ✓ item #{d[:item]["id"][0, 24]}… identifié = #{pid}"
    target_item = d[:item] if pid == target_pid
  end

  # 2e chance : la réf type 18 est probablement l'id d'une subscriptionSubmission
  # (créée quand l'abo est « ajouté pour vérification »). On la GET pour lire sa
  # relation subscription.
  if target_item.nil?
    decoded.select { |d| d[:type] == "18" }.each do |d|
      %W[/v1/subscriptionSubmissions/#{d[:ref]}?include=subscription
         /v1/subscriptionSubmissions/#{d[:ref]}/relationships/subscription
         /v1/subscriptionSubmissions/#{d[:ref]}].each do |path|
        code, body = req(:get, path)
        puts "  · sonde #{path[0, 60]}… → HTTP #{code}"
        next unless code == 200 && body["data"]
        data = body["data"]
        sub_id = if data.is_a?(Hash) && data["type"] == "subscriptions"
                   data["id"]
                 else
                   data.is_a?(Hash) && data.dig("relationships", "subscription", "data", "id") ||
                     (body["included"] || []).find { |i| i["type"] == "subscriptions" }&.dig("id")
                 end
        if sub_id
          puts "    → subscription #{sub_id}"
          target_item = d[:item] if sub_id == target_sub_id
        end
        break
      end
      break if target_item
    end
  end

  unless target_item
    puts "\n⛔ Item du #{target_pid} NON identifié — rien supprimé. Retrait à faire dans l'UI ASC."
    puts "   (Corrélation UUID insuffisante ; items type 18 : #{decoded.select { |d| d[:type] == "18" }.map { |d| d[:ref] }.join(", ")})"
    exit 1
  end

  ok, = write("suppression de l'item #{target_pid} du brouillon", :delete,
    "/v1/reviewSubmissionItems/#{target_item["id"]}", nil)
  exit 1 unless ok

  rest = get_all("/v1/reviewSubmissions/#{submission["id"]}/items?limit=50")
  puts "\n===== BROUILLON APRÈS RETRAIT ====="
  puts "#{rest.size} élément(s) restant(s) (attendu : version + groupe + hebdo + annuel = 4)"
  exit rest.size == 4 ? 0 : 1
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
  version_id, = find_editable_version(app_id)
  abort_with("appStoreVersions", 0, "aucune version éditable (1.0) trouvée") unless version_id
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
  version_id, vattrs = find_editable_version(app_id)
  abort_with("appStoreVersions", 0, "aucune version éditable (1.0) trouvée") unless version_id
  puts "Version : #{vattrs["versionString"]} (#{version_id}) état=#{vattrs["appStoreState"]}"

  # Prix de l'app = GRATUIT (le schedule existe toujours mais peut être vide ;
  # requis même pour un freemium avec achats intégrés). On (re)pose le prix gratuit.
  free_id = nil
  url = "/v1/apps/#{app_id}/appPricePoints?filter[territory]=USA&limit=200&fields[appPricePoints]=customerPrice"
  while url
    code, body = req(:get, url)
    abort_with("appPricePoints", code, body) unless code == 200
    hit = body["data"].find { |p| p.dig("attributes", "customerPrice").to_f == 0.0 }
    (free_id = hit["id"]; break) if hit
    url = body.dig("links", "next")
  end
  if free_id
    write("prix de l'app = Gratuit", :post, "/v1/appPriceSchedules",
      { data: { type: "appPriceSchedules",
                relationships: {
                  app: { data: { type: "apps", id: app_id } },
                  baseTerritory: { data: { type: "territories", id: "USA" } },
                  manualPrices: { data: [{ type: "appPrices", id: "${p0}" }] } } },
        included: [{ type: "appPrices", id: "${p0}",
                    relationships: { appPricePoint: { data: { type: "appPricePoints", id: free_id } } } }] })
  else
    puts "  ÉCHEC point de prix gratuit introuvable"
  end

  # Note : conformité export déjà OK (build TestFlight) — pas dans les bloqueurs.
  # DAC7 « service personnel » : traité en amont si SUBMIT_DAC7 fourni (voir plus bas).

  # ── Abonnements D'ABORD (ordre critique) ─────────────────────────────────
  # Les abonnements doivent rejoindre le dossier AVANT tout contrôle de
  # complétude. Sinon le garde-fou « brouillon incomplet » sort en erreur sans
  # avoir jamais tenté de les soumettre : la version partait seule en review,
  # d'où le 2.1(b) « In-app purchase products could not be found » à répétition.
  # Après un refus, les abos sont en REJECTED et n'ont plus de version
  # modifiable : on la régénère en re-uploadant le screenshot de review.
  resubmittable_states = %w[READY_TO_SUBMIT REJECTED DEVELOPER_ACTION_NEEDED]
  # EXCLUDE_PRODUCTS (productIds séparés par des virgules) : abonnements à NE PAS
  # soumettre — un abo soumis mais introuvable dans l'app = refus 2.1(b) assuré.
  # Ex. healthmap_monthly : le paywall n'affiche que Annuel + Hebdo (shortPlan).
  excluded_products = ENV["EXCLUDE_PRODUCTS"].to_s.split(",").map(&:strip).reject(&:empty?)
  puts "Abonnements exclus de la soumission : #{excluded_products.join(", ")}" unless excluded_products.empty?
  presubmitted = []
  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      st = s.dig("attributes", "state")
      next unless resubmittable_states.include?(st)
      pid = s.dig("attributes", "productId")
      if excluded_products.include?(pid)
        puts "  · #{pid} : état=#{st} → EXCLU (EXCLUDE_PRODUCTS)"
        next
      end
      puts "  · #{pid} : état=#{st} → soumission de l'abonnement"
      payload = { data: { type: "subscriptionSubmissions",
                          relationships: { subscription: { data: { type: "subscriptions", id: s["id"] } } } } }
      okc, resp = write("soumission abonnement #{pid}", :post, "/v1/subscriptionSubmissions", payload)

      detail = resp.is_a?(Hash) ? resp.dig("errors", 0, "detail").to_s : ""
      err_code = resp.is_a?(Hash) ? resp.dig("errors", 0, "code").to_s : ""
      needs_pending = detail.include?("pending version") || err_code.include?("RELATIONSHIP.INVALID")
      if !okc && needs_pending &&
         ENV["REVIEW_SCREENSHOT_PATH"].to_s != "" && File.exist?(ENV["REVIEW_SCREENSHOT_PATH"])
        code_shot, shot = req(:get, "/v1/subscriptions/#{s["id"]}/appStoreReviewScreenshot")
        if code_shot == 200 && shot["data"]
          write("suppression ancien screenshot (#{pid})", :delete,
            "/v1/subscriptionAppStoreReviewScreenshots/#{shot["data"]["id"]}", nil)
        end
        if upload_review_screenshot(s["id"], ENV["REVIEW_SCREENSHOT_PATH"])
          sleep 3
          okc, = write("soumission abonnement #{pid} (2e tentative)", :post,
            "/v1/subscriptionSubmissions", payload)
        end
      end
      presubmitted << pid if okc
    end
  end
  unless presubmitted.empty?
    puts "\nAbonnements repassés en soumission : #{presubmitted.join(", ")}"
    sleep 5
  end

  active_states = %w[WAITING_FOR_REVIEW IN_REVIEW]
  subs_list = get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50")

  # 0) PRIORITÉ : une soumission déjà PRÉPARÉE avec des items (montée via l'UI
  #    web — seule voie possible pour le 1er abonnement) doit être ENVOYÉE telle
  #    quelle, jamais détruite. On la soumet et on s'arrête là.
  staged_with_items = subs_list.filter_map do |s|
    next unless s.dig("attributes", "state") == "READY_FOR_REVIEW"
    items = get_all("/v1/reviewSubmissions/#{s["id"]}/items?limit=50")
    [s, items] if items.size.positive?
  end
  if staged_with_items.any?
    # Le nouveau workflow App Store Connect place le groupe et ses abonnements
    # dans le brouillon, mais leur API conserve encore l'état READY_TO_SUBMIT et
    # ne révèle pas leur relation dans reviewSubmissionItems. Pour une première
    # soumission : version + groupe + N abonnements = N + 2 éléments attendus.
    staged, staged_items = staged_with_items.max_by { |_, items| items.size }
    pending_subs = get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").flat_map do |g|
      get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50")
        .select { |s| s.dig("attributes", "state") == "READY_TO_SUBMIT" }
        .map { |s| s.dig("attributes", "productId") }
        .reject { |pid| excluded_products.include?(pid) }
    end
    expected_items = pending_subs.size + 2
    if staged_items.size < expected_items
      puts "\n⛔ ENVOI BLOQUÉ — brouillon incomplet :"
      puts "   #{staged_items.size} élément(s) présent(s), #{expected_items} attendu(s)"
      puts "   (version + groupe + #{pending_subs.size} abonnement(s))."
      pending_subs.each { |p| puts "     - #{p}" }
      puts "   Soumission #{staged["id"]} laissée préparée, non envoyée."
      exit 1
    end
    puts "Soumission préparée complète (#{staged["id"]}) :"
    puts "  #{staged_items.size} élément(s) pour #{pending_subs.size} abonnement(s)."
    # STAGE_ONLY doit être respecté ICI AUSSI : ce chemin envoyait à Apple même
    # en mode préparation (seul le chemin « nouvelle soumission » le vérifiait).
    if ENV["STAGE_ONLY"] == "1"
      puts "STAGE_ONLY=1 — soumission COMPLÈTE mais NON envoyée (#{staged["id"]})."
      puts "Pour l'envoyer : relancer submit sans STAGE_ONLY."
      exit 0
    end
    ok, = write("ENVOI de la soumission préparée", :patch, "/v1/reviewSubmissions/#{staged["id"]}",
      { data: { type: "reviewSubmissions", id: staged["id"], attributes: { submitted: true } } })
    exit 1 unless ok
    code, s = req(:get, "/v1/reviewSubmissions/#{staged["id"]}")
    puts "\n===== ÉTAT SOUMISSION ====="
    puts JSON.pretty_generate(code == 200 ? s["data"]["attributes"] : s)
    exit 0
  end

  # 1) La VERSION est-elle déjà en review active ? (idempotence : ne pas la
  #    re-soumettre, sinon 409 ITEM_PART_OF_ANOTHER_SUBMISSION).
  version_live = subs_list.any? { |s| active_states.include?(s.dig("attributes", "state")) }

  if version_live
    puts "Version déjà en review (soumission active) — on saute la re-soumission de la version."
  else
    # Nettoyer les soumissions bloquantes : après un refus la version reste piégée
    # dans une soumission UNRESOLVED_ISSUES (409 ITEM_PART_OF_ANOTHER_SUBMISSION),
    # et un run précédent a pu laisser une soumission vide READY_FOR_REVIEW.
    cancel_states = %w[READY_FOR_REVIEW UNRESOLVED_ISSUES]
    to_cancel = subs_list.select { |s| cancel_states.include?(s.dig("attributes", "state")) }
    to_cancel.each do |s|
      st = s.dig("attributes", "state")
      # L'API REFUSE le DELETE sur reviewSubmissions (403 FORBIDDEN_ERROR :
      # « Allowed operations are: CREATE, GET_COLLECTION, GET_INSTANCE,
      # UPDATE »). Une soumission préparée s'annule donc par PATCH, quel que
      # soit son état — sinon la version restait piégée en READY_FOR_REVIEW,
      # donc non éditable, et le build ne pouvait plus être remplacé.
      write("annulation soumission #{s["id"]} (#{st})", :patch,
        "/v1/reviewSubmissions/#{s["id"]}",
        { data: { type: "reviewSubmissions", id: s["id"], attributes: { canceled: true } } })
    end
    unless to_cancel.empty?
      10.times do
        sleep 3
        still = get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50")
               .select { |s| (cancel_states + %w[CANCELING]).include?(s.dig("attributes", "state")) }
        break if still.empty?
        puts "  … annulation en cours (#{still.size} soumission(s) encore ouverte(s))"
      end
    end

    ok, resp = write("création de la soumission (version)", :post, "/v1/reviewSubmissions",
      { data: { type: "reviewSubmissions",
                attributes: { platform: "IOS" },
                relationships: { app: { data: { type: "apps", id: app_id } } } } })
    rev_id = resp["data"]["id"] if ok
    abort_with("reviewSubmissions", 0, "impossible de créer une soumission") unless rev_id

    write("ajout de la version à la soumission", :post, "/v1/reviewSubmissionItems",
      { data: { type: "reviewSubmissionItems",
                relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: rev_id } },
                                 appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })

    # Les ABONNEMENTS dans la MÊME soumission que la version — c'est ce
    # qu'exige un refus 2.1(b) (« IAP could not be found in the binary »).
    # `subscriptionSubmissions` échoue en 409 sur un abo rejeté (« no pending
    # version »), mais un abo revenu à READY_TO_SUBMIT peut s'attacher
    # directement comme item de la soumission.
    get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
      get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
        next unless s.dig("attributes", "state") == "READY_TO_SUBMIT"
        write("ajout de l'abonnement #{s.dig("attributes", "productId")} à la soumission",
          :post, "/v1/reviewSubmissionItems",
          { data: { type: "reviewSubmissionItems",
                    relationships: { reviewSubmission: { data: { type: "reviewSubmissions", id: rev_id } },
                                     subscription: { data: { type: "subscriptions", id: s["id"] } } } } })
      end
    end

    # STAGE_ONLY : on prépare la soumission (version + abos) SANS l'envoyer.
    # Utile tant qu'un prérequis hors-API manque (accord Paid Apps, vidéo
    # sandbox exigée par App Review) : envoyer trop tôt = refus assuré.
    if ENV["STAGE_ONLY"] == "1"
      puts "\nSTAGE_ONLY=1 — soumission PRÉPARÉE mais NON envoyée (#{rev_id})."
      puts "Contenu :"
      get_all("/v1/reviewSubmissions/#{rev_id}/items?limit=50").each do |it|
        rel = (it["relationships"] || {}).find { |_, v| v.is_a?(Hash) && v["data"] }
        puts "  - #{rel ? "#{rel[0]}:#{rel[1]["data"]["id"]}" : it.dig("attributes", "state")}"
      end
      puts "Pour l'envoyer : relancer submit sans STAGE_ONLY (elle sera envoyée telle quelle)."
      exit 0
    end

    write("SOUMISSION version à Apple (submitted=true)", :patch, "/v1/reviewSubmissions/#{rev_id}",
      { data: { type: "reviewSubmissions", id: rev_id, attributes: { submitted: true } } })
  end

  # 2) Soumettre les ABONNEMENTS via l'endpoint DÉDIÉ subscriptionSubmissions
  #    (fix refus 2.1(b) : le 1er abonnement DOIT partir avec la nouvelle version.
  #    'subscription' n'est PAS une relation de reviewSubmissionItems — l'API le
  #    refuse ENTITY_ERROR.RELATIONSHIP.UNKNOWN ; c'est subscriptionSubmissions).
  # ⚠️ Ne PAS filtrer sur le seul READY_TO_SUBMIT : après un refus App Review les
  # abonnements retombent en REJECTED, et les sauter ici empêchait la reprise
  # ci-dessous (régénération d'une pending version) de tourner — l'app repartait
  # donc en review SANS ses abonnements, d'où le 2.1(b) « could not be found »
  # à répétition. On traite aussi REJECTED / DEVELOPER_ACTION_NEEDED.
  submitted_subs = []
  resubmittable = %w[READY_TO_SUBMIT REJECTED DEVELOPER_ACTION_NEEDED]
  get_all("/v1/apps/#{app_id}/subscriptionGroups?limit=200").each do |g|
    get_all("/v1/subscriptionGroups/#{g["id"]}/subscriptions?limit=50").each do |s|
      state = s.dig("attributes", "state")
      next unless resubmittable.include?(state)
      pid = s.dig("attributes", "productId")
      puts "  · #{pid} : état=#{state} → tentative de soumission"
      sub_payload = { data: { type: "subscriptionSubmissions",
                  relationships: { subscription: { data: { type: "subscriptions", id: s["id"] } } } } }
      okc, resp = write("soumission abonnement #{pid}", :post, "/v1/subscriptionSubmissions", sub_payload)

      # Après un refus App Review, l'abonnement n'a plus de « pending version »
      # (409 ENTITY_ERROR.RELATIONSHIP.INVALID). Un PATCH de localisation à
      # l'identique est un no-op pour ASC (testé : le 409 persiste) — il faut
      # une modification RÉELLE pour régénérer un brouillon soumissible.
      # La moins invasive : supprimer puis re-uploader le screenshot de review
      # (même PNG → aucun changement visible, mais nouvelle version pending).
      # Le libellé exact varie selon l'état de départ (REJECTED vs READY_TO_SUBMIT) :
      # on tente la reprise dès qu'un échec évoque l'absence de version modifiable,
      # au lieu de matcher la seule phrase « no pending version ».
      detail = resp.is_a?(Hash) ? resp.dig("errors", 0, "detail").to_s : ""
      needs_pending = detail.include?("no pending version") ||
                      detail.include?("pending version") ||
                      detail.include?("RELATIONSHIP.INVALID") ||
                      (resp.is_a?(Hash) && resp.dig("errors", 0, "code").to_s.include?("RELATIONSHIP.INVALID"))
      if !okc && needs_pending &&
         ENV["REVIEW_SCREENSHOT_PATH"].to_s != "" && File.exist?(ENV["REVIEW_SCREENSHOT_PATH"])
        code_shot, shot = req(:get, "/v1/subscriptions/#{s["id"]}/appStoreReviewScreenshot")
        if code_shot == 200 && shot["data"]
          write("suppression ancien screenshot (#{pid})", :delete,
            "/v1/subscriptionAppStoreReviewScreenshots/#{shot["data"]["id"]}", nil)
        end
        if upload_review_screenshot(s["id"], ENV["REVIEW_SCREENSHOT_PATH"])
          sleep 3
          okc, = write("soumission abonnement #{pid} (2e tentative)", :post,
            "/v1/subscriptionSubmissions", sub_payload)
        end
      end

      submitted_subs << pid if okc
    end
  end
  puts "\nAbonnements soumis : #{submitted_subs.empty? ? "(aucun READY_TO_SUBMIT — déjà soumis ?)" : submitted_subs.join(", ")}"

  # 3) État final de toutes les soumissions
  puts "\n===== ÉTAT SOUMISSIONS ====="
  get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50").each do |s|
    a = s["attributes"]
    puts "  reviewSubmission #{s["id"]} → #{a["state"]} (soumis: #{a["submittedDate"] || "—"})"
  end
  exit 0
end

# ── MODE fix-meta : annule la soumission en cours + corrige les métadonnées ──
#    (refus 3.1.2(c) : lien CGU/EULA absent des métadonnées ; 2.5.1 : notes review
#     localisant HealthKit) et REND la version éditable pour que la soumission
#     version + 3 abonnements se fasse dans l'UI web (l'API interdit de soumettre
#     le 1er abonnement — FIRST_SUBSCRIPTION_MUST_BE_SUBMITTED_ON_VERSION).
if MODE == "fix-meta"
  terms_url = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
  privacy_url = "https://healthmap.fr/privacy"

  # 1) Rendre la version éditable : annuler toute soumission en cours.
  cancel_states = %w[READY_FOR_REVIEW WAITING_FOR_REVIEW UNRESOLVED_ISSUES]
  to_cancel = get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50")
             .select { |s| cancel_states.include?(s.dig("attributes", "state")) }
  to_cancel.each do |s|
    st = s.dig("attributes", "state")
    # Une soumission PRÉPARÉE (READY_FOR_REVIEW, jamais envoyée) n'est ni
    # supprimable (403 : DELETE interdit sur reviewSubmissions) ni annulable
    # (409 « Resource is not in cancellable state »). Le seul moyen de libérer
    # la version est de RETIRER ses éléments : le brouillon redevient vide et
    # la version repasse éditable (on peut alors changer le build attaché).
    if st == "READY_FOR_REVIEW"
      items = get_all("/v1/reviewSubmissions/#{s["id"]}/items?limit=50")
      if items.empty?
        puts "  (soumission #{s["id"]} déjà vide)"
      else
        items.each do |it|
          write("retrait d'un élément du brouillon #{s["id"]}", :delete,
            "/v1/reviewSubmissionItems/#{it["id"]}", nil)
        end
      end
    else
      write("annulation soumission #{s["id"]} (#{st})", :patch,
        "/v1/reviewSubmissions/#{s["id"]}",
        { data: { type: "reviewSubmissions", id: s["id"], attributes: { canceled: true } } })
    end
  end
  unless to_cancel.empty?
    10.times do
      sleep 3
      still = get_all("/v1/apps/#{app_id}/reviewSubmissions?limit=50")
             .select { |s| (cancel_states + %w[CANCELING]).include?(s.dig("attributes", "state")) }
      break if still.empty?
      puts "  … annulation en cours (#{still.size})"
    end
  end

  version_id, vattrs = find_editable_version(app_id)
  abort_with("appStoreVersions", 0, "aucune version éditable") unless version_id
  puts "Version éditable : #{vattrs["versionString"]} état=#{vattrs["appStoreState"]}"

  # 2) Description : ajouter les liens CGU/EULA + confidentialité (idempotent,
  #    garde-fou 4000 caractères max imposé par Apple).
  footer = "\n\nConditions d'utilisation (CGU) : #{terms_url}\nConfidentialite : #{privacy_url}"
  # ⚠️ `healthmap.fr/terms` n'a JAMAIS existé (aucune route côté web) : la page
  # renvoyait un 404 rendu en JavaScript, donc HTTP 200 mais « Page introuvable »
  # à l'écran. C'est ce lien mort, présent dans la description ET dans le
  # paywall, qui a valu trois refus 3.1.2(c) — le reviewer cliquait et tombait
  # sur la 404. On le REMPLACE partout par l'EULA standard d'Apple.
  dead_terms = "https://healthmap.fr/terms"
  get_all("/v1/appStoreVersions/#{version_id}/appStoreVersionLocalizations?limit=20").each do |l|
    loc = l.dig("attributes", "locale")
    desc = l.dig("attributes", "description").to_s

    if desc.include?(dead_terms)
      fixed = desc.gsub(dead_terms, terms_url)
      write("remplacement du lien CGU mort dans description #{loc}", :patch,
        "/v1/appStoreVersionLocalizations/#{l["id"]}",
        { data: { type: "appStoreVersionLocalizations", id: l["id"],
                  attributes: { description: fixed } } })
      next
    end

    if desc.include?(terms_url)
      puts "  (description #{loc} : lien EULA valide déjà présent)"
      next
    end
    if (desc + footer).length > 4000
      puts "  ATTENTION description #{loc} trop longue pour ajouter les liens (#{desc.length} car.) — à faire en UI"
      next
    end
    write("liens CGU+confidentialité dans description #{loc}", :patch,
      "/v1/appStoreVersionLocalizations/#{l["id"]}",
      { data: { type: "appStoreVersionLocalizations", id: l["id"],
                attributes: { description: desc + footer } } })
  end

  # 3) URL de politique de confidentialité au niveau appInfo (best-effort).
  get_all("/v1/apps/#{app_id}/appInfos?limit=5").each do |ai|
    get_all("/v1/appInfos/#{ai["id"]}/appInfoLocalizations?limit=20").each do |ail|
      next if ail.dig("attributes", "privacyPolicyUrl").to_s == privacy_url
      write("privacyPolicyUrl #{ail.dig("attributes", "locale")}", :patch,
        "/v1/appInfoLocalizations/#{ail["id"]}",
        { data: { type: "appInfoLocalizations", id: ail["id"],
                  attributes: { privacyPolicyUrl: privacy_url } } })
    end
  end

  # 4) Notes de review : localiser HealthKit (2.5.1) + détailler les abonnements (2.1b/3.1.2c).
  notes = <<~NOTES.strip
    Kiwio is a French nutrition app. Demo account: audit-b@test.com

    IMPORTANT - the app has NO "Profil" tab. The profile opens as a sheet from
    the profile icon (person symbol) at the TOP-RIGHT of the Bilan tab.

    HOW TO FIND THE IN-APP PURCHASES (2.1(b)) - two paths:
    1. Bilan tab (first tab) > tap the "Kiwio Premium" card visible on the
       screen > the paywall opens.
    2. Bilan tab > profile icon (top-right) > "Passer a Premium".
    The paywall lists the auto-renewable subscriptions of group Kiwio Premium:
    Annual (50 EUR) and Weekly (0.99 EUR) - names, durations and prices are
    displayed. Both are submitted with this version. The Monthly subscription
    is NOT part of this submission and is not displayed in the app.

    HEALTHKIT (2.5.1): Apple Health is read-only. Path: Bilan tab > profile
    icon (top-right) > "Modifier mon profil" > "Apple Sante" card (imports
    weight, steps and sleep). The Scanner tab also reads active energy (kcal).

    A screen recording captured on a physical iPhone is attached to this
    section: it begins on the Home Screen, launches the app, signs in with
    the demo account, walks through the core features, opens the paywall and
    completes a successful sandbox purchase.

    Terms of Use (EULA): #{terms_url}
    Privacy Policy: #{privacy_url}
    (Both are also tappable at the bottom of the paywall in-app. The EULA
    link is also included in the App Description, per 3.1.2(c).)
  NOTES
  code, rd = req(:get, "/v1/appStoreVersions/#{version_id}/appStoreReviewDetail")
  if code == 200 && rd["data"]
    write("notes de review", :patch, "/v1/appStoreReviewDetails/#{rd["data"]["id"]}",
      { data: { type: "appStoreReviewDetails", id: rd["data"]["id"], attributes: { notes: notes } } })
  else
    write("notes de review (création)", :post, "/v1/appStoreReviewDetails",
      { data: { type: "appStoreReviewDetails", attributes: { notes: notes },
                relationships: { appStoreVersion: { data: { type: "appStoreVersions", id: version_id } } } } })
  end

  puts "\n===== MÉTADONNÉES CORRIGÉES ====="
  puts "Version #{vattrs["versionString"]} rendue éditable ; liens CGU+confidentialité + notes review posés."
  puts "PROCHAINE ÉTAPE (UI web) : soumettre la version 1.0 + les 3 abonnements ENSEMBLE."
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
  next unless ONLY_PRODUCT.empty? || ONLY_PRODUCT == product_id
  puts "\n--- #{product_id} ---"
  entry = all_subs[product_id]

  if entry.nil?
    ok, resp = write("création de l'abonnement", :post, "/v1/subscriptions",
      { data: { type: "subscriptions",
                attributes: { name: spec[:name], productId: product_id,
                              subscriptionPeriod: spec[:period], familySharable: false, groupLevel: spec[:level] || 1 },
                relationships: { group: { data: { type: "subscriptionGroups", id: group_id } } } } })
    (failures << "#{product_id}: création" ; next) unless ok
    entry = { id: resp["data"]["id"] }
  end
  sub_id = entry[:id]
  snap = sub_snapshot(sub_id)

  # Localisation fr-FR
  french_localizations = get_all("/v1/subscriptions/#{sub_id}/subscriptionLocalizations?limit=50")
                         .select { |l| l.dig("attributes", "locale").to_s.start_with?("fr") }
  if french_localizations.empty?
    ok, = write("localisation fr-FR", :post, "/v1/subscriptionLocalizations",
      { data: { type: "subscriptionLocalizations",
                attributes: { locale: "fr-FR", name: spec[:name], description: SUBSCRIPTION_DESCRIPTION },
                relationships: { subscription: { data: { type: "subscriptions", id: sub_id } } } } })
    failures << "#{product_id}: localisation" unless ok
  else
    french_localizations.each do |loc|
      next if loc.dig("attributes", "description").to_s == SUBSCRIPTION_DESCRIPTION
      # Apple verrouille DESCRIPTION dès que l'abonnement atteint READY_TO_SUBMIT.
      # La capture de revue et la note App Review portent alors le wording exact.
      puts "  INFO description fr-FR existante verrouillée par Apple"
    end
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

  # Disponibilité : tous les territoires. Un sub fraîchement créé a une coquille
  # de dispo VIDE (territoriesCount=0) → il faut y ajouter les territoires, sinon
  # MISSING_METADATA. On crée si absente, sinon on complète les territoires.
  avail = snap[:availability]
  if !avail.is_a?(Hash)
    territories = get_all("/v1/territories?limit=200").map { |t| t["id"] }
    ok, = write("disponibilité (#{territories.size} territoires)", :post, "/v1/subscriptionAvailabilities",
      { data: { type: "subscriptionAvailabilities",
                attributes: { availableInNewTerritories: true },
                relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                 availableTerritories: { data: territories.map { |t| { type: "territories", id: t } } } } } })
    failures << "#{product_id}: disponibilité" unless ok
  elsif avail[:territoriesCount].to_i < 100
    territories = get_all("/v1/territories?limit=200").map { |t| t["id"] }
    ok, = write("disponibilité : ajout de #{territories.size} territoires", :post,
      "/v1/subscriptionAvailabilities/#{avail[:id]}/relationships/availableTerritories",
      { data: territories.map { |t| { type: "territories", id: t } } })
    failures << "#{product_id}: disponibilité (ajout)" unless ok
  else
    puts "  OK  disponibilité déjà sur #{avail[:territoriesCount]} territoires"
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

  # Screenshot review : requis pour sortir de MISSING_METADATA. Une capture
  # COMPLETE peut néanmoins être obsolète : comparer son checksum au PNG rendu.
  shot = snap[:reviewScreenshot]
  png = ENV["REVIEW_SCREENSHOT_PATH"]
  desired_checksum =
    png && File.exist?(png) ? Digest::MD5.file(png).hexdigest : nil
  needs_upload =
    if shot.is_a?(String)
      true # absent
    elsif shot.dig("assetDeliveryState", "state") == "COMPLETE" &&
          desired_checksum &&
          shot["sourceFileChecksum"].to_s != desired_checksum
      code, response = req(:delete,
        "/v1/subscriptionAppStoreReviewScreenshots/#{shot[:id]}")
      locked = code == 409 &&
        Array(response.is_a?(Hash) ? response["errors"] : nil).any? do |error|
          error["code"] == "ENTITY_ERROR.MEDIA_ASSET_DELETE_NOT_ALLOWED"
        end
      if (200..299).cover?(code)
        puts "  OK  suppression screenshot review obsolète (HTTP #{code})"
        true
      elsif locked
        # Après un premier rattachement à une soumission, Apple conserve l'asset
        # COMPLETE mais interdit son remplacement. Il reste valide pour la revue.
        puts "  INFO screenshot review COMPLETE verrouillé par Apple"
        false
      else
        puts "  ÉCHEC suppression screenshot review obsolète -> HTTP #{code}"
        puts(response.is_a?(String) ? response : JSON.pretty_generate(response))
        failures << "#{product_id}: suppression screenshot obsolète"
        false
      end
    elsif shot.dig("assetDeliveryState", "state") == "COMPLETE"
      false
    else
      # réservation jamais finalisée (AWAITING_UPLOAD / FAILED) : suppression puis ré-upload
      ok, = write("suppression screenshot non finalisé", :delete,
        "/v1/subscriptionAppStoreReviewScreenshots/#{shot[:id]}", nil)
      failures << "#{product_id}: suppression screenshot non finalisé" unless ok
      ok
    end
  if needs_upload
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
  exit 1
end

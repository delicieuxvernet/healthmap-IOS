#!/usr/bin/env ruby
# Pilote les abonnements App Store via l'API officielle App Store Connect.
# L'éditeur de prix de l'UI App Store Connect (shadow DOM) n'est pas automatisable ;
# l'API, elle, expose prix/localisations/disponibilité ET renvoie l'erreur exacte
# si un accord (ex. vérification DSA) bloque l'écriture.
#
#   MODE=audit : lit et rapporte l'état complet des abonnements (aucune écriture)
#   MODE=apply : fixe les prix validés (2,99 € mensuel / 24,99 € annuel, base FRA,
#                autres territoires égalisés par Apple), crée localisation fr-FR et
#                disponibilité manquantes, essai gratuit 7 j — puis relit l'état.

require "jwt"
require "json"
require "net/http"
require "openssl"

BUNDLE_ID = "fr.healthmap.app"
TARGETS = {
  "healthmap_monthly" => { price: "2.99",  name: "Kiwio Mensuel", period: "ONE_MONTH" },
  "healthmap_annual"  => { price: "24.99", name: "Kiwio Annuel",  period: "ONE_YEAR"  },
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

  # assetDeliveryState est le point clé : un screenshot réservé mais jamais
  # committé (AWAITING_UPLOAD) compte comme métadonnée manquante.
  code, shot = req(:get, "/v1/subscriptions/#{sub_id}/appStoreReviewScreenshot")
  snap[:reviewScreenshot] = code == 200 ? shot["data"]["attributes"] : "absent (HTTP #{code})"
  snap[:rawAttributes] = a
  snap
end

def find_price_point(sub_id, price)
  url = "/v1/subscriptions/#{sub_id}/pricePoints?filter[territory]=FRA&limit=200&fields[subscriptionPricePoints]=customerPrice"
  while url
    code, body = req(:get, url)
    abort_with("pricePoints", code, body) unless code == 200
    hit = body["data"].find { |p| p.dig("attributes", "customerPrice") == price }
    return hit["id"] if hit
    url = body.dig("links", "next")
  end
  nil
end

# ── 1. App + groupes ─────────────────────────────────────────────────────────
code, body = req(:get, "/v1/apps?filter[bundleId]=#{BUNDLE_ID}")
abort_with("apps", code, body) unless code == 200 && body["data"]&.any?
app_id = body["data"][0]["id"]
puts "App #{BUNDLE_ID} -> #{app_id} | MODE=#{MODE}"

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
  pp_id = find_price_point(sub_id, spec[:price])
  if pp_id.nil?
    puts "  ÉCHEC aucun price point FRA à #{spec[:price]}"
    failures << "#{product_id}: price point introuvable"
  else
    current = snap[:prices_fra].is_a?(Array) ? snap[:prices_fra].map { |p| p[:customerPrice] } : []
    if current.include?(spec[:price])
      puts "  OK  prix FRA déjà à #{spec[:price]} €"
    else
      ok, = write("prix FRA #{spec[:price]} €", :post, "/v1/subscriptionPrices",
        { data: { type: "subscriptionPrices",
                  relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                   subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: pp_id } } } } })
      failures << "#{product_id}: prix base" unless ok
    end

    if snap[:pricesAllTerritoriesCount] < 100
      eqs = get_all("/v1/subscriptionPricePoints/#{pp_id}/equalizations?limit=200&fields[subscriptionPricePoints]=customerPrice")
      ok_n = ko_n = 0
      first_error = nil
      eqs.each do |eq|
        code, resp = req(:post, "/v1/subscriptionPrices",
          { data: { type: "subscriptionPrices",
                    relationships: { subscription: { data: { type: "subscriptions", id: sub_id } },
                                     subscriptionPricePoint: { data: { type: "subscriptionPricePoints", id: eq["id"] } } } } })
        if (200..299).cover?(code)
          ok_n += 1
        else
          ko_n += 1
          first_error ||= [code, resp]
        end
      end
      puts "  égalisation : #{ok_n} territoires OK, #{ko_n} en échec (sur #{eqs.size})"
      if first_error
        puts "  première erreur d'égalisation -> HTTP #{first_error[0]}"
        puts JSON.pretty_generate(first_error[1]) rescue puts(first_error[1].inspect)
      end
      failures << "#{product_id}: égalisation (#{ko_n} échecs)" if ko_n > 0 && ok_n == 0
    else
      puts "  OK  grille de prix déjà complète (#{snap[:pricesAllTerritoriesCount]} territoires)"
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

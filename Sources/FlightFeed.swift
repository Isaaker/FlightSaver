import Foundation

/// Consulta fuentes ADS-B compatibles (formato ADSBExchange v2) con respaldo automático y backoff.
/// Compartido por todas las vistas del proceso (varios monitores / vista previa) para no multiplicar peticiones.
final class FlightFeed {
    static let shared = FlightFeed()

    struct Provider {
        let name: String
        let build: (Double, Double, Int) -> String
        let key: String?
        let minInterval: TimeInterval
    }

    private(set) var aircraft: [String: Aircraft] = [:]
    private(set) var statusText = "Conectando…"
    private(set) var statusIsError = false
    private(set) var lastOK: Date?
    private(set) var providerName = ""

    private var users = 0
    private var settings = Settings()
    private var radiusNm = 60
    private var timer: Timer?
    private var blockedUntil: [String: Date] = [:]
    private var lastRequest = Date.distantPast
    private var inFlight = false

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 10
        c.httpAdditionalHeaders = ["User-Agent": NetworkIdentity.userAgent]
        return URLSession(configuration: c)
    }()

    var radius: Int { radiusNm }

    func start(settings: Settings, radiusNm: Int) {
        users += 1
        self.settings = settings
        self.radiusNm = max(self.radiusNm, min(250, max(10, radiusNm)))
        if timer == nil {
            let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.tick() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
        tick()
    }

    func stop() {
        users = max(0, users - 1)
        if users == 0 {
            timer?.invalidate()
            timer = nil
            radiusNm = 60
        }
    }

    // MARK: Proveedores

    private func providers() -> [Provider] {
        let key = settings.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let lol = Provider(
            name: "adsb.lol",
            build: { "https://api.adsb.lol/v2/point/\($0)/\($1)/\($2)" },
            key: key.isEmpty ? nil : key,
            minInterval: key.isEmpty ? 180 : 2        // sin clave: ~500 peticiones/día por IP
        )
        let fi = Provider(
            name: "adsb.fi",
            build: { "https://opendata.adsb.fi/api/v3/lat/\($0)/lon/\($1)/dist/\($2)" },
            key: nil,
            minInterval: 2                            // límite público: 1 petición/s
        )
        return key.isEmpty ? [fi, lol] : [lol, fi]
    }

    private func tick() {
        guard !inFlight else { return }
        let now = Date()
        let available = providers().filter { (blockedUntil[$0.name] ?? .distantPast) <= now }
        guard let p = available.first else {
            statusText = "Todas las fuentes están en pausa; reintentando en breve"
            statusIsError = true
            return
        }
        guard now.timeIntervalSince(lastRequest) >= max(settings.refresh, p.minInterval) else { return }
        lastRequest = now
        fetch(p)
    }

    private func fetch(_ p: Provider) {
        guard let url = URL(string: p.build(settings.lat, settings.lon, radiusNm)) else { return }
        var req = URLRequest(url: url)
        if let k = p.key { req.setValue(k, forHTTPHeaderField: "X-API-Key") }
        inFlight = true
        session.dataTask(with: req) { [weak self] data, response, error in
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            var json: Any?
            if code == 200, let data = data { json = try? JSONSerialization.jsonObject(with: data) }
            let errText = error?.localizedDescription
            DispatchQueue.main.async {
                self?.handle(p, code: code, retryAfter: retryAfter, json: json, error: errText)
            }
        }.resume()
    }

    private func block(_ p: Provider, seconds: TimeInterval) {
        blockedUntil[p.name] = Date().addingTimeInterval(seconds)
        lastRequest = .distantPast      // la siguiente fuente puede probar ya
    }

    private func fail(_ message: String) {
        statusText = message
        statusIsError = true
    }

    private func handle(_ p: Provider, code: Int, retryAfter: Double?, json: Any?, error: String?) {
        inFlight = false
        if let error = error {
            block(p, seconds: 20)
            fail("\(p.name): sin conexión (\(error))")
            return
        }
        switch code {
        case 200:
            if let json = json, ingest(json, receivedAt: Date()) {
                lastOK = Date()
                providerName = p.name
                statusText = ""
                statusIsError = false
            } else {
                block(p, seconds: 30)
                fail("\(p.name): respuesta con formato inesperado")
            }
        case 429:
            block(p, seconds: max(retryAfter ?? 60, 30))
            fail("\(p.name): límite de peticiones (429)")
        case 401:
            block(p, seconds: 3600)
            fail("\(p.name): clave de API inválida (401)")
        case 403:
            block(p, seconds: 3600)
            fail("\(p.name): acceso denegado (403)")
        default:
            block(p, seconds: 30)
            fail("\(p.name): error HTTP \(code)")
        }
    }

    // MARK: Datos

    private func num(_ any: Any?) -> Double? { (any as? NSNumber)?.doubleValue }

    private func ingest(_ json: Any, receivedAt now: Date) -> Bool {
        guard let root = json as? [String: Any] else { return false }
        guard let list = (root["ac"] as? [[String: Any]]) ?? (root["aircraft"] as? [[String: Any]]) else { return false }

        for d in list {
            guard let hex = d["hex"] as? String, let lat = num(d["lat"]), let lon = num(d["lon"]) else { continue }

            let seenPos = num(d["seen_pos"]) ?? num(d["seen"]) ?? 0
            let posTime = now.addingTimeInterval(-min(max(seenPos, 0), 30))

            var a: Aircraft
            var oldDisplayed: (lat: Double, lon: Double)?
            if let old = aircraft[hex] {
                a = old
                oldDisplayed = old.displayed(at: now)
                if old.lat != lat || old.lon != lon {
                    a.trail.append(TrailPoint(lat: old.lat, lon: old.lon))
                    if a.trail.count > 60 { a.trail.removeFirst(a.trail.count - 60) }
                }
            } else {
                a = Aircraft(hex: hex, callsign: hex.uppercased(), lat: lat, lon: lon,
                             posTime: posTime, lastSeen: now, firstSeen: now)
            }

            a.lat = lat
            a.lon = lon
            a.posTime = posTime
            a.lastSeen = now

            a.reg = (d["r"] as? String) ?? a.reg
            a.type = (d["t"] as? String) ?? a.type
            a.category = (d["category"] as? String) ?? a.category
            a.squawk = (d["squawk"] as? String) ?? ""
            let flight = ((d["flight"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            a.callsign = flight.isEmpty ? (a.reg.isEmpty ? hex.uppercased() : a.reg) : flight

            a.track = num(d["track"]) ?? num(d["true_heading"]) ?? num(d["mag_heading"]) ?? a.track
            a.gs = num(d["gs"]) ?? 0
            if let s = d["alt_baro"] as? String {
                a.onGround = (s == "ground")
                a.alt = nil
            } else {
                a.onGround = false
                a.alt = num(d["alt_baro"])
            }
            a.vRate = num(d["baro_rate"]) ?? num(d["geom_rate"])
            a.military = (Int(num(d["dbFlags"]) ?? 0) & 1) != 0
            let emergencyField = (d["emergency"] as? String) ?? "none"
            a.emergency = (emergencyField != "none" && !emergencyField.isEmpty)
                || ["7500", "7600", "7700"].contains(a.squawk)

            if let od = oldDisplayed {
                let ne = a.extrapolated(at: now)
                let dLat = od.lat - ne.lat, dLon = od.lon - ne.lon
                if abs(dLat) < 0.2 && abs(dLon) < 0.2 {
                    a.corrLat = dLat
                    a.corrLon = dLon
                } else {
                    a.corrLat = 0
                    a.corrLon = 0
                }
                a.corrTime = now
            }
            aircraft[hex] = a
        }
        aircraft = aircraft.filter { now.timeIntervalSince($0.value.lastSeen) < 40 }
        return true
    }
}

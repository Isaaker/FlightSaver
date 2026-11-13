import Foundation
import ScreenSaver

enum Config {
    static let module = "com.isaaker.flightsaver"

    static var store: UserDefaults {
        (ScreenSaverDefaults(forModuleWithName: module) as UserDefaults?) ?? UserDefaults.standard
    }

    /// Copies preferences from the pre-public bundle identifier once, so an upgrade
    /// does not discard a user's existing centre coordinates or provider settings.
    static func migrateLegacyPreferencesIfNeeded() {
        let current = store
        let keys = [
            "lat", "lon", "zoomV2", "refreshV3", "apiKeyV3", "mapStyleV1",
            "mapApiKeyV1", "homeLabelV3", "labelsV2", "trailsV2", "ringsV3",
            "hudV3", "statusV3"
        ]
        guard !keys.contains(where: { current.object(forKey: $0) != nil }) else { return }
        guard let legacy = ScreenSaverDefaults(forModuleWithName: "com.local.FlightSaver") as UserDefaults? else { return }

        for key in keys {
            if let value = legacy.object(forKey: key) {
                current.set(value, forKey: key)
            }
        }
        current.synchronize()
    }
}

struct Settings {
    var lat = 40.3706            // por defecto: alrededor de LECU (Cuatro Vientos). Cámbialo en Opciones.
    var lon = -3.7853
    var zoom = 9.5
    var refresh = 3.0            // segundos entre consultas (las fuentes limitan a 1 petición/s)
    var apiKey = ""              // clave de adsb.lol (opcional; quita su límite diario)
    var mapStyle = "osm-dark"   // mapa oscuro gratuito; CARTO requiere una clave propia
    var mapApiKey = ""
    var homeLabel = "LECU"
    var labels = true
    var trails = true
    var rings = true
    var hud = true
    var status = true

    var usesCartoMap: Bool { mapStyle == "carto-dark" && !mapApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static func load() -> Settings {
        Config.migrateLegacyPreferencesIfNeeded()
        let s = Config.store
        var r = Settings()
        if let v = s.object(forKey: "lat") as? Double { r.lat = v }
        if let v = s.object(forKey: "lon") as? Double { r.lon = v }
        if let v = s.object(forKey: "zoomV2") as? Double { r.zoom = v }
        if let v = s.object(forKey: "refreshV3") as? Double { r.refresh = max(1, v) }
        if let v = s.string(forKey: "apiKeyV3") { r.apiKey = v }
        if let v = s.string(forKey: "mapStyleV1") { r.mapStyle = v }
        if let v = s.string(forKey: "mapApiKeyV1") { r.mapApiKey = v }
        if let v = s.string(forKey: "homeLabelV3") { r.homeLabel = v }
        if let v = s.object(forKey: "labelsV2") as? Bool { r.labels = v }
        if let v = s.object(forKey: "trailsV2") as? Bool { r.trails = v }
        if let v = s.object(forKey: "ringsV3") as? Bool { r.rings = v }
        if let v = s.object(forKey: "hudV3") as? Bool { r.hud = v }
        if let v = s.object(forKey: "statusV3") as? Bool { r.status = v }
        return r
    }
}

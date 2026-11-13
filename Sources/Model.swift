import Foundation

enum Geo {
    static let earthNm = 3440.065

    static func distanceNm(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = p2 - p1
        let dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * earthNm * asin(min(1, sqrt(a)))
    }

    /// Rumbo inicial de (lat1, lon1) hacia (lat2, lon2), 0-360.
    static func bearing(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dl = (lon2 - lon1) * .pi / 180
        let y = sin(dl) * cos(p2)
        let x = cos(p1) * sin(p2) - sin(p1) * cos(p2) * cos(dl)
        let deg = atan2(y, x) * 180 / .pi
        return (deg + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Web Mercator con tiles de 256 puntos; z puede ser fraccionario.
    static func worldPx(lat: Double, lon: Double, z: Double) -> (x: Double, y: Double) {
        let n = 256.0 * pow(2.0, z)
        let s = sin(min(max(lat, -85.0511), 85.0511) * .pi / 180)
        return ((lon + 180) / 360 * n, (0.5 - log((1 + s) / (1 - s)) / (4 * .pi)) * n)
    }
}

struct TrailPoint { var lat: Double; var lon: Double }

struct Aircraft {
    var hex: String
    var callsign: String
    var reg = ""
    var type = ""
    var category = ""
    var squawk = ""
    var lat: Double
    var lon: Double
    var track = 0.0              // grados, 0 = norte
    var gs = 0.0                 // nudos
    var alt: Double? = nil       // pies
    var vRate: Double? = nil     // pies/min
    var onGround = false
    var military = false
    var emergency = false
    var posTime: Date            // instante al que corresponde (lat, lon)
    var lastSeen: Date
    var firstSeen: Date
    var trail: [TrailPoint] = []
    // Corrección que se disuelve en ~1 s para que no haya saltos al llegar datos nuevos
    var corrLat = 0.0
    var corrLon = 0.0
    var corrTime = Date.distantPast

    private static let heliTypes: Set<String> = [
        "EC35", "EC45", "EC30", "EC20", "EC55", "EC25", "H60", "S76", "S92", "R22", "R44", "R66",
        "AS50", "AS55", "AS32", "AS35", "B06", "B407", "B412", "B429", "A109", "A119", "A139", "A169",
        "A189", "H145", "H135", "H160", "H500", "MI8", "UH1", "AW09", "NH90", "PUMA", "LYNX", "CH47", "H47",
    ]

    var isHelicopter: Bool { category == "A7" || Aircraft.heliTypes.contains(type) }
    var isLight: Bool { category == "A1" || category == "B1" || category == "B4" }

    /// Posición estimada avanzando desde la última medida con velocidad y rumbo.
    func extrapolated(at now: Date) -> (lat: Double, lon: Double) {
        if onGround || gs < 30 { return (lat, lon) }
        let dt = min(max(now.timeIntervalSince(posTime), 0), 30)
        let distNm = gs * dt / 3600
        let rad = track * .pi / 180
        let dLat = distNm * cos(rad) / 60
        let dLon = distNm * sin(rad) / (60 * max(cos(lat * .pi / 180), 0.1))
        return (lat + dLat, lon + dLon)
    }

    /// Posición mostrada = estimada + corrección que decae.
    func displayed(at now: Date) -> (lat: Double, lon: Double) {
        let e = extrapolated(at: now)
        let k = exp(-max(now.timeIntervalSince(corrTime), 0) / 0.9)
        return (e.lat + corrLat * k, e.lon + corrLon * k)
    }
}

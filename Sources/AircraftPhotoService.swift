import AppKit
import Foundation

/// Integración con la API pública de fotografías de Planespotters.net.
/// Primero busca por matrícula y, si no encuentra una fotografía, prueba por hex ICAO.
/// Solo conserva en memoria los metadatos (máximo 24 h); la imagen se solicita al CDN
/// de Planespotters y nunca se escribe a disco.
final class AircraftPhotoService {
    static let shared = AircraftPhotoService()

    struct PhotoInfo {
        let thumbnailURL: URL
        let pageURL: URL
        let photographer: String
    }

    private struct CachedLookup {
        let info: PhotoInfo?
        let expiresAt: Date
    }

    private var lookups: [String: CachedLookup] = [:]
    private var pendingLookups = Set<String>()
    private var pendingImages = Set<String>()
    private var blockedUntil = Date.distantPast

    private(set) var featuredHex: String?
    private(set) var featuredRegistration: String?
    private(set) var currentInfo: PhotoInfo?
    private(set) var currentImage: NSImage?
    private var featuredLookupID: String?
    private var lookupFinishedID: String?

    var isLookupFinishedForFeatured: Bool {
        guard let featuredLookupID = featuredLookupID else { return false }
        return lookupFinishedID == featuredLookupID
    }

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 12
        c.httpAdditionalHeaders = [
            "User-Agent": NetworkIdentity.userAgent,
            "Accept": "application/json"
        ]
        return URLSession(configuration: c)
    }()

    func clearFeatured() {
        featuredHex = nil
        featuredRegistration = nil
        featuredLookupID = nil
        currentInfo = nil
        currentImage = nil
        lookupFinishedID = nil
    }

    /// Actualiza el avión destacado. La matrícula es la búsqueda principal; el hex es el respaldo.
    func setFeatured(hex rawHex: String, registration rawRegistration: String) {
        let hex = normalizedHex(rawHex)
        let registration = normalizedRegistration(rawRegistration)
        guard !hex.isEmpty || !registration.isEmpty else {
            clearFeatured()
            return
        }

        // Incluye ambos identificadores: algunos feeds completan la matrícula después del hex.
        let lookupID = "\(registration)|\(hex)"
        guard lookupID != featuredLookupID else { return }

        featuredHex = hex
        featuredRegistration = registration
        featuredLookupID = lookupID
        currentInfo = nil
        currentImage = nil
        lookupFinishedID = nil

        if !registration.isEmpty {
            resolveRegistration(registration, hex: hex, lookupID: lookupID)
        } else {
            resolveHex(hex, lookupID: lookupID)
        }
    }

    private func normalizedRegistration(_ value: String) -> String {
        let compact = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .filter { !$0.isWhitespace }
            .uppercased()
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        guard !compact.isEmpty,
              compact.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "" }
        return compact
    }

    private func normalizedHex(_ value: String) -> String {
        let hex = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = CharacterSet(charactersIn: "0123456789abcdef")
        guard !hex.isEmpty, hex.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "" }
        return hex
    }

    private func markFinished(_ lookupID: String) {
        guard featuredLookupID == lookupID else { return }
        lookupFinishedID = lookupID
    }

    // MARK: Búsqueda por matrícula (preferida)

    private func resolveRegistration(_ registration: String, hex: String, lookupID: String) {
        let cacheKey = "reg:\(registration)"
        if let cached = validCachedLookup(for: cacheKey) {
            if let info = cached.info {
                markFinished(lookupID)
                display(info, for: lookupID)
            } else {
                // Una respuesta vacía por matrícula activa la búsqueda de respaldo por hex.
                resolveHex(hex, lookupID: lookupID)
            }
            return
        }

        guard !pendingLookups.contains(cacheKey) else { return }
        guard blockedUntil <= Date() else {
            markFinished(lookupID)
            return
        }
        guard let url = URL(string: "https://api.planespotters.net/pub/photos/reg/\(registration)") else {
            resolveHex(hex, lookupID: lookupID)
            return
        }
        fetchLookup(cacheKey: cacheKey, url: url, matchingRegistration: registration, matchingHex: nil, fallbackToHex: true)
    }

    // MARK: Búsqueda por hex (respaldo)

    private func resolveHex(_ hex: String, lookupID: String) {
        guard !hex.isEmpty else {
            markFinished(lookupID)
            return
        }

        let cacheKey = "hex:\(hex)"
        if let cached = validCachedLookup(for: cacheKey) {
            markFinished(lookupID)
            if let info = cached.info { display(info, for: lookupID) }
            return
        }

        guard !pendingLookups.contains(cacheKey) else { return }
        guard blockedUntil <= Date() else {
            markFinished(lookupID)
            return
        }
        guard let url = URL(string: "https://api.planespotters.net/pub/photos/hex/\(hex)") else {
            markFinished(lookupID)
            return
        }
        fetchLookup(cacheKey: cacheKey, url: url, matchingRegistration: nil, matchingHex: hex, fallbackToHex: false)
    }

    private func validCachedLookup(for key: String) -> CachedLookup? {
        guard let cached = lookups[key] else { return nil }
        if cached.expiresAt > Date() { return cached }
        lookups.removeValue(forKey: key)
        return nil
    }

    private func fetchLookup(
        cacheKey: String,
        url: URL,
        matchingRegistration: String?,
        matchingHex: String?,
        fallbackToHex: Bool
    ) {
        guard !pendingLookups.contains(cacheKey) else { return }
        pendingLookups.insert(cacheKey)

        var request = URLRequest(url: url)
        request.setValue(NetworkIdentity.userAgent, forHTTPHeaderField: "User-Agent")

        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let http = response as? HTTPURLResponse
            let code = http?.statusCode ?? 0
            let retryAfter = http?.value(forHTTPHeaderField: "Retry-After").flatMap { Double($0) }
            let info = (code == 200 && error == nil) ? data.flatMap { self.parsePhotoInfo($0) } : nil

            DispatchQueue.main.async {
                self.pendingLookups.remove(cacheKey)

                // La misma matrícula o el mismo hex puede estar representando al avión
                // destacado aunque haya cambiado su identidad compuesta durante la petición.
                let matchesCurrentAircraft: Bool
                if let registration = matchingRegistration {
                    matchesCurrentAircraft = self.featuredRegistration == registration
                } else if let hex = matchingHex {
                    matchesCurrentAircraft = self.featuredHex == hex
                } else {
                    matchesCurrentAircraft = false
                }
                guard matchesCurrentAircraft, let activeLookupID = self.featuredLookupID else { return }

                if code == 200 {
                    // Los resultados de la API se conservan como máximo 24 horas.
                    self.lookups[cacheKey] = CachedLookup(info: info, expiresAt: Date().addingTimeInterval(24 * 60 * 60))
                    if let info = info {
                        self.markFinished(activeLookupID)
                        self.display(info, for: activeLookupID)
                    } else if fallbackToHex {
                        // Una respuesta válida sin fotos (o con un esquema inesperado)
                        // también activa el respaldo por hex.
                        self.resolveHex(self.featuredHex ?? "", lookupID: activeLookupID)
                    } else {
                        self.markFinished(activeLookupID)
                    }
                    return
                }

                if code == 429 {
                    // Evita duplicar una petición cuando el proveedor ha limitado el acceso.
                    self.blockedUntil = Date().addingTimeInterval(max(retryAfter ?? 60, 30))
                    self.markFinished(activeLookupID)
                    return
                }

                if code == 404 {
                    // Sin resultados por matrícula: conserva el resultado negativo y prueba el hex.
                    self.lookups[cacheKey] = CachedLookup(info: nil, expiresAt: Date().addingTimeInterval(24 * 60 * 60))
                }

                if fallbackToHex {
                    // Incluye HTTP 403 y errores de transporte: el hex es el último recurso.
                    self.resolveHex(self.featuredHex ?? "", lookupID: activeLookupID)
                } else {
                    if code == 403 {
                        self.blockedUntil = Date().addingTimeInterval(5 * 60)
                    }
                    self.markFinished(activeLookupID)
                }

                if let error = error {
                    NSLog("FlightSaver: Planespotters request failed (%@)", error.localizedDescription)
                } else if code != 200 {
                    NSLog("FlightSaver: Planespotters returned HTTP %d for %@", code, url.absoluteString)
                }
            }
        }.resume()
    }

    private func parsePhotoInfo(_ data: Data) -> PhotoInfo? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let photos = root["photos"] as? [[String: Any]] else { return nil }

        // Some API records may be incomplete. Use the first photo with both a
        // usable thumbnail and its original Planespotters page instead of only
        // inspecting photos[0].
        for photo in photos {
            let large = photo["thumbnail_large"] as? [String: Any]
            let small = photo["thumbnail"] as? [String: Any]
            guard let imageString = (large?["src"] as? String) ?? (small?["src"] as? String),
                  let imageURL = URL(string: imageString),
                  let linkString = photo["link"] as? String,
                  let pageURL = URL(string: linkString) else { continue }

            let photographer = (photo["photographer"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return PhotoInfo(
                thumbnailURL: imageURL,
                pageURL: pageURL,
                photographer: (photographer?.isEmpty == false) ? photographer! : "Fotógrafo desconocido"
            )
        }
        return nil
    }

    private func display(_ info: PhotoInfo, for lookupID: String) {
        guard featuredLookupID == lookupID else { return }
        currentInfo = info

        let imageKey = info.thumbnailURL.absoluteString
        guard !pendingImages.contains(imageKey) else { return }
        pendingImages.insert(imageKey)

        var request = URLRequest(url: info.thumbnailURL)
        request.setValue(NetworkIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        session.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            DispatchQueue.main.async {
                self.pendingImages.remove(imageKey)
                guard self.currentInfo?.thumbnailURL.absoluteString == imageKey else { return }
                if status == 200, let data = data, let image = NSImage(data: data) {
                    self.currentImage = image
                } else if let error = error {
                    NSLog("FlightSaver: Planespotters image download failed (%@)", error.localizedDescription)
                } else {
                    NSLog("FlightSaver: Planespotters image CDN returned HTTP %d for %@", status, info.thumbnailURL.host ?? "unknown host")
                }
            }
        }.resume()
    }
}

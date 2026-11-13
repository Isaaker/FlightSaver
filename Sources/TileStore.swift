import AppKit
import CoreImage

/// Tiles CARTO Dark Matter (con clave) u OpenStreetMap estándar transformado a oscuro.
/// La caché local respeta una retención mínima de siete días para los tiles OSM.
final class TileStore {
    static let shared = TileStore()

    private(set) var version = 0
    private var images: [String: NSImage] = [:]
    private var pending = Set<String>()
    private var retryAt: [String: Date] = [:]
    private let cacheTTL: TimeInterval = 7 * 24 * 60 * 60
    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    private lazy var session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 15
        c.httpAdditionalHeaders = ["User-Agent": NetworkIdentity.userAgent]
        return URLSession(configuration: c)
    }()

    var loadedCount: Int { images.count }

    func image(z: Int, x: Int, y: Int, style: String, apiKey: String) -> NSImage? {
        let useCarto = style == "carto-dark" && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let provider = useCarto ? "carto-dark" : "osm-dark"
        let key = "\(provider)/\(z)/\(x)/\(y)"
        if let img = images[key] { return img }
        if pending.contains(key) { return nil }
        if let t = retryAt[key], t > Date() { return nil }

        if let cached = readDiskCache(provider: provider, z: z, x: x, y: y),
           let img = makeImage(data: cached, darken: !useCarto) {
            images[key] = img
            return img
        }

        pending.insert(key)
        if useCarto {
            var queryCharacters = CharacterSet.urlQueryAllowed
            queryCharacters.remove(charactersIn: "&=+#?")
            let safeKey = apiKey.addingPercentEncoding(withAllowedCharacters: queryCharacters) ?? apiKey
            let url = URL(string: "https://basemaps.cartocdn.com/rastertiles/dark_all/\(z)/\(x)/\(y).png?key=\(safeKey)")
            if let url = url {
                fetch(url: url) { [weak self] data in
                    guard let self = self else { return }
                    if let data = data, self.isImage(data), let image = self.makeImage(data: data, darken: false) {
                        self.finish(data: data, image: image, key: key, provider: provider, z: z, x: x, y: y)
                    } else {
                        // Un fallo de CARTO nunca deja el salvapantallas con un mapa vacío:
                        // se recurre automáticamente al mapa libre, sin clave.
                        self.fetchOpenStreetMapFallback(key: key, provider: provider, z: z, x: x, y: y)
                    }
                }
            } else {
                fetchOpenStreetMapFallback(key: key, provider: provider, z: z, x: x, y: y)
            }
        } else {
            fetchOpenStreetMap(z: z, x: x, y: y) { [weak self] data in
                guard let self = self else { return }
                guard let data = data, let image = self.makeImage(data: data, darken: true) else {
                    self.fail(key: key)
                    return
                }
                self.finish(data: data, image: image, key: key, provider: provider, z: z, x: x, y: y)
            }
        }
        return nil
    }

    private func fetchOpenStreetMapFallback(key: String, provider: String, z: Int, x: Int, y: Int) {
        fetchOpenStreetMap(z: z, x: x, y: y) { [weak self] data in
            guard let self = self else { return }
            guard let data = data, let image = self.makeImage(data: data, darken: true) else {
                self.fail(key: key)
                return
            }
            self.finish(data: data, image: image, key: key, provider: provider, z: z, x: x, y: y, writeCache: false)
        }
    }

    private func fetchOpenStreetMap(z: Int, x: Int, y: Int, completion: @escaping (Data?) -> Void) {
        guard let url = URL(string: "https://tile.openstreetmap.org/\(z)/\(x)/\(y).png") else {
            completion(nil)
            return
        }
        fetch(url: url, completion: completion)
    }

    private func fetch(url: URL, completion: @escaping (Data?) -> Void) {
        session.dataTask(with: url) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            completion(status == 200 ? data : nil)
        }.resume()
    }

    private func isImage(_ data: Data) -> Bool { CIImage(data: data) != nil }

    private func makeImage(data: Data, darken: Bool) -> NSImage? {
        guard var ci = CIImage(data: data) else { return nil }
        if darken {
            let invert = CIFilter(name: "CIColorInvert")
            invert?.setValue(ci, forKey: kCIInputImageKey)
            if let output = invert?.outputImage { ci = output }

            let controls = CIFilter(name: "CIColorControls")
            controls?.setValue(ci, forKey: kCIInputImageKey)
            controls?.setValue(0.16, forKey: kCIInputSaturationKey)
            controls?.setValue(1.08, forKey: kCIInputContrastKey)
            controls?.setValue(0.015, forKey: kCIInputBrightnessKey)
            if let output = controls?.outputImage { ci = output }
        }
        guard let cg = ciContext.createCGImage(ci, from: ci.extent) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height)))
    }

    private func finish(data: Data, image: NSImage, key: String, provider: String, z: Int, x: Int, y: Int, writeCache: Bool = true) {
        if writeCache { writeDiskCache(data, provider: provider, z: z, x: x, y: y) }
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pending.remove(key)
            self.retryAt.removeValue(forKey: key)
            self.images[key] = image
            if self.images.count > 500 { self.images = [key: image] }
            self.version += 1
        }
    }

    private func fail(key: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.pending.remove(key)
            self.retryAt[key] = Date().addingTimeInterval(30)
        }
    }

    private func cacheURL(provider: String, z: Int, x: Int, y: Int) -> URL? {
        guard let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = root.appendingPathComponent("FlightSaver/MapTiles/\(provider)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("\(z)_\(x)_\(y).png")
    }

    private func readDiskCache(provider: String, z: Int, x: Int, y: Int) -> Data? {
        guard let url = cacheURL(provider: provider, z: z, x: x, y: y),
              let values = try? url.resourceValues(forKeys: [.contentModificationDateKey]),
              let modified = values.contentModificationDate,
              Date().timeIntervalSince(modified) <= cacheTTL else { return nil }
        return try? Data(contentsOf: url)
    }

    private func writeDiskCache(_ data: Data, provider: String, z: Int, x: Int, y: Int) {
        guard let url = cacheURL(provider: provider, z: z, x: x, y: y) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

import AppKit

final class ConfigController: NSObject {
    let window: NSWindow
    private let latField = NSTextField()
    private let lonField = NSTextField()
    private let zoomField = NSTextField()
    private let refreshField = NSTextField()
    private let homeField = NSTextField()
    private let adsbKeyField = NSSecureTextField()
    private let mapKeyField = NSSecureTextField()
    private let mapStylePopup = NSPopUpButton()

    private let labelsBox = NSButton(checkboxWithTitle: "Etiquetas (indicativo, altitud, velocidad y tipo)", target: nil, action: nil)
    private let trailsBox = NSButton(checkboxWithTitle: "Estelas de las aeronaves", target: nil, action: nil)
    private let ringsBox = NSButton(checkboxWithTitle: "Anillos de distancia (NM)", target: nil, action: nil)
    private let hudBox = NSButton(checkboxWithTitle: "Resumen de tráfico y ficha del avión destacado", target: nil, action: nil)
    private let statusBox = NSButton(checkboxWithTitle: "Línea de estado inferior", target: nil, action: nil)

    override init() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 570),
                          styleMask: [.titled], backing: .buffered, defer: false)
        super.init()
        build()
    }

    private func addRow(_ title: String, view: NSView, y: CGFloat, width: CGFloat, hint: String? = nil) {
        let label = NSTextField(labelWithString: title)
        label.frame = NSRect(x: 20, y: y, width: 132, height: 22)
        window.contentView?.addSubview(label)

        view.frame = NSRect(x: 160, y: y, width: width, height: 22)
        window.contentView?.addSubview(view)

        if let hint = hint {
            let text = NSTextField(labelWithString: hint)
            text.font = .systemFont(ofSize: 10)
            text.textColor = .secondaryLabelColor
            text.frame = NSRect(x: 160 + width + 8, y: y, width: max(80, 600 - (160 + width + 8)), height: 22)
            window.contentView?.addSubview(text)
        }
    }

    private func build() {
        window.title = "FlightSaver · Opciones"
        let s = Settings.load()

        addRow("Latitud", view: latField, y: 520, width: 130)
        addRow("Longitud", view: lonField, y: 487, width: 130)
        addRow("Zoom", view: zoomField, y: 454, width: 130, hint: "3 (amplio) – 14 (cercano)")
        addRow("Refresco (s)", view: refreshField, y: 421, width: 130, hint: "mín. 1")
        addRow("Etiqueta central", view: homeField, y: 388, width: 230, hint: "p. ej. LECU")
        addRow("Clave adsb.lol", view: adsbKeyField, y: 355, width: 420)

        mapStylePopup.addItems(withTitles: ["Mapa oscuro gratuito · OpenStreetMap", "CARTO Dark Matter · requiere clave"])
        addRow("Estilo del mapa", view: mapStylePopup, y: 322, width: 280)
        addRow("Clave CARTO", view: mapKeyField, y: 289, width: 420)

        let note = NSTextField(wrappingLabelWithString:
            "El mapa oscuro gratuito no necesita cuenta ni API key. CARTO puede usarse con una clave personal gratuita; si falla, FlightSaver vuelve automáticamente al mapa gratuito. Las claves se guardan en las preferencias del salvapantallas.")
        note.font = .systemFont(ofSize: 10)
        note.textColor = .secondaryLabelColor
        note.frame = NSRect(x: 160, y: 235, width: 430, height: 42)
        window.contentView?.addSubview(note)

        var y: CGFloat = 205
        for box in [labelsBox, trailsBox, ringsBox, hudBox, statusBox] {
            box.frame = NSRect(x: 160, y: y, width: 430, height: 22)
            window.contentView?.addSubview(box)
            y -= 25
        }

        latField.stringValue = String(s.lat)
        lonField.stringValue = String(s.lon)
        zoomField.stringValue = String(s.zoom)
        refreshField.stringValue = String(s.refresh)
        homeField.stringValue = s.homeLabel
        adsbKeyField.stringValue = s.apiKey
        mapKeyField.stringValue = s.mapApiKey
        mapStylePopup.selectItem(at: s.mapStyle == "carto-dark" ? 1 : 0)
        labelsBox.state = s.labels ? .on : .off
        trailsBox.state = s.trails ? .on : .off
        ringsBox.state = s.rings ? .on : .off
        hudBox.state = s.hud ? .on : .off
        statusBox.state = s.status ? .on : .off

        let ok = NSButton(title: "Guardar", target: self, action: #selector(save))
        ok.frame = NSRect(x: 500, y: 14, width: 90, height: 28)
        ok.keyEquivalent = "\r"
        let cancel = NSButton(title: "Cancelar", target: self, action: #selector(cancel))
        cancel.frame = NSRect(x: 400, y: 14, width: 90, height: 28)
        window.contentView?.addSubview(ok)
        window.contentView?.addSubview(cancel)
    }

    private func dbl(_ f: NSTextField) -> Double? {
        Double(f.stringValue.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }

    @objc private func save() {
        let s = Config.store
        if let v = dbl(latField) { s.set(min(max(v, -85), 85), forKey: "lat") }
        if let v = dbl(lonField) { s.set(min(max(v, -180), 180), forKey: "lon") }
        if let v = dbl(zoomField) { s.set(min(max(v, 3), 14), forKey: "zoomV2") }
        if let v = dbl(refreshField) { s.set(max(v, 1), forKey: "refreshV3") }
        s.set(homeField.stringValue.trimmingCharacters(in: .whitespaces), forKey: "homeLabelV3")
        s.set(adsbKeyField.stringValue.trimmingCharacters(in: .whitespaces), forKey: "apiKeyV3")
        s.set(mapStylePopup.indexOfSelectedItem == 1 ? "carto-dark" : "osm-dark", forKey: "mapStyleV1")
        s.set(mapKeyField.stringValue.trimmingCharacters(in: .whitespaces), forKey: "mapApiKeyV1")
        s.set(labelsBox.state == .on, forKey: "labelsV2")
        s.set(trailsBox.state == .on, forKey: "trailsV2")
        s.set(ringsBox.state == .on, forKey: "ringsV3")
        s.set(hudBox.state == .on, forKey: "hudV3")
        s.set(statusBox.state == .on, forKey: "statusV3")
        s.synchronize()
        close()
    }

    @objc private func cancel() { close() }

    private func close() {
        if let parent = window.sheetParent { parent.endSheet(window) } else { window.close() }
    }
}

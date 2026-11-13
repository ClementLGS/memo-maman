import Foundation

/// Mises à jour de l'interface, SANS signature : la page reçue est enregistrée si elle a l'air d'une interface valide.
/// L'empreinte « uisha » de version.json détecte un téléchargement abîmé ou tronqué, pas une origine douteuse
/// (qui contrôle le dépôt GitHub peut changer l'interface : ne jamais y mettre de donnée, les notes restent sur le téléphone).
enum Ota {
    /// Niveau du pont natif : une interface qui exige plus (marqueur TDBA) est refusée plutôt que d'être cassée.
    static let bridgeLevel = 1

    private static let defaults = UserDefaults.standard
    private static let buildKey = "memorh.ota.build"
    private static var pending = ""

    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("www", isDirectory: true)
    }
    static var file: URL { dir.appendingPathComponent("index.html") }

    /// Valeur du marqueur « TDBV:123 » / « TDBA:123 » dans la page, ou -1.
    static func mark(_ text: String, _ key: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: key + ":(\\d+)"),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text), let v = Int(text[r]) else { return -1 }
        return v
    }

    /// Contrôle d'une interface reçue : nil si elle est acceptable, sinon le message d'erreur (« err:… »).
    static func problem(html: String, versionJson: String) -> String? {
        let bytes = Data(html.utf8)
        if let data = versionJson.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let want = obj["uisha"] as? String, !want.isEmpty,
           want.lowercased() != Hash.sha256Hex(bytes) {
            return "err:le fichier reçu ne correspond pas à version.json (téléchargement abîmé, ou version.json pas à jour)"
        }
        if bytes.count < 8000 || !html.contains("window.MEMO_RH") { return "err:fichier d'interface invalide" }
        let v = mark(html, "TDBV"), a = mark(html, "TDBA")
        if v < 0 || a < 0 { return "err:fichier d'interface sans numéro de version" }
        if a > bridgeLevel {
            return "err:cette interface demande une appli plus récente (niveau \(a), actuel \(bridgeLevel)) : réinstalle l'appli"
        }
        return nil
    }

    /// Page à afficher et dossier qu'elle peut lire : l'interface mise à jour si elle est valide, sinon celle livrée avec l'appli.
    static func page() -> (page: URL, readAccess: URL)? {
        guard let bundled = Bundle.main.url(forResource: "index", withExtension: "html") else { return nil }
        let fallback = (page: bundled, readAccess: bundled.deletingLastPathComponent())
        let fm = FileManager.default
        // Nouvelle installation de l'appli (interface livrée différente) : l'ancienne mise à jour est écartée,
        // l'interface livrée prend le relais et la prochaine vérification récupère ce qui est plus récent.
        if let d = try? Data(contentsOf: bundled) {
            let id = Hash.sha256Hex(d)
            if defaults.string(forKey: buildKey) != id {
                try? fm.removeItem(at: file)
                defaults.set(id, forKey: buildKey)
            }
        }
        guard fm.fileExists(atPath: file.path) else { return fallback }
        guard let t = try? String(contentsOf: file, encoding: .utf8), problem(html: t, versionJson: "") == nil else {
            try? fm.removeItem(at: file)
            return fallback
        }
        return (page: file, readAccess: dir)
    }

    // L'interface arrive par morceaux (appels synchrones courts depuis la page), puis on valide le tout.
    static func begin() { pending = "" }
    static func chunk(_ s: String) { pending += s }

    static func commit(versionJson: String) -> String {
        let html = pending
        pending = ""
        if let err = problem(html: html, versionJson: versionJson) { return err }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(html.utf8).write(to: file, options: .atomic)
        } catch {
            return "err:écriture impossible"
        }
        return "ok:\(mark(html, "TDBV"))"
    }
}

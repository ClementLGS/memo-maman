import Foundation

/// Stockage des notes : un fichier JSON dans « Documents » (visible dans l'app Fichiers > Sur mon iPhone > Mémo RH),
/// plus une copie de sécurité par jour (les 7 dernières sont gardées).
enum Store {
    static var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    static var file: URL { dir.appendingPathComponent("memo-rh.json") }
    private static let backupPrefix = "memo-rh-sauvegarde-"

    /// Un texte est accepté seulement si c'est un objet JSON avec un tableau « cats » (évite d'écraser les notes par n'importe quoi).
    static func valid(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["cats"] is [Any] else { return false }
        return true
    }

    /// « empty » s'il n'y a pas encore de fichier, « ok:<contenu> » sinon, « err:… » si la lecture échoue.
    static func read() -> String {
        guard FileManager.default.fileExists(atPath: file.path) else { return "empty" }
        guard let t = try? String(contentsOf: file, encoding: .utf8) else { return "err:lecture impossible" }
        return "ok:" + t
    }

    static func write(_ text: String) -> String {
        guard valid(text) else { return "err:données invalides" }
        let fm = FileManager.default
        do {
            if fm.fileExists(atPath: file.path) { try dailyBackup() }
            try Data(text.utf8).write(to: file, options: .atomic)
        } catch {
            return "err:écriture impossible"
        }
        return "ok"
    }

    /// Avant la première écriture du jour : copie du fichier actuel, puis suppression des sauvegardes au-delà de 7.
    private static func dailyBackup() throws {
        let fm = FileManager.default
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let target = dir.appendingPathComponent(backupPrefix + f.string(from: Date()) + ".json")
        if !fm.fileExists(atPath: target.path) { try fm.copyItem(at: file, to: target) }
        let names = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).filter { $0.hasPrefix(backupPrefix) }.sorted()
        if names.count > 7 {
            for n in names.prefix(names.count - 7) { try? fm.removeItem(at: dir.appendingPathComponent(n)) }
        }
    }
}

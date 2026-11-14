import Foundation

/// Fichier de réglages « reglages.txt » déposé dans Fichiers > Sur mon iPhone > Prise de notes Ciolek.
/// Lignes « clé = valeur » ; tout ce qui suit un « # » en début de ligne est ignoré. Lu à l'ouverture de l'appli, puis supprimé.
enum Config {
    static var file: URL { Store.dir.appendingPathComponent("reglages.txt") }

    struct Values: Equatable {
        var update = ""      // mise_a_jour = propriétaire/nom[@branche]
        var backupRepo = ""  // sauvegarde_depot = propriétaire/nom
        var token = ""       // sauvegarde_jeton = github_pat_…
    }

    /// Les valeurs d'exemple du modèle (« propriétaire/… », « colle_ici… ») sont traitées comme « non rempli ».
    static func isPlaceholder(_ v: String) -> Bool {
        let l = v.lowercased()
        return l.isEmpty || l.hasPrefix("colle_ici") || l.contains("votre-") || l.hasPrefix("<")
    }

    static func parse(_ text: String) -> Values {
        var v = Values()
        let clean = text.replacingOccurrences(of: "\u{FEFF}", with: "")
        for raw in clean.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq].trimmingCharacters(in: .whitespaces).lowercased()
                .folding(options: .diacriticInsensitive, locale: nil)
            var val = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if val.count >= 2, let f = val.first, let l = val.last, (f == "\"" && l == "\"") || (f == "“" && l == "”") { val = String(val.dropFirst().dropLast()) }
            if isPlaceholder(val) { continue }
            switch key {
            case "mise_a_jour", "mise_a_jour_source": v.update = val
            case "sauvegarde_depot": v.backupRepo = val
            case "sauvegarde_jeton": v.token = val
            default: break
            }
        }
        return v
    }

    /// Vérifie les valeurs ; renvoie un message d'erreur ou nil.
    static func problem(_ v: Values) -> String? {
        if !v.update.isEmpty, v.update.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(@[A-Za-z0-9_./-]+)?$", options: .regularExpression) == nil {
            return "mise_a_jour : format attendu propriétaire/nom ou propriétaire/nom@branche"
        }
        if !v.backupRepo.isEmpty, !Backup.validRepo(v.backupRepo) { return "sauvegarde_depot : format attendu propriétaire/nom" }
        if !v.token.isEmpty, v.backupRepo.isEmpty, Backup.repo.isEmpty { return "sauvegarde_jeton : indique aussi sauvegarde_depot" }
        if v.update.isEmpty && v.backupRepo.isEmpty && v.token.isEmpty { return "aucune valeur remplie dans le fichier" }
        return nil
    }

    /// Absent : « none ». Sinon « ok:<mise à jour>|<dépôt>|<jeton enregistré 0/1> » (le fichier est alors supprimé) ou « err:… » (le fichier reste).
    static func importFile() -> String {
        guard FileManager.default.fileExists(atPath: file.path) else { return "none" }
        guard let t = try? String(contentsOf: file, encoding: .utf8) else { return "err:fichier reglages.txt illisible (enregistre-le en texte brut UTF-8)" }
        let v = parse(t)
        if let p = problem(v) { return "err:" + p }
        if !v.backupRepo.isEmpty || !v.token.isEmpty {
            let r = Backup.configure(repo: v.backupRepo.isEmpty ? Backup.repo : v.backupRepo, token: v.token)
            if r != "ok" { return r }
        }
        try? FileManager.default.removeItem(at: file)
        return "ok:\(v.update)|\(v.backupRepo)|\(v.token.isEmpty ? 0 : 1)"
    }
}

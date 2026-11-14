import Foundation

/// Sauvegarde des notes dans un dépôt GitHub PRIVÉ (fichier notes.json : l'historique Git garde les versions successives).
/// Déclenchée par la page (à l'ouverture, au retour dans l'appli, quelques minutes après une modification, ou à la demande) :
/// iOS ne laisse pas une appli installée hors App Store travailler en arrière-plan, donc rien ne part si l'appli reste fermée.
enum Backup {
    static let repoKey = "memorh.backup.repo"
    static let lastTsKey = "memorh.backup.ts"
    static let lastHashKey = "memorh.backup.hash"
    /// Entre deux sauvegardes automatiques : au moins une heure (et seulement si les notes ont changé).
    static let minInterval: TimeInterval = 3600
    private static let defaults = UserDefaults.standard

    /// « propriétaire/nom » : lettres, chiffres, point, tiret, souligné.
    static func validRepo(_ s: String) -> Bool {
        return s.range(of: "^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", options: .regularExpression) != nil
    }

    static var repo: String { return defaults.string(forKey: repoKey) ?? "" }
    static var lastTs: TimeInterval { return defaults.double(forKey: lastTsKey) }

    /// « ok:<dépôt>|<1 si un jeton est enregistré>|<date de la dernière sauvegarde, secondes>»
    static func status() -> String {
        return "ok:\(repo)|\(Keychain.get() == nil ? 0 : 1)|\(Int(lastTs))"
    }

    /// Enregistre le dépôt et le jeton (jeton vide = garder l'ancien).
    static func configure(repo r: String, token: String) -> String {
        let rr = r.trimmingCharacters(in: .whitespacesAndNewlines)
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard validRepo(rr) else { return "err:dépôt invalide (format : propriétaire/nom)" }
        if !t.isEmpty {
            guard Keychain.set(t) else { return "err:jeton non enregistré" }
        } else if Keychain.get() == nil {
            return "err:jeton manquant"
        }
        defaults.set(rr, forKey: repoKey)
        defaults.removeObject(forKey: lastHashKey) // la prochaine vérification sauvegarde sans attendre
        return "ok"
    }

    static func forget() -> String {
        Keychain.delete()
        defaults.removeObject(forKey: repoKey)
        defaults.removeObject(forKey: lastHashKey)
        defaults.removeObject(forKey: lastTsKey)
        return "ok"
    }

    /// nil : il faut sauvegarder. Sinon la raison de ne pas le faire.
    static func skipReason(configured: Bool, hash: String, lastHash: String?, lastTs: TimeInterval, now: TimeInterval, manual: Bool) -> String? {
        if !configured { return "skip:non configuré" }
        if manual { return nil }
        if hash == lastHash { return "skip:à jour" }
        if lastHash != nil && now - lastTs < minInterval { return "skip:attente" }
        return nil
    }

    static func putBody(message: String, content: Data, sha: String?) -> Data? {
        var o: [String: Any] = ["message": message, "content": content.base64EncodedString()]
        if let sha = sha { o["sha"] = sha }
        return try? JSONSerialization.data(withJSONObject: o)
    }

    /// Lance la sauvegarde (ou explique pourquoi pas). Résultat : « ok », « ok:inchangé », « skip:… » ou « err:… » ; appelé sur un fil quelconque.
    static func run(manual: Bool, completion: @escaping (String) -> Void) {
        let raw = Store.read()
        guard raw.hasPrefix("ok:") else { completion(raw == "empty" ? "skip:aucune note" : raw); return }
        let data = Data(String(raw.dropFirst(3)).utf8)
        let hash = Hash.sha256Hex(data)
        let token = Keychain.get() ?? ""
        let repoName = repo
        let configured = validRepo(repoName) && !token.isEmpty
        if let why = skipReason(configured: configured, hash: hash, lastHash: defaults.string(forKey: lastHashKey),
                                lastTs: lastTs, now: Date().timeIntervalSince1970, manual: manual) {
            completion(why)
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(repoName)/contents/notes.json") else { completion("err:adresse invalide"); return }

        func request(_ method: String, body: Data?) -> URLRequest {
            var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
            r.httpMethod = method
            r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            r.setValue("PriseDeNotesCiolek", forHTTPHeaderField: "User-Agent")
            if let b = body { r.httpBody = b; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
            return r
        }
        func done(_ result: String) {
            if result.hasPrefix("ok") {
                defaults.set(hash, forKey: lastHashKey)
                defaults.set(Date().timeIntervalSince1970, forKey: lastTsKey)
            }
            completion(result)
        }

        // 1) fichier actuel (pour son empreinte « sha », exigée par GitHub pour le remplacer)
        URLSession.shared.dataTask(with: request("GET", body: nil)) { gd, gr, ge in
            let st = (gr as? HTTPURLResponse)?.statusCode ?? 0
            if st == 0 { done("err:réseau indisponible"); return }
            var sha: String?
            if st == 200, let gd = gd, let o = try? JSONSerialization.jsonObject(with: gd) as? [String: Any] {
                sha = o["sha"] as? String
                let remote = (o["content"] as? String)?.replacingOccurrences(of: "\n", with: "")
                if remote == data.base64EncodedString() { done("ok:inchangé"); return }
            } else if st == 401 || st == 403 {
                done("err:jeton refusé ou expiré"); return
            } else if st != 404 {
                done("err:GitHub a répondu \(st)"); return
            }
            // 2) envoi
            let f = DateFormatter()
            f.locale = Locale(identifier: "fr_FR")
            f.timeZone = TimeZone(identifier: "Europe/Paris")
            f.dateFormat = "yyyy-MM-dd HH:mm"
            guard let body = putBody(message: "Sauvegarde " + f.string(from: Date()), content: data, sha: sha) else { done("err:préparation impossible"); return }
            URLSession.shared.dataTask(with: request("PUT", body: body)) { _, pr, _ in
                let ps = (pr as? HTTPURLResponse)?.statusCode ?? 0
                switch ps {
                case 200, 201: done("ok")
                case 0: done("err:réseau indisponible")
                case 401, 403: done("err:jeton refusé (il doit avoir le droit « Contents : lecture et écriture » sur ce dépôt)")
                case 404: done("err:dépôt introuvable, ou jeton sans accès à ce dépôt")
                case 409, 422: done("err:conflit avec une autre sauvegarde, réessaie")
                default: done("err:GitHub a répondu \(ps)")
                }
            }.resume()
        }.resume()
    }

    /// Chemin du fichier de remarques envoyées : feedback/AAAA-MM-JJ-HHMMSS.md (heure de Paris).
    static func feedbackPath(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "feedback/" + f.string(from: d) + ".md"
    }

    /// Dépose les remarques (texte Markdown fourni par la page) dans le dépôt de sauvegarde. Résultat : « ok » ou « err:… ».
    static func sendFeedback(_ text: String, completion: @escaping (String) -> Void) {
        let token = Keychain.get() ?? ""
        let repoName = repo
        guard validRepo(repoName), !token.isEmpty else { completion("err:sauvegarde GitHub non configurée (Réglages)"); return }
        let data = Data(text.utf8)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, data.count < 200_000 else { completion("err:remarques vides ou trop longues"); return }
        guard let url = URL(string: "https://api.github.com/repos/\(repoName)/contents/\(feedbackPath(Date()))"),
              let body = putBody(message: "Feedback de l'appli", content: data, sha: nil) else { completion("err:préparation impossible"); return }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        r.httpMethod = "PUT"
        r.httpBody = body
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("PriseDeNotesCiolek", forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        URLSession.shared.dataTask(with: r) { _, resp, _ in
            switch (resp as? HTTPURLResponse)?.statusCode ?? 0 {
            case 200, 201: completion("ok")
            case 0: completion("err:réseau indisponible")
            case 401, 403: completion("err:jeton refusé (droit « Contents : lecture et écriture » nécessaire)")
            case 404: completion("err:dépôt introuvable, ou jeton sans accès à ce dépôt")
            case 409, 422: completion("err:conflit, réessaie dans une seconde")
            case let c: completion("err:GitHub a répondu \(c)")
            }
        }.resume()
    }
}

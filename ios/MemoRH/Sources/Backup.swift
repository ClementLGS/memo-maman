import Foundation

/// Synchronisation et sauvegarde des notes dans un dépôt GitHub PRIVÉ (fichier notes.json : l'historique Git garde les versions successives).
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

    // MARK: - Synchronisation (la page fusionne ; l'appli ne fait que lire et écrire notes.json)

    /// Texte (UTF-8) d'un champ « content » renvoyé par GitHub (base64 coupé en lignes).
    static func decodeContent(_ b64: String) -> String? {
        let clean = b64.replacingOccurrences(of: "\n", with: "").replacingOccurrences(of: "\r", with: "")
        guard !clean.isEmpty, let d = Data(base64Encoded: clean) else { return nil }
        return String(data: d, encoding: .utf8)
    }

    /// Message d'erreur lisible pour un code HTTP d'écriture ; nil si c'est un succès. « conflict » = le fichier a changé entre-temps.
    static func pushOutcome(_ status: Int) -> String? {
        switch status {
        case 200, 201: return nil
        case 0: return "err:réseau indisponible"
        case 401, 403: return "err:jeton refusé (droit « Contents : lecture et écriture » nécessaire)"
        case 404: return "err:dépôt introuvable, ou jeton sans accès à ce dépôt"
        case 409, 422: return "conflict"
        case let c: return "err:GitHub a répondu \(c)"
        }
    }

    private static func notesRequest(_ method: String, body: Data?) -> URLRequest? {
        let token = Keychain.get() ?? ""
        guard validRepo(repo), !token.isEmpty, let url = URL(string: "https://api.github.com/repos/\(repo)/contents/notes.json") else { return nil }
        var r = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        r.setValue("PriseDeNotesCiolek", forHTTPHeaderField: "User-Agent")
        if let b = body { r.httpBody = b; r.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        return r
    }

    /// Lit notes.json. Rappel : (« ok » | « none » | « err:… », sha, texte).
    static func pull(completion: @escaping (String, String, String) -> Void) {
        guard let req = notesRequest("GET", body: nil) else { completion("err:synchronisation non configurée (Réglages)", "", ""); return }
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            switch st {
            case 0: completion("err:réseau indisponible", "", "")
            case 404: completion("none", "", "")
            case 401, 403: completion("err:jeton refusé ou expiré", "", "")
            case 200:
                guard let data = data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let sha = o["sha"] as? String, let c = o["content"] as? String, let text = decodeContent(c)
                else { completion("err:fichier distant vide ou trop gros", "", ""); return }
                completion("ok", sha, text)
            default: completion("err:GitHub a répondu \(st)", "", "")
            }
        }.resume()
    }

    /// Écrit notes.json (sha = version qu'on a lue, vide si le fichier n'existe pas encore). Rappel : (« ok » | « conflict » | « err:… », nouveau sha).
    static func push(text: String, sha: String, completion: @escaping (String, String) -> Void) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        guard !text.isEmpty, text.utf8.count < 5_000_000,
              let body = putBody(message: "Synchronisation " + f.string(from: Date()), content: Data(text.utf8), sha: sha.isEmpty ? nil : sha),
              let req = notesRequest("PUT", body: body) else { completion("err:synchronisation non configurée (Réglages)", ""); return }
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            let st = (resp as? HTTPURLResponse)?.statusCode ?? 0
            if let bad = pushOutcome(st) { completion(bad, ""); return }
            var newSha = ""
            if let data = data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let c = o["content"] as? [String: Any] { newSha = (c["sha"] as? String) ?? "" }
            completion("ok", newSha)
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

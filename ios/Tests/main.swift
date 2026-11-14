import Foundation

// Tests du contrôle des mises à jour (Ota.swift) et du stockage (Store.swift) : mêmes fichiers que l'appli.
var failed = false
func check(_ name: String, _ ok: Bool) { print((ok ? "OK      " : "ECHEC   ") + name); if !ok { failed = true } }
check("sha256 de « abc »", Hash.sha256Hex(Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")

func page(_ v: Int, _ a: Int, marker: Bool = true, size: Int = 12000) -> String {
    return "<!--TDBV:\(v) TDBA:\(a)-->" + (marker ? "window.MEMO_RH" : "") + String(repeating: "x", count: size)
}
let ok1 = page(1001, 1)
let vjOk = "{\"ui\":1001,\"uisha\":\"" + Hash.sha256Hex(Data(ok1.utf8)) + "\"}"
check("interface valide acceptée (avec empreinte)", Ota.problem(html: ok1, versionJson: vjOk) == nil)
check("interface valide acceptée (sans version.json)", Ota.problem(html: ok1, versionJson: "") == nil)
check("empreinte fausse refusée", Ota.problem(html: ok1 + "x", versionJson: vjOk)?.contains("version.json") == true)
check("sans window.MEMO_RH refusée", Ota.problem(html: page(1001, 1, marker: false), versionJson: "") != nil)
check("fichier trop petit refusé", Ota.problem(html: page(1001, 1, size: 100), versionJson: "") != nil)
check("sans numéro de version refusé", Ota.problem(html: "window.MEMO_RH" + String(repeating: "x", count: 12000), versionJson: "") != nil)
check("interface qui exige une appli plus récente refusée", Ota.problem(html: page(1001, Ota.bridgeLevel + 1), versionJson: "")?.contains("plus récente") == true)
check("marqueurs lus", Ota.mark(ok1, "TDBV") == 1001 && Ota.mark(ok1, "TDBA") == 1 && Ota.mark("rien", "TDBV") == -1)

check("notes valides acceptées", Store.valid("{\"v\":1,\"cats\":[]}"))
check("texte quelconque refusé", !Store.valid("n'importe quoi") && !Store.valid("") && !Store.valid("[]"))
check("objet sans cats refusé", !Store.valid("{\"v\":1}") && !Store.valid("{\"cats\":3}"))


// Sauvegarde GitHub : format du dépôt, quand sauvegarder, corps de la requête
check("dépôt valide", Backup.validRepo("ClementLGS/memo-maman-sauvegardes") && Backup.validRepo("a.b/c_d-e"))
check("dépôt invalide refusé", !Backup.validRepo("") && !Backup.validRepo("sans-barre") && !Backup.validRepo("a/b/c") && !Backup.validRepo("a b/c") && !Backup.validRepo("https://github.com/a/b"))
check("non configuré : pas de sauvegarde", Backup.skipReason(configured: false, hash: "h", lastHash: nil, lastTs: 0, now: 10, manual: true) == "skip:non configuré")
check("première sauvegarde : tout de suite", Backup.skipReason(configured: true, hash: "h", lastHash: nil, lastTs: 0, now: 10, manual: false) == nil)
check("notes inchangées : rien à faire", Backup.skipReason(configured: true, hash: "h", lastHash: "h", lastTs: 0, now: 99999, manual: false) == "skip:à jour")
check("notes changées depuis moins d'une heure : attente", Backup.skipReason(configured: true, hash: "h2", lastHash: "h", lastTs: 1000, now: 1000 + 600, manual: false) == "skip:attente")
check("notes changées depuis plus d'une heure : sauvegarde", Backup.skipReason(configured: true, hash: "h2", lastHash: "h", lastTs: 1000, now: 1000 + 3700, manual: false) == nil)
check("à la demande : toujours", Backup.skipReason(configured: true, hash: "h", lastHash: "h", lastTs: 1000, now: 1001, manual: true) == nil)
if let b = Backup.putBody(message: "m", content: Data("{\"cats\":[]}".utf8), sha: "abc"),
   let o = try? JSONSerialization.jsonObject(with: b) as? [String: Any] {
    check("corps de requête : contenu en base64 + sha", o["sha"] as? String == "abc" && o["message"] as? String == "m" && o["content"] as? String == Data("{\"cats\":[]}".utf8).base64EncodedString())
} else { check("corps de requête lisible", false) }
if let b = Backup.putBody(message: "m", content: Data("x".utf8), sha: nil), let o = try? JSONSerialization.jsonObject(with: b) as? [String: Any] {
    check("corps de requête sans sha (premier envoi)", o["sha"] == nil)
}

// Chemin des remarques envoyées
let fbDate = Date(timeIntervalSince1970: 1_794_000_000) // 2026-11-06 ~ heure de Paris
let fbP = Backup.feedbackPath(fbDate)
check("feedback : chemin feedback/AAAA-MM-JJ-HHMMSS.md", fbP.range(of: "^feedback/[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{6}\\.md$", options: .regularExpression) != nil)
check("feedback : deux dates différentes, deux fichiers", Backup.feedbackPath(fbDate) != Backup.feedbackPath(fbDate.addingTimeInterval(1)))

// Fichier de réglages
let cfgTxt = "\u{FEFF}# commentaire\nmise_a_jour = ClementLGS/memo-maman\nSauvegarde_Depot = \"Clem/notes-sauv\"\nsauvegarde_jeton = github_pat_ABC=def\ninconnu = x\n"
let cfgV = Config.parse(cfgTxt)
check("réglages : valeurs lues (BOM, guillemets, casse, = dans le jeton)", cfgV == Config.Values(update: "ClementLGS/memo-maman", backupRepo: "Clem/notes-sauv", token: "github_pat_ABC=def"))
check("réglages : exemples du modèle ignorés", Config.parse("sauvegarde_depot = votre-compte/votre-depot\nsauvegarde_jeton = colle_ici_le_jeton\n") == Config.Values())
check("réglages : fichier valide accepté", Config.problem(cfgV) == nil)
check("réglages : fichier vide refusé", Config.problem(Config.Values()) != nil)
check("réglages : dépôt invalide refusé", Config.problem(Config.Values(update: "", backupRepo: "pas bon", token: "x")) != nil)
check("réglages : source de mise à jour invalide refusée", Config.problem(Config.Values(update: "a b", backupRepo: "", token: "")) != nil)
check("réglages : branche acceptée", Config.problem(Config.Values(update: "a/b@dev", backupRepo: "", token: "")) == nil)

// version.json du dépôt = index.html du dépôt (sinon l'appli refuserait la mise à jour : empreinte différente)
let argv = CommandLine.arguments
if argv.count >= 3, let vjText = try? String(contentsOfFile: argv[1], encoding: .utf8), let htmlData = try? Data(contentsOf: URL(fileURLWithPath: argv[2])),
   let o = try? JSONSerialization.jsonObject(with: Data(vjText.utf8)) as? [String: Any], let want = o["uisha"] as? String {
    if Hash.sha256Hex(htmlData) == want.lowercased() { print("OK      version.json correspond à index.html") }
    else { print("ECHEC   version.json ne correspond pas à index.html : lance python3 tools/version.py avant de pousser"); failed = true }
    if let html = String(data: htmlData, encoding: .utf8) { check("index.html passe le contrôle Ota", Ota.problem(html: html, versionJson: vjText) == nil) }
}
exit(failed ? 1 : 0)

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

// version.json du dépôt = index.html du dépôt (sinon l'appli refuserait la mise à jour : empreinte différente)
let argv = CommandLine.arguments
if argv.count >= 3, let vjText = try? String(contentsOfFile: argv[1], encoding: .utf8), let htmlData = try? Data(contentsOf: URL(fileURLWithPath: argv[2])),
   let o = try? JSONSerialization.jsonObject(with: Data(vjText.utf8)) as? [String: Any], let want = o["uisha"] as? String {
    if Hash.sha256Hex(htmlData) == want.lowercased() { print("OK      version.json correspond à index.html") }
    else { print("ECHEC   version.json ne correspond pas à index.html : lance python3 tools/version.py avant de pousser"); failed = true }
    if let html = String(data: htmlData, encoding: .utf8) { check("index.html passe le contrôle Ota", Ota.problem(html: html, versionJson: vjText) == nil) }
}
exit(failed ? 1 : 0)

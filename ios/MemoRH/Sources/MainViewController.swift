import UIKit
import WebKit

/// Écran unique : une WKWebView qui affiche l'interface (index.html) et sert les appels de la page.
final class MainViewController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var webView: WKWebView!
    private let ucc = WKUserContentController()
    /// La page ne peut contacter que GitHub (mises à jour) : rien d'autre ne sort de l'appli.
    private let allowedHosts: Set<String> = ["api.github.com", "raw.githubusercontent.com"]

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask { .portrait }
    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }
    /// Même fond que le tableau de bord (#0f1114).
    private static let bg = UIColor(red: 15.0 / 255, green: 17.0 / 255, blue: 20.0 / 255, alpha: 1)

    override func loadView() {
        let conf = WKWebViewConfiguration()
        ucc.add(WeakScriptHandler(self), name: "native")
        conf.userContentController = ucc
        let wv = WKWebView(frame: .zero, configuration: conf)
        wv.navigationDelegate = self
        wv.uiDelegate = self
        wv.isOpaque = false
        wv.backgroundColor = Self.bg
        wv.scrollView.backgroundColor = Self.bg
        wv.scrollView.contentInsetAdjustmentBehavior = .never
        wv.scrollView.minimumZoomScale = 1
        wv.scrollView.maximumZoomScale = 1
        wv.scrollView.pinchGestureRecognizer?.isEnabled = false
        webView = wv
        view = wv
        overrideUserInterfaceStyle = .dark
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadPage()
    }

    /// Charge l'interface : la version mise à jour (si elle existe et qu'elle est valide), sinon celle fournie avec l'appli.
    func loadPage() {
        guard let p = Ota.page() else {
            webView.loadHTMLString("<body style='font:20px sans-serif;padding:40px'>index.html introuvable dans l'appli.</body>", baseURL: nil)
            return
        }
        webView.loadFileURL(p.page, allowingReadAccessTo: p.readAccess)
    }

    // Appels synchrones : la page les envoie par prompt("__tdb", json).
    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (String?) -> Void) {
        if prompt == "__tdb", frame.isMainFrame, let t = defaultText {
            completionHandler(handleSync(t))
        } else {
            completionHandler(nil)
        }
    }

    private func handleSync(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let d = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let m = d["m"] as? String, let a = d["a"] as? [Any] else { return "err:appel invalide" }
        let first = (a.first as? String) ?? ""
        switch m {
        case "data.get": return Store.read()
        case "data.set": return Store.write(first)
        case "ota.begin": Ota.begin(); return "ok"
        case "ota.chunk": Ota.chunk(first); return "ok"
        case "ota.commit": return Ota.commit(versionJson: first)
        case "cfg.import": return Config.importFile()
        case "bk.status": return Backup.status()
        case "bk.set": return Backup.configure(repo: first, token: a.count > 1 ? ((a[1] as? String) ?? "") : "")
        case "bk.forget": return Backup.forget()
        default: return "err:appel inconnu"
        }
    }

    // Appels asynchrones : reloadUi (recharger la page) et httpGet (GitHub seulement).
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let d = message.body as? [String: Any], let m = d["m"] as? String, let a = d["a"] as? [Any] else { return }
        switch m {
        case "reloadUi":
            loadPage()
        case "backupRun":
            let manual = (a.first as? NSNumber)?.boolValue ?? false
            Backup.run(manual: manual) { [weak self] result in
                let js = "window.__bk(\(Self.literal(result)))"
                DispatchQueue.main.async { self?.webView.evaluateJavaScript(js, completionHandler: nil) }
            }
        case "httpGet":
            guard a.count >= 3, let id = (a[0] as? NSNumber)?.intValue else { return }
            httpGet(id: id, urlString: (a[1] as? String) ?? "", headers: (a[2] as? [String: Any]) ?? [:])
        default:
            break
        }
    }

    private func httpGet(id: Int, urlString: String, headers: [String: Any]) {
        guard let url = URL(string: urlString), url.scheme == "https", let host = url.host, allowedHosts.contains(host) else {
            deliver(id: id, status: 0, body: "", error: "adresse refusée")
            return
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        for (k, v) in headers { if let s = v as? String { req.setValue(s, forHTTPHeaderField: k) } }
        URLSession.shared.dataTask(with: req) { [weak self] data, resp, err in
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            self?.deliver(id: id, status: status, body: body, error: err?.localizedDescription ?? "")
        }.resume()
    }

    private func deliver(id: Int, status: Int, body: String, error: String) {
        let js = "window.__nat(\(id),\(status),\(Self.literal(body)),\(Self.literal(error)))"
        DispatchQueue.main.async { [weak self] in self?.webView.evaluateJavaScript(js, completionHandler: nil) }
    }

    /// Texte -> littéral JavaScript entre guillemets.
    static func literal(_ s: String) -> String {
        guard let d = try? JSONSerialization.data(withJSONObject: [s], options: []),
              let t = String(data: d, encoding: .utf8), t.count >= 2 else { return "\"\"" }
        return String(t.dropFirst().dropLast())
    }

    // iOS peut arrêter le processus de la page quand il manque de mémoire : on la recharge.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        loadPage()
    }
}

/// Évite que la WKUserContentController garde le contrôleur en vie (cycle de références).
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}

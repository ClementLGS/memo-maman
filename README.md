# Prise de notes Ciolek

Pense-bête pour iPhone : 7 catégories, des sous-thèmes, des notes à cocher. Les notes restent **sur le téléphone**
(fichier `memo-rh.json`, visible dans Fichiers > Sur mon iPhone > Prise de notes Ciolek). Ce dépôt ne contient que l'interface et le code de l'appli : **aucune note, aucun secret**.

- `index.html` : toute l'interface (HTML + CSS + JS).
- `version.json` : numéro et empreinte de l'interface (écrit par `python3 tools/version.py`).
- `ios/` : coque iOS (WKWebView) : stockage des notes, mises à jour de l'interface, tests.
- `.github/workflows/ios.yml` : compile l'IPA non signé sur GitHub Actions (onglet Actions > dernier passage > Artifacts).

## Publier une nouvelle version de l'interface
1. Modifier `index.html`.
2. Augmenter le numéro à **trois endroits identiques** : `<!--TDBV:… -->`, `parseInt("…")` de `UI_CODE`, et `UI_NAME`. Un numéro déjà utilisé ne se réutilise jamais.
3. `python3 tools/version.py`
4. Commit + push de `index.html` **et** `version.json` ensemble.
5. Vérifier : `git ls-remote origin main`.

L'appli la récupère seule (5 s après l'ouverture, puis toutes les 6 h, ou via Réglages > « Chercher une mise à jour »), l'installe, puis propose « Recharger ».
Un nouvel IPA n'est nécessaire que si le code Swift change (ou tous les 7 jours avec un compte Apple gratuit).

## Installer sur l'iPhone (depuis Windows)
1. Télécharger l'IPA (Actions > Artifacts), le dézipper.
2. **Sideloadly** + iTunes/iCloud (versions du site d'Apple) ; iPhone branché en USB, déverrouillé, « Faire confiance ».
3. Glisser l'IPA dans Sideloadly, saisir l'identifiant Apple, Start.
4. iPhone : Réglages > Confidentialité et sécurité > **Mode développeur** (activer, redémarrer), puis Réglages > Général > VPN et gestion de l'appareil > **Faire confiance** à l'identifiant.
5. Compte Apple gratuit : l'appli expire au bout de **7 jours** ; ré-installer avec Sideloadly, **avec le même identifiant Apple**, par-dessus l'appli existante (les notes sont conservées).

## Limites connues
- Rien n'a encore tourné sur un vrai iPhone : stockage, mise à jour automatique et clavier sont à vérifier au premier essai.
- Mises à jour non signées : `uisha` détecte un fichier abîmé, pas un fichier malveillant. Acceptable ici parce que l'appli ne contient aucune donnée sensible ; la page ne peut contacter que `api.github.com` et `raw.githubusercontent.com`.
- Pas de rappels/notifications, pas de synchronisation entre appareils : les notes vivent sur un seul téléphone (sauvegarde : copier/coller dans Réglages, ou fichier dans Fichiers).

## Fichier de réglages

`reglages.txt` (modèle à la racine du dépôt) : à remplir sur le PC et à déposer dans Fichiers > Sur mon iPhone > Prise de notes Ciolek. L'appli le lit à l'ouverture, remplit les réglages (source de mise à jour, dépôt et jeton de sauvegarde GitHub) puis le supprime.

#!/usr/bin/env python3
"""Écrit version.json à partir de index.html (numéro d'interface, nom, empreinte SHA-256).
À lancer à chaque nouvelle interface, avant de pousser : python3 tools/version.py
L'appli compare le numéro « ui » de version.json à celui de l'interface affichée ; s'il est différent,
elle télécharge index.html et l'enregistre. L'empreinte « uisha » sert à écarter un fichier abîmé (pas à prouver l'origine)."""
import hashlib, json, os, re, sys

racine = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
html = open(os.path.join(racine, "index.html"), "rb").read()
t = html.decode("utf-8")
ui = re.search(r'var UI_CODE = parseInt\("(\d+)"', t)
nom = re.search(r'UI_NAME = "([^"]+)"', t)
tdbv = re.search(r"TDBV:(\d+)", t)
if not (ui and nom and tdbv):
    sys.exit("index.html : UI_CODE, UI_NAME ou TDBV introuvable")
if ui.group(1) != tdbv.group(1):
    sys.exit("index.html : UI_CODE (%s) et TDBV (%s) diffèrent" % (ui.group(1), tdbv.group(1)))
v = {"ui": int(ui.group(1)), "name": nom.group(1), "uisha": hashlib.sha256(html).hexdigest()}
open(os.path.join(racine, "version.json"), "w", encoding="utf-8", newline="").write(json.dumps(v, ensure_ascii=False, separators=(",", ":")))
print("version.json :", json.dumps(v, ensure_ascii=False))

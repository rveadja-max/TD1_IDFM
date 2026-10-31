"""Normalisation technique des fichiers de validations, sans transformation métier.

Les archives IDFM changent de format d'un fichier à l'autre (constaté sur le snapshot
2026-10-31) : TXT tabulé en cp1252, UTF-8 ou UTF-16 ; XLSX en 2025 ; en-tête `JOUR`,
`Date` ; colonne `ID_ZDC`, `ID_ZdC` ou `lda` ; ordre des colonnes variable.

Cette étape ne fait que rendre ces fichiers lisibles par BigQuery : décodage, repérage
des colonnes par leur nom, ajout de la provenance. Toutes les valeurs restent du texte,
telles qu'écrites dans la source. Le typage, le nettoyage et l'harmonisation se font
ensuite en SQL (sql/silver/), où ils sont tracés et contrôlés.
"""

from __future__ import annotations

import io
import re
import warnings
import zipfile

import pandas as pd

# Colonnes de sortie, dans l'ordre du schéma de chargement.
COLONNES = ["JOUR", "CODE_STIF_TRNS", "CODE_STIF_RES", "CODE_STIF_ARRET",
            "LIBELLE_ARRET", "ID_ZDC", "CATEGORIE_TITRE", "NB_VALD"]
COLONNES_PROVENANCE = ["FICHIER_SOURCE", "LIGNE_SOURCE", "ENCODAGE_SOURCE", "NOM_COLONNE_ZDC"]

# Variantes d'en-têtes observées -> nom normalisé.
# `lda` (2023 S1) porte les mêmes valeurs que ID_ZDC pour une même station
# (ex. PORTE MAILLOT : 71379) ; l'équivalence est vérifiée par requête en Silver.
ALIAS = {"JOUR": "JOUR", "DATE": "JOUR", "ID_ZDC": "ID_ZDC", "LDA": "ID_ZDC"}


class ErreurFormat(ValueError):
    """Fichier de validations dont la structure ne correspond pas aux colonnes attendues."""


def decoder(octets: bytes) -> tuple[str, str]:
    """Détecte l'encodage : marque d'ordre UTF-16, puis UTF-8 strict, sinon cp1252."""
    if octets[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return octets.decode("utf-16"), "utf-16"
    try:
        return octets.decode("utf-8-sig"), "utf-8"
    except UnicodeDecodeError:
        return octets.decode("cp1252"), "cp1252"


def _normaliser_colonnes(df: pd.DataFrame) -> tuple[pd.DataFrame, str]:
    renommage, nom_zdc = {}, ""
    for c in df.columns:
        cle = str(c).strip().upper()
        cible = ALIAS.get(cle, cle)
        if cible == "ID_ZDC":
            nom_zdc = str(c).strip()
        renommage[c] = cible
    df = df.rename(columns=renommage)
    manquantes = [c for c in COLONNES if c not in df.columns]
    if manquantes:
        raise ErreurFormat(f"Colonnes absentes : {manquantes} (présentes : {list(df.columns)})")
    return df[COLONNES], nom_zdc


def lire_fichier(nom: str, octets: bytes) -> pd.DataFrame:
    """Lit un fichier NB_FER (TXT ou XLSX) ; renvoie du texte brut + provenance."""
    if nom.lower().endswith(".xlsx"):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore")  # avertissements de style openpyxl sans effet
            df = pd.read_excel(io.BytesIO(octets), sheet_name=0, dtype=str, keep_default_na=False)
        encodage = "xlsx"
    else:
        texte, encodage = decoder(octets)
        df = pd.read_csv(io.StringIO(texte), sep="\t", dtype=str, keep_default_na=False,
                         quoting=3)  # QUOTE_NONE : aucun guillemet interprété
    df, nom_zdc = _normaliser_colonnes(df)
    df = df.copy()
    df["FICHIER_SOURCE"] = nom
    df["LIGNE_SOURCE"] = range(2, len(df) + 2)  # n° de ligne dans le fichier (en-tête = 1)
    df["ENCODAGE_SOURCE"] = encodage
    df["NOM_COLONNE_ZDC"] = nom_zdc
    return df


def fichiers_nb_fer(archive: bytes) -> list[str]:
    """Membres NB_FER d'une archive annuelle (les PROFIL_FER sont hors périmètre)."""
    with zipfile.ZipFile(io.BytesIO(archive)) as zf:
        return sorted(n for n in zf.namelist()
                      if re.search(r"_NB_FER\s*\.(txt|xlsx)$", n, re.IGNORECASE))


def normaliser_archive(archive: bytes):
    """Produit (nom_membre, DataFrame normalisé) pour chaque fichier NB_FER de l'archive."""
    with zipfile.ZipFile(io.BytesIO(archive)) as zf:
        for nom in fichiers_nb_fer(archive):
            yield nom, lire_fichier(nom, zf.read(nom))

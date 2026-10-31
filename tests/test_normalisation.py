"""Tests de la normalisation technique des fichiers de validations."""

import io
import zipfile

import pandas as pd
import pytest

from src.silver.normalisation import ErreurFormat, decoder, fichiers_nb_fer, lire_fichier

ENTETE = "JOUR\tCODE_STIF_TRNS\tCODE_STIF_RES\tCODE_STIF_ARRET\tLIBELLE_ARRET\tID_ZDC\tCATEGORIE_TITRE\tNB_VALD"


def test_decodage_utf16_utf8_cp1252():
    assert decoder("é".encode("utf-16")) == ("é", "utf-16")
    assert decoder("é".encode("utf-8")) == ("é", "utf-8")
    assert decoder("é".encode("cp1252")) == ("é", "cp1252")


def test_codes_conserves_en_texte_et_provenance():
    texte = ENTETE + "\n01/01/2024\t100\t010\t0001\tPORTE MAILLOT \t71379.0\tAmethyste\t1 020\n"
    df = lire_fichier("2024_T4_NB_FER.txt", texte.encode("utf-8"))
    ligne = df.iloc[0]
    # Aucune conversion : zéros initiaux, espaces et décimales restent visibles pour le SQL.
    assert ligne["CODE_STIF_RES"] == "010" and ligne["CODE_STIF_ARRET"] == "0001"
    assert ligne["ID_ZDC"] == "71379.0" and ligne["NB_VALD"] == "1 020"
    assert ligne["LIBELLE_ARRET"] == "PORTE MAILLOT "
    assert ligne["FICHIER_SOURCE"] == "2024_T4_NB_FER.txt" and ligne["LIGNE_SOURCE"] == 2


def test_colonnes_reperees_par_nom_et_alias():
    # Ordre permuté (2025 T3/T4), en-tête « Date » (2025 T2), colonne « lda » (2023 S1).
    texte = ("Date\tCODE_STIF_TRNS\tCODE_STIF_RES\tCODE_STIF_ARRET\tlda\tLIBELLE_ARRET"
             "\tCATEGORIE_TITRE\tNB_VALD\n01/04/2025\t100\t110\t1\t71379\tPORTE MAILLOT\tNAVIGO\t5\n")
    df = lire_fichier("x_NB_FER.txt", texte.encode("cp1252"))
    assert list(df.columns[:8]) == ["JOUR", "CODE_STIF_TRNS", "CODE_STIF_RES", "CODE_STIF_ARRET",
                                     "LIBELLE_ARRET", "ID_ZDC", "CATEGORIE_TITRE", "NB_VALD"]
    assert df.iloc[0]["JOUR"] == "01/04/2025" and df.iloc[0]["ID_ZDC"] == "71379"
    assert df.iloc[0]["NOM_COLONNE_ZDC"] == "lda"


def test_xlsx():
    tampon = io.BytesIO()
    pd.DataFrame({"JOUR": ["01/07/2025"], "CODE_STIF_TRNS": ["100"], "CODE_STIF_RES": ["110"],
                  "CODE_STIF_ARRET": ["1"], "ID_ZdC": ["71379"], "LIBELLE_ARRET": ["PORTE MAILLOT"],
                  "CATEGORIE_TITRE": ["Imagine R"], "NB_VALD": ["12"]}).to_excel(tampon, index=False)
    df = lire_fichier("2025_T3_NB_FER.xlsx", tampon.getvalue())
    assert df.iloc[0]["ID_ZDC"] == "71379" and df.iloc[0]["ENCODAGE_SOURCE"] == "xlsx"


def test_colonne_manquante_refusee():
    with pytest.raises(ErreurFormat, match="NB_VALD"):
        lire_fichier("x.txt", b"JOUR\tCODE_STIF_TRNS\n01/01/2024\t100\n")


def test_selection_des_fichiers_nb_fer():
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w") as zf:
        for n in ("d/2023_S1_NB_FER .txt", "d/2023_S1_PROFIL_FER.txt", "d/T1/2025_T1_NB_FER.xlsx"):
            zf.writestr(n, "x")
    assert fichiers_nb_fer(tampon.getvalue()) == ["d/2023_S1_NB_FER .txt", "d/T1/2025_T1_NB_FER.xlsx"]

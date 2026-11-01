"""Contrôles qualité : exécution des requêtes versionnées de sql/checks/ et empreintes.

Chaque requête de contrôle renvoie, pour chaque contrôle : identifiant, intitulé,
mesure obtenue, valeur attendue, statut et interprétation. Aucun statut n'est affiché
sans la mesure qui le justifie.
"""

from __future__ import annotations

import pandas as pd

from src import bq as B
from src.config import Config

FICHIERS_CONTROLES = ["checks/silver_validations.sql", "checks/silver_referentiels.sql", "checks/gold.sql"]

# Tables dont on compare le contenu entre deux exécutions.
TABLES_EMPREINTE = {
    "silver": ["validations_chargement", "validations", "validations_rejets", "ref_categorie_titre",
               "zones_correspondance", "jours_feries", "meteo_quotidienne", "stations_meteo"],
    "gold": ["dim_date", "dim_zone", "meteo_station_jour", "meteo_jour_idf", "fait_validations_jour",
             "ds_zone_jour", "regles_mesures"],
}


def executer_controles(config: Config, fichiers: list[str] | None = None) -> pd.DataFrame:
    bq = B.client(config)
    resultats = [B.requete_fichier(bq, f, config).assign(fichier=f) for f in (fichiers or FICHIERS_CONTROLES)]
    return pd.concat(resultats, ignore_index=True)


def empreintes(config: Config) -> pd.DataFrame:
    """Nombre de lignes et empreinte de contenu indépendante de l'ordre des lignes.

    L'empreinte est le XOR des FARM_FINGERPRINT de chaque ligne sérialisée en JSON :
    deux tables de même contenu ont la même empreinte, quel que soit l'ordre physique.
    Les colonnes GEOGRAPHY sont sérialisées en texte (ST_ASTEXT).
    """
    bq = B.client(config)
    morceaux = []
    for couche, tables in TABLES_EMPREINTE.items():
        dataset = config.dataset_silver if couche == "silver" else config.dataset_gold
        for t in tables:
            sql = f"""
              SELECT '{couche}' AS couche, '{t}' AS table_bq, COUNT(*) AS lignes,
                     BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS empreinte
              FROM (SELECT * REPLACE (ST_ASTEXT(point) AS point) FROM `{config.projet}.{dataset}.{t}`) AS t
            """ if t in ("zones_correspondance", "stations_meteo") else f"""
              SELECT '{couche}' AS couche, '{t}' AS table_bq, COUNT(*) AS lignes,
                     BIT_XOR(FARM_FINGERPRINT(TO_JSON_STRING(t))) AS empreinte
              FROM `{config.projet}.{dataset}.{t}` AS t
            """
            morceaux.append(B.requete(bq, sql))
    return pd.concat(morceaux, ignore_index=True)


def comparer_empreintes(avant: pd.DataFrame, apres: pd.DataFrame) -> pd.DataFrame:
    m = avant.merge(apres, on=["couche", "table_bq"], suffixes=("_exec1", "_exec2"))
    m["lignes_identiques"] = m["lignes_exec1"] == m["lignes_exec2"]
    # Table vide : empreinte NULL des deux côtés, contenu identique par définition.
    vides = m["empreinte_exec1"].isna() & m["empreinte_exec2"].isna() & (m["lignes_exec1"] == 0) & (m["lignes_exec2"] == 0)
    m["contenu_identique"] = vides | (m["empreinte_exec1"] == m["empreinte_exec2"]).fillna(False).astype(bool)
    return m

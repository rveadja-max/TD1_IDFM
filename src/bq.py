"""Outils BigQuery communs : client, exécution des scripts SQL versionnés, requêtes."""

from __future__ import annotations

from pathlib import Path

import pandas as pd
from google.cloud import bigquery

from src.config import RACINE_PROJET, Config

DOSSIER_SQL = RACINE_PROJET / "sql"
# Plafond de sécurité par requête (10 Go facturés) : une erreur de jointure ne coûte rien.
OCTETS_FACTURES_MAX = 10 * 1024**3


def client(config: Config) -> bigquery.Client:
    return bigquery.Client(project=config.projet, location=config.localisation)


def parametres_sql(config: Config) -> dict[str, str]:
    """Valeurs substituées dans les scripts SQL ({projet}, {silver}, …)."""
    return {
        "projet": config.projet, "silver": config.dataset_silver, "gold": config.dataset_gold,
        "bucket": config.bucket, "snapshot": config.snapshot,
        "annee_debut": str(config.annee_debut), "annee_fin": str(config.annee_fin),
    }


def lire_sql(chemin: str | Path, config: Config) -> str:
    texte = (DOSSIER_SQL / chemin).read_text(encoding="utf-8")
    for cle, valeur in parametres_sql(config).items():
        texte = texte.replace("{" + cle + "}", valeur)
    return texte


def executer_script(bq: bigquery.Client, chemin: str | Path, config: Config) -> bigquery.QueryJob:
    """Exécute un fichier SQL (script multi-instructions accepté) et attend la fin."""
    job = bq.query(lire_sql(chemin, config),
                   job_config=bigquery.QueryJobConfig(maximum_bytes_billed=OCTETS_FACTURES_MAX))
    job.result()
    return job


def requete(bq: bigquery.Client, sql: str) -> pd.DataFrame:
    job = bq.query(sql, job_config=bigquery.QueryJobConfig(maximum_bytes_billed=OCTETS_FACTURES_MAX))
    return job.to_dataframe()


def requete_fichier(bq: bigquery.Client, chemin: str | Path, config: Config) -> pd.DataFrame:
    return requete(bq, lire_sql(chemin, config))

"""Enchaînement du pipeline, appelé par le notebook (aucune orchestration automatique).

Ordre : Bronze (GCS) -> chargement Silver -> SQL Silver -> SQL Gold -> contrôles.
Chaque étape est rejouable : Bronze réutilise les snapshots, les tables sont remplacées.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field

import pandas as pd
from google.cloud import storage

from src import bq as B
from src.bronze.collecte import collecter_bronze
from src.config import Config
from src.silver.chargement import charger_tout

SQL_SILVER = ["silver/01_ref_categorie_titre.sql", "silver/02_zones.sql", "silver/03_validations.sql",
              "silver/04_jours_feries.sql", "silver/05_meteo.sql"]
SQL_GOLD = ["gold/01_dimensions.sql", "gold/02_faits.sql", "gold/03_kpi_et_semantique.sql"]


@dataclass
class Execution:
    bronze: pd.DataFrame | None = None
    chargement: dict[str, pd.DataFrame] = field(default_factory=dict)
    scripts: list[dict] = field(default_factory=list)


def executer_scripts(config: Config, fichiers: list[str]) -> list[dict]:
    bq = B.client(config)
    journal = []
    for f in fichiers:
        debut = time.time()
        job = B.executer_script(bq, f, config)
        journal.append({"script": f, "octets_traites": job.total_bytes_processed,
                        "duree_s": round(time.time() - debut, 1)})
    return journal


def executer(config: Config, bronze: bool = True, silver: bool = True, gold: bool = True) -> Execution:
    ex = Execution()
    if bronze:
        ex.bronze = collecter_bronze(config)
    if silver:
        ex.chargement = charger_tout(config, B.client(config), storage.Client(project=config.projet))
        ex.scripts += executer_scripts(config, SQL_SILVER)
    if gold:
        ex.scripts += executer_scripts(config, SQL_GOLD)
    return ex

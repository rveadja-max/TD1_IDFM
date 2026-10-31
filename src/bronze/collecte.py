"""Collecte Bronze de bout en bout : résout les cibles puis dépose chaque objet une fois."""

from __future__ import annotations

from dataclasses import asdict

import pandas as pd
from google.cloud import storage

from src.bronze.storage import chemin_bronze, deposer
from src.collect.sources import Cible, toutes_les_cibles
from src.config import Config


def collecter_bronze(config: Config, cibles: list[Cible] | None = None,
                     verifier_existant: bool = True) -> pd.DataFrame:
    """Renvoie un tableau de provenance : une ligne par objet Bronze."""
    bucket = storage.Client(project=config.projet).bucket(config.bucket)
    cibles = cibles if cibles is not None else toutes_les_cibles(config.annees)
    lignes = []
    for c in cibles:
        chemin = chemin_bronze(c.source, config.snapshot, c.partition, c.nom_fichier)
        entree = deposer(bucket, c.source, config.snapshot, chemin, c.telecharger, c.valider,
                         verifier_existant=verifier_existant)
        lignes.append(asdict(entree))
    return pd.DataFrame(lignes)

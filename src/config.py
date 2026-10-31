"""Configuration du pipeline : lecture des variables d'environnement et du fichier .env.

Aucune valeur propre à un projet GCP n'est écrite dans le code : tout vient de
l'environnement ou du fichier .env (ignoré par Git). Les variables déjà définies
dans l'environnement sont prioritaires sur le fichier .env.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from dotenv import load_dotenv

RACINE_PROJET = Path(__file__).resolve().parents[1]
FICHIER_ENV = RACINE_PROJET / ".env"

# Le sujet impose au moins trois années civiles complètes.
NB_ANNEES_MIN = 3


class ConfigError(ValueError):
    """Configuration absente ou invalide."""


@dataclass(frozen=True)
class Config:
    projet: str
    localisation: str
    bucket: str
    dataset_silver: str
    dataset_gold: str
    annee_debut: int
    annee_fin: int
    snapshot: str  # date du snapshot Bronze, format AAAA-MM-JJ

    @property
    def annees(self) -> list[int]:
        return list(range(self.annee_debut, self.annee_fin + 1))


def _obligatoire(nom: str) -> str:
    valeur = os.environ.get(nom, "").strip()
    if not valeur:
        raise ConfigError(f"Variable {nom} absente : la renseigner dans .env (voir .env.example).")
    return valeur


def _entier(nom: str) -> int:
    valeur = _obligatoire(nom)
    try:
        return int(valeur)
    except ValueError:
        raise ConfigError(f"{nom} doit être un entier, reçu : {valeur!r}") from None


def charger_config(fichier_env: Path | None = FICHIER_ENV) -> Config:
    """Lit .env (s'il existe) puis l'environnement, et valide les paramètres."""
    if fichier_env is not None and fichier_env.exists():
        load_dotenv(dotenv_path=fichier_env, override=False)

    annee_debut = _entier("START_YEAR")
    annee_fin = _entier("END_YEAR")
    if annee_fin - annee_debut + 1 < NB_ANNEES_MIN:
        raise ConfigError(
            f"Période {annee_debut}-{annee_fin} trop courte : "
            f"au moins {NB_ANNEES_MIN} années civiles complètes sont exigées."
        )

    snapshot = _obligatoire("SNAPSHOT_DATE")
    try:
        date.fromisoformat(snapshot)
    except ValueError:
        raise ConfigError(f"SNAPSHOT_DATE doit être au format AAAA-MM-JJ, reçu : {snapshot!r}") from None

    return Config(
        projet=_obligatoire("GCP_PROJECT_ID"),
        localisation=_obligatoire("GCP_LOCATION"),
        bucket=_obligatoire("GCS_BUCKET"),
        dataset_silver=_obligatoire("BQ_DATASET_SILVER"),
        dataset_gold=_obligatoire("BQ_DATASET_GOLD"),
        annee_debut=annee_debut,
        annee_fin=annee_fin,
        snapshot=snapshot,
    )

"""Tests de src/config.py : lecture et validation des paramètres."""

import pytest

from src.config import ConfigError, charger_config

VARIABLES_VALIDES = {
    "GCP_PROJECT_ID": "projet-test",
    "GCP_LOCATION": "EU",
    "GCS_BUCKET": "bucket-test",
    "BQ_DATASET_SILVER": "silver_idfm",
    "BQ_DATASET_GOLD": "gold_idfm",
    "START_YEAR": "2023",
    "END_YEAR": "2025",
    "SNAPSHOT_DATE": "2026-10-31",
}


@pytest.fixture
def env_vide(monkeypatch):
    """Retire les variables du pipeline pour isoler chaque test."""
    for nom in VARIABLES_VALIDES:
        monkeypatch.delenv(nom, raising=False)
    return monkeypatch


def test_config_lue_depuis_fichier_env(env_vide, tmp_path):
    fichier = tmp_path / ".env"
    fichier.write_text("\n".join(f"{k}={v}" for k, v in VARIABLES_VALIDES.items()))

    config = charger_config(fichier)

    assert config.projet == "projet-test"
    assert config.annees == [2023, 2024, 2025]
    assert config.snapshot == "2026-10-31"


def test_environnement_prioritaire_sur_fichier(env_vide, tmp_path):
    fichier = tmp_path / ".env"
    fichier.write_text("\n".join(f"{k}={v}" for k, v in VARIABLES_VALIDES.items()))
    env_vide.setenv("GCP_PROJECT_ID", "projet-environnement")

    assert charger_config(fichier).projet == "projet-environnement"


def test_variable_absente(env_vide):
    for k, v in VARIABLES_VALIDES.items():
        if k != "GCS_BUCKET":
            env_vide.setenv(k, v)

    with pytest.raises(ConfigError, match="GCS_BUCKET"):
        charger_config(None)


@pytest.mark.parametrize(
    ("nom", "valeur", "message"),
    [
        ("END_YEAR", "2024", "trop courte"),
        ("START_YEAR", "deux-mille", "entier"),
        ("SNAPSHOT_DATE", "31/10/2026", "AAAA-MM-JJ"),
    ],
)
def test_valeurs_invalides(env_vide, nom, valeur, message):
    for k, v in VARIABLES_VALIDES.items():
        env_vide.setenv(k, v)
    env_vide.setenv(nom, valeur)

    with pytest.raises(ConfigError, match=message):
        charger_config(None)

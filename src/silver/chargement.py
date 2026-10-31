"""Couche Silver, étape 1 : tables de chargement BigQuery, une par source.

Les tables de chargement reproduisent la source avec un schéma explicite et en mode
remplacement (WRITE_TRUNCATE) : une relance remplace leur contenu, sans jamais ajouter
de lignes. Elles sont toutes alimentées à partir des objets Bronze du snapshot
configuré, jamais directement depuis Internet.
"""

from __future__ import annotations

import gzip
import io
import json
import re

import pandas as pd
import pyarrow.parquet as pq
from google.cloud import bigquery, storage
from pyproj import Transformer

from src.bronze.storage import lister_snapshot
from src.config import Config
from src.silver.normalisation import COLONNES, COLONNES_PROVENANCE, normaliser_archive

PREFIXE_STAGING = "silver_staging"
ENTIER = {"LIGNE_SOURCE"}


def _schema_texte(colonnes: list[str], descriptions: dict[str, str] | None = None) -> list:
    descriptions = descriptions or {}
    return [bigquery.SchemaField(c, "INT64" if c in ENTIER else "STRING", mode="NULLABLE",
                                 description=descriptions.get(c, "Valeur brute de la source, en texte"))
            for c in colonnes]


SCHEMA_VALIDATIONS = _schema_texte(COLONNES + COLONNES_PROVENANCE, {
    "FICHIER_SOURCE": "Fichier de l'archive Bronze dont provient la ligne",
    "LIGNE_SOURCE": "Numéro de ligne dans ce fichier (en-tête = 1)",
    "ENCODAGE_SOURCE": "Encodage détecté du fichier (utf-8, cp1252, utf-16, xlsx)",
    "NOM_COLONNE_ZDC": "Nom d'origine de la colonne lue comme ID_ZDC (ID_ZDC, ID_ZdC, lda)",
})

SCHEMA_FERIES = [
    bigquery.SchemaField("date", "STRING", description="Date du jour férié, AAAA-MM-JJ, telle que publiée"),
    bigquery.SchemaField("nom", "STRING", description="Nom du jour férié"),
    bigquery.SchemaField("annee_demandee", "INT64", description="Année passée à l'API"),
    bigquery.SchemaField("chemin_bronze", "STRING", description="Objet Bronze d'origine"),
]

SCHEMA_ZONES_WGS84 = [
    bigquery.SchemaField("zdcid", "STRING", description="Identifiant de la zone (texte)"),
    bigquery.SchemaField("x_lambert93", "INT64", description="X Lambert 93 (EPSG:2154), m"),
    bigquery.SchemaField("y_lambert93", "INT64", description="Y Lambert 93 (EPSG:2154), m"),
    bigquery.SchemaField("longitude", "FLOAT64", description="Longitude WGS84 (EPSG:4326) calculée par pyproj"),
    bigquery.SchemaField("latitude", "FLOAT64", description="Latitude WGS84 (EPSG:4326) calculée par pyproj"),
]


def _table(config: Config, nom: str) -> str:
    return f"{config.projet}.{config.dataset_silver}.{nom}"


def _remplacer(schema: list | None, **options) -> bigquery.LoadJobConfig:
    return bigquery.LoadJobConfig(schema=schema, write_disposition="WRITE_TRUNCATE", **options)


def _objets(gcs: storage.Client, config: Config, source: str):
    bucket = gcs.bucket(config.bucket)
    entrees = sorted(lister_snapshot(bucket, source, config.snapshot), key=lambda e: e.chemin_gcs)
    if not entrees:
        raise RuntimeError(f"Aucun objet Bronze « {source} » pour le snapshot {config.snapshot}")
    return bucket, entrees


def charger_validations(config: Config, bq: bigquery.Client, gcs: storage.Client) -> pd.DataFrame:
    """Normalise chaque fichier NB_FER, le dépose en CSV UTF-8 puis charge le tout."""
    bucket, entrees = _objets(gcs, config, "validations")
    uris, bilan = [], []
    for e in entrees:
        archive = bucket.blob(e.chemin_gcs).download_as_bytes()
        for membre, df in normaliser_archive(archive):
            nom = re.sub(r"[^A-Za-z0-9_.-]", "_", membre.rsplit("/", 1)[-1].replace(" .", "."))
            chemin = f"{PREFIXE_STAGING}/validations/snapshot={config.snapshot}/{nom}.csv.gz"
            # Données dérivées et déterministes : le remplacement est volontaire ici.
            bucket.blob(chemin).upload_from_string(
                gzip.compress(df.to_csv(index=False).encode("utf-8"), mtime=0),
                content_type="application/gzip")
            uris.append(f"gs://{config.bucket}/{chemin}")
            bilan.append({"archive_bronze": e.chemin_gcs, "fichier": membre, "lignes": len(df),
                          "encodage": df["ENCODAGE_SOURCE"].iat[0],
                          "colonne_zdc": df["NOM_COLONNE_ZDC"].iat[0]})
    job = bq.load_table_from_uri(uris, _table(config, "validations_chargement"), job_config=_remplacer(
        SCHEMA_VALIDATIONS, source_format="CSV", skip_leading_rows=1, allow_quoted_newlines=False))
    job.result()
    out = pd.DataFrame(bilan)
    out.attrs["lignes_chargees"] = job.output_rows
    return out


def charger_zones(config: Config, bq: bigquery.Client, gcs: storage.Client) -> pd.DataFrame:
    """Parquet Bronze chargé tel quel (schéma embarqué) + coordonnées WGS84 calculées."""
    bucket, entrees = _objets(gcs, config, "zones")
    e = entrees[0]
    bq.load_table_from_uri(f"gs://{config.bucket}/{e.chemin_gcs}", _table(config, "zones_chargement"),
                           job_config=_remplacer(None, source_format="PARQUET")).result()

    df = pq.read_table(io.BytesIO(bucket.blob(e.chemin_gcs).download_as_bytes())).to_pandas()
    # Lambert 93 -> WGS84 ; always_xy : ordre (x, y) en entrée, (lon, lat) en sortie.
    lon, lat = Transformer.from_crs("EPSG:2154", "EPSG:4326", always_xy=True).transform(
        df["zdcxepsg2154"].astype(float).to_numpy(), df["zdcyepsg2154"].astype(float).to_numpy())
    geo = pd.DataFrame({"zdcid": df["zdcid"].astype(str), "x_lambert93": df["zdcxepsg2154"].astype("Int64"),
                        "y_lambert93": df["zdcyepsg2154"].astype("Int64"), "longitude": lon, "latitude": lat})
    bq.load_table_from_dataframe(geo, _table(config, "zones_wgs84_chargement"),
                                 job_config=_remplacer(SCHEMA_ZONES_WGS84)).result()
    return pd.DataFrame([{"objet_bronze": e.chemin_gcs, "lignes_parquet": len(df)}])


def charger_feries(config: Config, bq: bigquery.Client, gcs: storage.Client) -> pd.DataFrame:
    bucket, entrees = _objets(gcs, config, "jours_feries")
    lignes = []
    for e in entrees:
        annee = int(re.search(r"annee=(\d{4})", e.chemin_gcs).group(1))
        for date, nom in json.loads(bucket.blob(e.chemin_gcs).download_as_bytes()).items():
            lignes.append({"date": date, "nom": nom, "annee_demandee": annee, "chemin_bronze": e.chemin_gcs})
    ndjson = "\n".join(json.dumps(l, ensure_ascii=False) for l in lignes).encode("utf-8")
    bq.load_table_from_file(io.BytesIO(ndjson), _table(config, "jours_feries_chargement"),
                            job_config=_remplacer(SCHEMA_FERIES, source_format="NEWLINE_DELIMITED_JSON")).result()
    return pd.DataFrame(lignes).groupby("annee_demandee").size().rename("jours_feries").reset_index()


def charger_tout(config: Config, bq: bigquery.Client, gcs: storage.Client) -> dict[str, pd.DataFrame]:
    """La météo est chargée en SQL (table externe sur Bronze), voir sql/silver/meteo.sql."""
    return {"validations": charger_validations(config, bq, gcs),
            "zones": charger_zones(config, bq, gcs),
            "jours_feries": charger_feries(config, bq, gcs)}

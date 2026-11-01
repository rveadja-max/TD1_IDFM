# Architecture du pipeline

Pipeline médaillon Bronze (Cloud Storage) → Silver (BigQuery) → Gold (BigQuery), exécuté
manuellement depuis `notebooks/TD1_ADJAKOSSA_AKODEKOU.ipynb` via `src/pipeline.py`.

```text
API IDFM, data.gouv.fr, calendrier.api.gouv.fr
        │  src/collect/ : résolution des URL par catalogue, HTTP avec reprises, validation du contenu
        ▼
GCS  bronze/<source>/snapshot=<SNAPSHOT_DATE>/<partition>/<fichier>   (+ <fichier>.manifest.json)
        │  src/silver/normalisation.py (validations) ; table externe (météo) ; Parquet (zones) ; NDJSON (fériés)
        ▼
BigQuery silver_idfm : *_chargement (texte, schéma explicite, WRITE_TRUNCATE)
        │  sql/silver/01…05 (CREATE OR REPLACE, schémas et descriptions explicites)
        ▼
BigQuery silver_idfm : validations, zones_correspondance, jours_feries, meteo_quotidienne, stations_meteo, ref_categorie_titre
        │  sql/gold/01…03
        ▼
BigQuery gold_idfm : dim_date, dim_zone, meteo_station_jour, meteo_jour_idf, fait_validations_jour, ds_zone_jour,
                     v_kpi_*, regles_mesures, v_catalogue_colonnes
        │  sql/checks/*.sql, src/quality/checks.py
        ▼
Contrôles chiffrés (mesure, attendu, statut, interprétation) et empreintes de rejouabilité
```

## Bronze

- Chemin : `bronze/<source>/snapshot=<date>/<partition>/<fichier>` ; partitions `annee=` (validations,
  jours fériés) et `departement=` (météo).
- Dépôt avec `if_generation_match=0` : un objet existant n'est jamais écrasé.
- Si l'objet existe, la source n'est pas recontactée ; le SHA-256 de l'objet est recalculé et comparé
  au manifeste (`ErreurBronze` en cas d'écart).
- Contenu validé avant dépôt : ZIP (CRC de chaque membre, présence de `NB_FER`), GZIP (décompression,
  en-tête), Parquet (colonnes), JSON (dates dans l'année).
- Une actualisation = une nouvelle `SNAPSHOT_DATE`.

## Silver

| Source | Chargement | Table finale |
|---|---|---|
| Validations | normalisation Python (décodage, alias de colonnes, provenance) → CSV UTF-8 `silver_staging/` → `validations_chargement` | `validations` (+ `validations_rejets`, `ref_categorie_titre`) |
| Zones | Parquet Bronze → `zones_chargement` ; conversion Lambert 93 → WGS84 (pyproj) → `zones_wgs84_chargement` | `zones_correspondance` |
| Jours fériés | JSON Bronze → NDJSON → `jours_feries_chargement` | `jours_feries` |
| Météo | table externe `meteo_externe` sur Bronze (`_FILE_NAME`) → `meteo_chargement` | `meteo_quotidienne`, `stations_meteo` |

`silver_staging/` contient des données dérivées et déterministes : leur remplacement est volontaire.

## Gold

Voir `docs/dictionnaire_donnees.md` et la partie 3 du rapport.

## Décisions principales

| Décision | Raison |
|---|---|
| Colonnes de validations repérées par nom, valeurs gardées en texte jusqu'au SQL | ordre, en-têtes et encodages varient d'un fichier à l'autre |
| Format de date choisi par motif, contrôlé contre la période du fichier | trois formats coexistent ; une lecture « jour en premier » inverse les dates ISO |
| Sentinelles (`ND`, 999999, -1) conservées et signalées | elles portent des validations réelles, non localisables |
| Zone hors référentiel remplacée seulement si la zone actuelle du même arrêt est unique | anciens identifiants de grandes gares jusqu'en 2025 T1 |
| Catégories harmonisées avec un niveau de correspondance | deux nomenclatures ; aucune équivalence inventée |
| Fait agrégé avant toute jointure, dimensions à clé unique contrôlée | aucune multiplication de lignes possible |
| Station éligible la plus proche (TM et RR ≥ 95 % des jours) | les coordonnées permettent un rattachement géographique justifié |
| Retards joints sur la date, moyennes glissantes sur les jours précédents | robustesse aux jours manquants, pas de fuite de la cible |

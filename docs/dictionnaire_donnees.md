# Dictionnaire de données

Les descriptions de chaque colonne sont déclarées dans les scripts SQL (`OPTIONS(description = …)`)
et consultables dans BigQuery : `SELECT * FROM gold_idfm.v_catalogue_colonnes`, ou
`INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` pour Silver. Ce document résume les tables ; les règles
d'usage des mesures sont dans `gold_idfm.regles_mesures`.

## Silver (`silver_idfm`)

| Table | Grain | Clé | Contenu |
|---|---|---|---|
| `validations` | ligne publiée : jour × transporteur × réseau × arrêt × catégorie | technique : `fichier_source, ligne_source` | validations typées, zone retenue et son origine, catégorie harmonisée, indicateurs de censure et d'arrêt non déterminé |
| `validations_rejets` | ligne écartée | `fichier_source, ligne_source` | motif de rejet (vide sur le snapshot 2026-10-31) |
| `ref_categorie_titre` | catégorie source | `categorie_source` | catégorie harmonisée, niveau de correspondance, justification |
| `zones_correspondance` | zone | `zdc_id` | nom, type, commune, INSEE (texte), Lambert 93, WGS84, point géographique |
| `jours_feries` | date fériée | `date_ferie` | nom, année |
| `meteo_quotidienne` | station × jour (2023–2025) | `num_poste, jour` | RR, TN, TX, TM bruts, codes qualité, valeurs retenues (0/1/9) |
| `stations_meteo` | station | `num_poste` | position, nombre de jours avec TM et RR retenus |

## Gold (`gold_idfm`)

| Table / vue | Public | Grain | Clé | Mesures |
|---|---|---|---|---|
| `dim_date` | tous | jour | `jour` | type de jour, férié, pont, semaine ISO |
| `dim_zone` | tous | zone | `zdc_id` | station de référence, distance (km), présence dans les validations |
| `meteo_station_jour` | DS | station éligible × jour | `num_poste, jour` | `rr_mm`, `tn_c`, `tx_c`, `tm_c`, `jour_pluvieux` |
| `meteo_jour_idf` | DA, DS | jour | `jour` | moyennes régionales des stations éligibles |
| `fait_validations_jour` | socle | jour × zone × catégorie | `jour, zdc_id, categorie_titre` | `nb_vald` (additif), `nb_lignes_source`, `nb_arrets` (non additif), `nb_vald_plancher_5` |
| `ds_zone_jour` | DS | zone × jour (grille complète) | `zdc_id, jour` | `nb_vald`, `nb_vald_j1`, `_j7`, `_j364`, `moy_glissante_7j`, `_28j`, `tm_c`, `rr_mm`, `source_meteo` |
| `v_kpi_reseau_jour` | DA | jour | `jour` | total réseau, Imagine R, météo IDF |
| `v_kpi_type_jour` | DA | année × type de jour | — | moyenne par jour, indice base 100 = jour ouvré |
| `v_kpi_mensuel_categorie` | DA | mois × catégorie | — | total, moyenne par jour, part |
| `v_kpi_zone_annee` | DA | année × zone | — | total, rang, évolution annuelle |
| `regles_mesures` | agent IA | règle | — | définitions, agrégations, limites |
| `v_catalogue_colonnes` | agent IA | colonne | — | description de chaque colonne Gold |

## Définitions métier

- **Validation** : passage d'un titre en entrée de station ; une personne peut valider plusieurs fois,
  ce n'est donc pas un nombre de voyageurs.
- **Jour d'exploitation** : 04 h 00 à 03 h 59 le lendemain.
- **RR** : cumul de précipitations de J 06 h UTC à J+1 06 h UTC.
- **Codes transporteur et réseau** : texte, à lire ensemble ; ils ne désignent pas une ligne commerciale.

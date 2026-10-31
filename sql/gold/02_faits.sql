-- Gold : table de faits commune et table de variables Data Scientist.

-- fait_validations_jour : grain jour × zone × catégorie harmonisée.
-- Agrégation additive (SUM) des validations Silver ; aucune jointure ne précède
-- l'agrégation, donc aucune multiplication possible. Les dimensions se joignent ensuite
-- sur des clés dont l'unicité est contrôlée (sql/checks/gold.sql).
CREATE OR REPLACE TABLE `{projet}.{gold}.fait_validations_jour` (
  jour DATE NOT NULL OPTIONS(description = "Clé vers dim_date"),
  zdc_id STRING OPTIONS(description = "Clé vers dim_zone ; NULL si la source ne donne pas de zone"),
  categorie_titre STRING NOT NULL OPTIONS(description = "Catégorie harmonisée"),
  niveau_correspondance STRING NOT NULL OPTIONS(description = "Fiabilité de l'harmonisation (constante pour un jour donné)"),
  nb_vald INT64 NOT NULL OPTIONS(description = "Somme des validations d'entrée ; additive sur toutes les dimensions ; pas un nombre de voyageurs"),
  nb_lignes_source INT64 NOT NULL OPTIONS(description = "Lignes Silver agrégées"),
  nb_arrets INT64 NOT NULL OPTIONS(description = "Arrêts distincts (transporteur × réseau × arrêt) ; non additif"),
  nb_vald_plancher_5 INT64 NOT NULL OPTIONS(description = "Part de nb_vald issue de valeurs « 5 ou moins »"),
  zone_referencee BOOL NOT NULL OPTIONS(description = "zdc_id trouvé dans le référentiel actuel des zones")
)
PARTITION BY jour CLUSTER BY zdc_id, categorie_titre
OPTIONS(description = "Validations quotidiennes par zone de correspondance et catégorie de titre harmonisée")
AS
SELECT
  v.jour, v.id_zdc, v.categorie_titre, v.niveau_correspondance,
  SUM(v.nb_vald), COUNT(*),
  COUNT(DISTINCT CONCAT(v.code_stif_trns, '|', IFNULL(v.code_stif_res, ''), '|', v.code_stif_arret)),
  SUM(IF(v.nb_vald_plancher_5, v.nb_vald, 0)),
  LOGICAL_OR(z.zdc_id IS NOT NULL)
FROM `{projet}.{silver}.validations` AS v
LEFT JOIN (SELECT DISTINCT zdc_id FROM `{projet}.{gold}.dim_zone`) AS z ON z.zdc_id = v.id_zdc
GROUP BY v.jour, v.id_zdc, v.categorie_titre, v.niveau_correspondance;

-- ds_zone_jour : grain zone × jour, sur une grille complète zone × calendrier.
-- Variables retardées par jointure sur la date (et non par décalage de lignes), pour que
-- J-7 désigne bien la date d'il y a sept jours même en cas de jour manquant.
-- Moyennes glissantes sur les jours PRÉCÉDENTS uniquement (pas de fuite d'information).
CREATE OR REPLACE TABLE `{projet}.{gold}.ds_zone_jour`
PARTITION BY DATE_TRUNC(jour, MONTH) CLUSTER BY zdc_id
OPTIONS(description = "Variables Data Scientist : validations zone × jour, calendrier, météo de la station de référence, retards et moyennes glissantes")
AS
WITH zones AS (
  SELECT DISTINCT f.zdc_id FROM `{projet}.{gold}.fait_validations_jour` AS f WHERE f.zone_referencee
),
total AS (
  SELECT zdc_id, jour, SUM(nb_vald) AS nb_vald, SUM(IF(categorie_titre = 'Imagine R', nb_vald, 0)) AS nb_vald_imagine_r
  FROM `{projet}.{gold}.fait_validations_jour` WHERE zone_referencee GROUP BY zdc_id, jour
),
grille AS (
  SELECT z.zdc_id, d.*, t.nb_vald, t.nb_vald_imagine_r, t.nb_vald IS NOT NULL AS jour_observe
  FROM zones AS z CROSS JOIN `{projet}.{gold}.dim_date` AS d
  LEFT JOIN total AS t ON t.zdc_id = z.zdc_id AND t.jour = d.jour
)
SELECT
  g.zdc_id, g.jour, g.annee, g.mois, g.jour_semaine, g.est_weekend, g.est_ferie, g.type_jour, g.est_pont,
  g.jour_observe,
  g.nb_vald,
  g.nb_vald_imagine_r,
  l1.nb_vald AS nb_vald_j1, l7.nb_vald AS nb_vald_j7, l364.nb_vald AS nb_vald_j364,
  ROUND(AVG(g.nb_vald) OVER w7, 1) AS moy_glissante_7j,
  ROUND(AVG(g.nb_vald) OVER w28, 1) AS moy_glissante_28j,
  COUNT(g.nb_vald) OVER w28 AS nb_jours_observes_28j,
  dz.num_poste_ref, dz.distance_station_km,
  COALESCE(ms.tm_c, mi.tm_moyen_c) AS tm_c,
  COALESCE(ms.rr_mm, mi.rr_moyen_mm) AS rr_mm,
  CASE WHEN ms.tm_c IS NOT NULL AND ms.rr_mm IS NOT NULL THEN 'station de référence'
       WHEN mi.jour IS NOT NULL THEN 'moyenne IDF (repli)' ELSE 'indisponible' END AS source_meteo,
  mi.tm_moyen_c AS tm_idf_c, mi.rr_moyen_mm AS rr_idf_mm
FROM grille AS g
LEFT JOIN total AS l1 ON l1.zdc_id = g.zdc_id AND l1.jour = DATE_SUB(g.jour, INTERVAL 1 DAY)
LEFT JOIN total AS l7 ON l7.zdc_id = g.zdc_id AND l7.jour = DATE_SUB(g.jour, INTERVAL 7 DAY)
LEFT JOIN total AS l364 ON l364.zdc_id = g.zdc_id AND l364.jour = DATE_SUB(g.jour, INTERVAL 364 DAY)
LEFT JOIN `{projet}.{gold}.dim_zone` AS dz ON dz.zdc_id = g.zdc_id
LEFT JOIN `{projet}.{gold}.meteo_station_jour` AS ms ON ms.num_poste = dz.num_poste_ref AND ms.jour = g.jour
LEFT JOIN `{projet}.{gold}.meteo_jour_idf` AS mi ON mi.jour = g.jour
WINDOW
  w7 AS (PARTITION BY g.zdc_id ORDER BY UNIX_DATE(g.jour) RANGE BETWEEN 7 PRECEDING AND 1 PRECEDING),
  w28 AS (PARTITION BY g.zdc_id ORDER BY UNIX_DATE(g.jour) RANGE BETWEEN 28 PRECEDING AND 1 PRECEDING);

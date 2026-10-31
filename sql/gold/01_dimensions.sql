-- Gold : dimensions calendrier, zone (avec station météo de référence) et météo.

-- dim_date : une ligne par jour de la période d'étude.
CREATE OR REPLACE TABLE `{projet}.{gold}.dim_date` (
  jour DATE NOT NULL OPTIONS(description = "Clé : jour d'exploitation"),
  annee INT64 NOT NULL, trimestre INT64 NOT NULL, mois INT64 NOT NULL,
  semaine_iso INT64 NOT NULL OPTIONS(description = "Numéro de semaine ISO"),
  jour_semaine INT64 NOT NULL OPTIONS(description = "1 = lundi … 7 = dimanche"),
  nom_jour STRING NOT NULL,
  est_weekend BOOL NOT NULL,
  est_ferie BOOL NOT NULL OPTIONS(description = "Jour férié, zone métropole"),
  nom_ferie STRING,
  type_jour STRING NOT NULL OPTIONS(description = "Férié > Dimanche > Samedi > Ouvré (un férié prime sur le jour de semaine)"),
  est_pont BOOL NOT NULL OPTIONS(description = "Lundi ou vendredi ouvré accolé à un férié tombant mardi ou jeudi")
)
OPTIONS(description = "Calendrier {annee_debut}-{annee_fin}, grain jour ; vacances scolaires non couvertes (aucune source fournie)")
AS
WITH j AS (
  SELECT d AS jour, f.nom_ferie
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE({annee_debut}, 1, 1), DATE({annee_fin}, 12, 31))) AS d
  LEFT JOIN `{projet}.{silver}.jours_feries` AS f ON f.date_ferie = d
)
SELECT
  jour, EXTRACT(YEAR FROM jour), EXTRACT(QUARTER FROM jour), EXTRACT(MONTH FROM jour),
  EXTRACT(ISOWEEK FROM jour),
  MOD(EXTRACT(DAYOFWEEK FROM jour) + 5, 7) + 1,
  ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'][OFFSET(MOD(EXTRACT(DAYOFWEEK FROM jour) + 5, 7))],
  EXTRACT(DAYOFWEEK FROM jour) IN (1, 7),
  nom_ferie IS NOT NULL, nom_ferie,
  CASE WHEN nom_ferie IS NOT NULL THEN 'Férié' WHEN EXTRACT(DAYOFWEEK FROM jour) = 1 THEN 'Dimanche'
       WHEN EXTRACT(DAYOFWEEK FROM jour) = 7 THEN 'Samedi' ELSE 'Ouvré' END,
  nom_ferie IS NULL AND (
    (EXTRACT(DAYOFWEEK FROM jour) = 2 AND LEAD(nom_ferie) OVER (ORDER BY jour) IS NOT NULL) OR
    (EXTRACT(DAYOFWEEK FROM jour) = 6 AND LAG(nom_ferie) OVER (ORDER BY jour) IS NOT NULL))
FROM j;

-- Stations éligibles : TM et RR retenus sur au moins 95 % des jours de la période.
CREATE TEMP TABLE stations_eligibles AS
SELECT * FROM `{projet}.{silver}.stations_meteo`
WHERE nb_jours_tm >= 0.95 * nb_jours_periode AND nb_jours_rr >= 0.95 * nb_jours_periode;

-- dim_zone : une ligne par zone du référentiel, avec la station éligible la plus proche.
CREATE OR REPLACE TABLE `{projet}.{gold}.dim_zone` (
  zdc_id STRING NOT NULL OPTIONS(description = "Clé : identifiant de zone de correspondance"),
  nom_zone STRING, type_zone STRING, commune STRING, code_insee STRING, departement STRING,
  longitude FLOAT64, latitude FLOAT64,
  num_poste_ref STRING OPTIONS(description = "Station météo de référence : station éligible la plus proche du centre de la zone"),
  nom_station_ref STRING,
  distance_station_km FLOAT64 OPTIONS(description = "Distance géodésique zone–station, km"),
  presente_dans_validations BOOL NOT NULL OPTIONS(description = "La zone apparaît au moins une fois dans les validations")
)
CLUSTER BY zdc_id
OPTIONS(description = "Zones de correspondance (référentiel actuel) et rattachement météo géographique")
AS
WITH proche AS (
  SELECT z.zdc_id, s.num_poste, s.nom_station, ST_DISTANCE(z.point, s.point) / 1000 AS km,
         ROW_NUMBER() OVER (PARTITION BY z.zdc_id ORDER BY ST_DISTANCE(z.point, s.point), s.num_poste) AS rang
  FROM `{projet}.{silver}.zones_correspondance` AS z CROSS JOIN stations_eligibles AS s
)
SELECT z.zdc_id, z.nom_zone, z.type_zone, z.commune, z.code_insee, z.departement, z.longitude, z.latitude,
       p.num_poste, p.nom_station, ROUND(p.km, 3),
       z.zdc_id IN (SELECT DISTINCT id_zdc FROM `{projet}.{silver}.validations` WHERE id_zdc IS NOT NULL)
FROM `{projet}.{silver}.zones_correspondance` AS z
LEFT JOIN proche AS p ON p.zdc_id = z.zdc_id AND p.rang = 1;

-- meteo_station_jour : grain station éligible × jour, valeurs retenues uniquement.
CREATE OR REPLACE TABLE `{projet}.{gold}.meteo_station_jour` (
  num_poste STRING NOT NULL, jour DATE NOT NULL, nom_station STRING,
  rr_mm FLOAT64 OPTIONS(description = "Précipitations J 06 h UTC – J+1 06 h UTC, mm (qualité 0/1/9)"),
  tn_c FLOAT64, tx_c FLOAT64, tm_c FLOAT64 OPTIONS(description = "Moyenne des températures horaires, °C"),
  jour_pluvieux BOOL OPTIONS(description = "rr_mm >= 1 mm ; NULL si RR indisponible")
)
PARTITION BY DATE_TRUNC(jour, MONTH) CLUSTER BY num_poste
OPTIONS(description = "Météo quotidienne des stations éligibles (TM et RR disponibles >= 95 % des jours)")
AS
SELECT m.num_poste, m.jour, m.nom_station, m.rr_retenu, m.tn_retenu, m.tx_retenu, m.tm_retenu,
       IF(m.rr_retenu IS NULL, NULL, m.rr_retenu >= 1)
FROM `{projet}.{silver}.meteo_quotidienne` AS m
JOIN stations_eligibles AS s USING (num_poste);

-- meteo_jour_idf : grain jour ; synthèse régionale des stations éligibles (repli et usage réseau).
CREATE OR REPLACE TABLE `{projet}.{gold}.meteo_jour_idf` (
  jour DATE NOT NULL, nb_stations INT64 NOT NULL OPTIONS(description = "Stations éligibles avec TM ce jour"),
  rr_moyen_mm FLOAT64 OPTIONS(description = "Moyenne des RR des stations éligibles"),
  tm_moyen_c FLOAT64, tn_moyen_c FLOAT64, tx_moyen_c FLOAT64,
  part_stations_pluvieuses FLOAT64 OPTIONS(description = "Part des stations avec RR >= 1 mm")
)
OPTIONS(description = "Météo moyenne d'Île-de-France par jour (moyenne simple des stations éligibles)")
AS
SELECT jour, COUNTIF(tm_c IS NOT NULL), ROUND(AVG(rr_mm), 2), ROUND(AVG(tm_c), 2), ROUND(AVG(tn_c), 2),
       ROUND(AVG(tx_c), 2), ROUND(AVG(IF(jour_pluvieux, 1, 0)), 3)
FROM `{projet}.{gold}.meteo_station_jour`
GROUP BY jour;

-- Silver de la météo quotidienne Météo-France (famille RR-T-Vent, départements d'IDF).
-- Chargement : table externe sur les objets Bronze .csv.gz, avec un schéma explicite
-- (en-tête identique dans les 16 fichiers, vérifié). La pseudo-colonne _FILE_NAME
-- garde le fichier d'origine de chaque ligne.
-- Codes qualité (descriptif Météo-France) : 0 protégée, 1 validée, 9 filtrée
-- (contrôles de premier niveau passés), 2 douteuse en cours de vérification.
-- Règle retenue : valeur exploitable si code 0, 1 ou 9 ; valeur douteuse (2) mise à NULL
-- dans les colonnes *_retenu, la valeur brute restant disponible.

CREATE OR REPLACE EXTERNAL TABLE `{projet}.{silver}.meteo_externe` (
  NUM_POSTE STRING, NOM_USUEL STRING, LAT STRING, LON STRING, ALTI STRING, AAAAMMJJ STRING,
  RR STRING, QRR STRING, TN STRING, QTN STRING, HTN STRING, QHTN STRING,
  TX STRING, QTX STRING, HTX STRING, QHTX STRING, TM STRING, QTM STRING,
  TNTXM STRING, QTNTXM STRING, TAMPLI STRING, QTAMPLI STRING, TNSOL STRING, QTNSOL STRING,
  TN50 STRING, QTN50 STRING, DG STRING, QDG STRING, FFM STRING, QFFM STRING,
  FF2M STRING, QFF2M STRING, FXY STRING, QFXY STRING, DXY STRING, QDXY STRING,
  HXY STRING, QHXY STRING, FXI STRING, QFXI STRING, DXI STRING, QDXI STRING,
  HXI STRING, QHXI STRING, FXI2 STRING, QFXI2 STRING, DXI2 STRING, QDXI2 STRING,
  HXI2 STRING, QHXI2 STRING, FXI3S STRING, QFXI3S STRING, DXI3S STRING, QDXI3S STRING,
  HXI3S STRING, QHXI3S STRING, DRR STRING, QDRR STRING, STATUS_FXI3S STRING, STATUS_DXI3S STRING
)
OPTIONS (
  format = 'CSV', field_delimiter = ';', skip_leading_rows = 1, compression = 'GZIP',
  uris = ['gs://{bucket}/bronze/meteo/snapshot={snapshot}/*RR-T-Vent.csv.gz']
);

-- Table de chargement matérialisée : toutes les lignes, toutes années, texte brut.
CREATE OR REPLACE TABLE `{projet}.{silver}.meteo_chargement`
OPTIONS(description = "Météo quotidienne brute (texte), toutes périodes des fichiers Bronze, avec fichier d'origine")
AS SELECT *, _FILE_NAME AS fichier_source FROM `{projet}.{silver}.meteo_externe`;

CREATE OR REPLACE TABLE `{projet}.{silver}.meteo_quotidienne` (
  num_poste STRING NOT NULL OPTIONS(description = "Identifiant Météo-France de la station, 8 chiffres, texte"),
  nom_station STRING OPTIONS(description = "Nom usuel de la station"),
  departement STRING NOT NULL OPTIONS(description = "Deux premiers chiffres de num_poste"),
  latitude FLOAT64 OPTIONS(description = "Latitude WGS84, degrés décimaux"),
  longitude FLOAT64 OPTIONS(description = "Longitude WGS84, degrés décimaux"),
  altitude_m INT64 OPTIONS(description = "Altitude, m"),
  jour DATE NOT NULL OPTIONS(description = "Jour de la mesure"),
  rr FLOAT64 OPTIONS(description = "Précipitations de J 06 h UTC à J+1 06 h UTC, mm (valeur brute)"),
  qrr STRING OPTIONS(description = "Code qualité de RR"),
  tn FLOAT64 OPTIONS(description = "Température minimale sous abri, °C (brute)"),
  qtn STRING OPTIONS(description = "Code qualité de TN"),
  tx FLOAT64 OPTIONS(description = "Température maximale sous abri, °C (brute)"),
  qtx STRING OPTIONS(description = "Code qualité de TX"),
  tm FLOAT64 OPTIONS(description = "Moyenne des températures horaires, °C (brute)"),
  qtm STRING OPTIONS(description = "Code qualité de TM"),
  rr_retenu FLOAT64 OPTIONS(description = "RR si code qualité 0, 1 ou 9, sinon NULL"),
  tn_retenu FLOAT64 OPTIONS(description = "TN si code qualité 0, 1 ou 9, sinon NULL"),
  tx_retenu FLOAT64 OPTIONS(description = "TX si code qualité 0, 1 ou 9, sinon NULL"),
  tm_retenu FLOAT64 OPTIONS(description = "TM si code qualité 0, 1 ou 9, sinon NULL"),
  fichier_source STRING NOT NULL OPTIONS(description = "Objet Bronze d'origine")
)
-- Pas de partitionnement : la table pèse moins de 1 Go (partitions de moins de 1 Mo,
-- loin des ~10 Go recommandés) ; le clustering suffit à l'élagage des blocs.
CLUSTER BY num_poste, jour
OPTIONS(description = "Météo quotidienne, grain station × jour, années {annee_debut} à {annee_fin}")
AS
WITH t AS (
  SELECT
    TRIM(NUM_POSTE) AS num_poste, TRIM(NOM_USUEL) AS nom_station,
    SAFE_CAST(LAT AS FLOAT64) AS latitude, SAFE_CAST(LON AS FLOAT64) AS longitude,
    SAFE_CAST(ALTI AS INT64) AS altitude_m,
    SAFE.PARSE_DATE('%Y%m%d', AAAAMMJJ) AS jour,
    SAFE_CAST(RR AS FLOAT64) AS rr, NULLIF(QRR, '') AS qrr,
    SAFE_CAST(TN AS FLOAT64) AS tn, NULLIF(QTN, '') AS qtn,
    SAFE_CAST(TX AS FLOAT64) AS tx, NULLIF(QTX, '') AS qtx,
    SAFE_CAST(TM AS FLOAT64) AS tm, NULLIF(QTM, '') AS qtm,
    fichier_source
  FROM `{projet}.{silver}.meteo_chargement`
)
SELECT
  num_poste, nom_station, SUBSTR(num_poste, 1, 2) AS departement, latitude, longitude, altitude_m, jour,
  rr, qrr, tn, qtn, tx, qtx, tm, qtm,
  IF(qrr IN ('0', '1', '9'), rr, NULL) AS rr_retenu,
  IF(qtn IN ('0', '1', '9'), tn, NULL) AS tn_retenu,
  IF(qtx IN ('0', '1', '9'), tx, NULL) AS tx_retenu,
  IF(qtm IN ('0', '1', '9'), tm, NULL) AS tm_retenu,
  fichier_source
FROM t
WHERE jour BETWEEN DATE({annee_debut}, 1, 1) AND DATE({annee_fin}, 12, 31);

-- Stations : une ligne par station, avec sa couverture sur la période d'étude.
CREATE OR REPLACE TABLE `{projet}.{silver}.stations_meteo`
OPTIONS(description = "Stations météo d'IDF présentes sur la période, avec taux de couverture des mesures retenues")
AS
SELECT
  num_poste,
  ANY_VALUE(nom_station) AS nom_station,
  ANY_VALUE(departement) AS departement,
  ANY_VALUE(latitude) AS latitude, ANY_VALUE(longitude) AS longitude, ANY_VALUE(altitude_m) AS altitude_m,
  COUNT(DISTINCT nom_station) AS nb_noms, COUNT(DISTINCT latitude) AS nb_latitudes,
  MIN(jour) AS premier_jour, MAX(jour) AS dernier_jour,
  COUNT(DISTINCT jour) AS nb_jours,
  DATE_DIFF(DATE({annee_fin}, 12, 31), DATE({annee_debut}, 1, 1), DAY) + 1 AS nb_jours_periode,
  COUNTIF(rr_retenu IS NOT NULL) AS nb_jours_rr,
  COUNTIF(tm_retenu IS NOT NULL) AS nb_jours_tm,
  COUNTIF(tn_retenu IS NOT NULL AND tx_retenu IS NOT NULL) AS nb_jours_tn_tx,
  ST_GEOGPOINT(ANY_VALUE(longitude), ANY_VALUE(latitude)) AS point
FROM `{projet}.{silver}.meteo_quotidienne`
GROUP BY num_poste;

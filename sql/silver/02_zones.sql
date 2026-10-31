-- Silver des zones de correspondance (référentiel ACTUEL, export du snapshot).
-- Limite : aucune historisation ; une zone supprimée avant le snapshot est absente,
-- d'où des validations historiques potentiellement sans zone (taux mesuré en Gold).

CREATE OR REPLACE TABLE `{projet}.{silver}.zones_correspondance` (
  zdc_id STRING NOT NULL OPTIONS(description = "Identifiant de la zone (ZdCId), texte"),
  zdc_version STRING OPTIONS(description = "Version de la zone (ZdCVersion)"),
  date_creation TIMESTAMP OPTIONS(description = "Date de création (ZdCCreated)"),
  date_modification TIMESTAMP OPTIONS(description = "Date de dernière modification (ZdCChanged)"),
  nom_zone STRING OPTIONS(description = "Nom de la zone (ZdCName)"),
  type_zone STRING OPTIONS(description = "Type selon le mode principal (ZdCType)"),
  commune STRING OPTIONS(description = "Commune du centre de la zone (ZdCTown)"),
  code_insee STRING OPTIONS(description = "Code INSEE de la commune (ZdCPostalRegion) ; pas un code postal"),
  departement STRING OPTIONS(description = "Département déduit des deux premiers caractères du code INSEE"),
  x_lambert93 INT64 OPTIONS(description = "Coordonnée X du centre, Lambert 93 (EPSG:2154), mètres"),
  y_lambert93 INT64 OPTIONS(description = "Coordonnée Y du centre, Lambert 93 (EPSG:2154), mètres"),
  longitude FLOAT64 OPTIONS(description = "Longitude WGS84 convertie depuis Lambert 93 (pyproj)"),
  latitude FLOAT64 OPTIONS(description = "Latitude WGS84 convertie depuis Lambert 93 (pyproj)"),
  point GEOGRAPHY OPTIONS(description = "Centre de la zone, WGS84, pour les calculs de distance")
)
CLUSTER BY zdc_id
OPTIONS(description = "Zones de correspondance IDFM, une ligne par zone (référentiel actuel)")
AS
SELECT
  CAST(z.zdcid AS STRING) AS zdc_id,
  CAST(z.zdcversion AS STRING) AS zdc_version,
  TIMESTAMP(z.zdccreated) AS date_creation,
  TIMESTAMP(z.zdcchanged) AS date_modification,
  TRIM(z.zdcname) AS nom_zone,
  TRIM(z.zdctype) AS type_zone,
  TRIM(z.zdctown) AS commune,
  TRIM(CAST(z.zdcpostalregion AS STRING)) AS code_insee,
  SUBSTR(TRIM(CAST(z.zdcpostalregion AS STRING)), 1, 2) AS departement,
  CAST(z.zdcxepsg2154 AS INT64) AS x_lambert93,
  CAST(z.zdcyepsg2154 AS INT64) AS y_lambert93,
  g.longitude, g.latitude,
  ST_GEOGPOINT(g.longitude, g.latitude) AS point
FROM `{projet}.{silver}.zones_chargement` AS z
LEFT JOIN `{projet}.{silver}.zones_wgs84_chargement` AS g
  ON g.zdcid = CAST(z.zdcid AS STRING);

-- Silver des jours fériés (zone métropole), une ligne par date.

CREATE OR REPLACE TABLE `{projet}.{silver}.jours_feries` (
  date_ferie DATE NOT NULL OPTIONS(description = "Date du jour férié"),
  nom_ferie STRING NOT NULL OPTIONS(description = "Nom officiel du jour férié"),
  annee INT64 NOT NULL OPTIONS(description = "Année civile"),
  chemin_bronze STRING NOT NULL OPTIONS(description = "Objet Bronze d'origine")
)
OPTIONS(description = "Jours fériés de la zone métropole (calendrier.api.gouv.fr)")
AS
SELECT
  SAFE.PARSE_DATE('%Y-%m-%d', date) AS date_ferie,
  TRIM(nom) AS nom_ferie,
  annee_demandee AS annee,
  chemin_bronze
FROM `{projet}.{silver}.jours_feries_chargement`;

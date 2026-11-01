-- Gold : vues KPI pour le Data Analyst et catalogue sémantique pour un agent IA.

-- KPI par jour pour le réseau entier, avec le type de jour.
CREATE OR REPLACE VIEW `{projet}.{gold}.v_kpi_reseau_jour`
OPTIONS(description = "KPI réseau par jour : total des validations, type de jour, météo IDF")
AS
SELECT d.jour, d.annee, d.mois, d.type_jour, d.nom_ferie, d.est_pont,
       SUM(f.nb_vald) AS nb_vald,
       SUM(IF(f.categorie_titre = 'Imagine R', f.nb_vald, 0)) AS nb_vald_imagine_r,
       m.tm_moyen_c, m.rr_moyen_mm
FROM `{projet}.{gold}.dim_date` AS d
LEFT JOIN `{projet}.{gold}.fait_validations_jour` AS f USING (jour)
LEFT JOIN `{projet}.{gold}.meteo_jour_idf` AS m USING (jour)
GROUP BY d.jour, d.annee, d.mois, d.type_jour, d.nom_ferie, d.est_pont, m.tm_moyen_c, m.rr_moyen_mm;

-- Moyenne journalière par année et type de jour, indice base 100 = jour ouvré de l'année.
CREATE OR REPLACE VIEW `{projet}.{gold}.v_kpi_type_jour`
OPTIONS(description = "Validations moyennes par jour selon le type de jour ; indice 100 = jour ouvré moyen de l'année")
AS
WITH a AS (
  SELECT annee, type_jour, COUNT(*) AS nb_jours, AVG(nb_vald) AS moyenne_jour
  FROM `{projet}.{gold}.v_kpi_reseau_jour` GROUP BY annee, type_jour
)
SELECT annee, type_jour, nb_jours, ROUND(moyenne_jour) AS validations_moyennes_par_jour,
       ROUND(100 * moyenne_jour / MAX(IF(type_jour = 'Ouvré', moyenne_jour, NULL)) OVER (PARTITION BY annee), 1) AS indice_vs_ouvre
FROM a;

-- Mensuel par catégorie : total, moyenne journalière, part dans le mois.
CREATE OR REPLACE VIEW `{projet}.{gold}.v_kpi_mensuel_categorie`
OPTIONS(description = "Validations mensuelles par catégorie de titre harmonisée")
AS
WITH m AS (
  SELECT DATE_TRUNC(jour, MONTH) AS mois, categorie_titre,
         STRING_AGG(DISTINCT niveau_correspondance, ', ') AS niveau_correspondance,
         SUM(nb_vald) AS nb_vald, COUNT(DISTINCT jour) AS nb_jours
  FROM `{projet}.{gold}.fait_validations_jour`
  GROUP BY mois, categorie_titre
)
SELECT mois, categorie_titre, niveau_correspondance, nb_vald,
       ROUND(nb_vald / nb_jours) AS moyenne_par_jour,
       ROUND(100 * nb_vald / SUM(nb_vald) OVER (PARTITION BY mois), 2) AS part_pct
FROM m;

-- Annuel par zone : total, rang, évolution sur un an.
CREATE OR REPLACE VIEW `{projet}.{gold}.v_kpi_zone_annee`
OPTIONS(description = "Validations annuelles par zone, rang et évolution vs année précédente")
AS
WITH a AS (
  SELECT EXTRACT(YEAR FROM f.jour) AS annee, f.zdc_id, z.nom_zone, z.type_zone, z.departement,
         SUM(f.nb_vald) AS nb_vald, COUNT(DISTINCT f.jour) AS jours_observes
  FROM `{projet}.{gold}.fait_validations_jour` AS f
  JOIN `{projet}.{gold}.dim_zone` AS z USING (zdc_id)
  GROUP BY annee, f.zdc_id, z.nom_zone, z.type_zone, z.departement
)
SELECT *, RANK() OVER (PARTITION BY annee ORDER BY nb_vald DESC) AS rang,
       ROUND(100 * (nb_vald / LAG(nb_vald) OVER (PARTITION BY zdc_id ORDER BY annee) - 1), 2) AS evolution_pct
FROM a;

-- Règles d'usage des mesures : ce qu'un agent IA doit savoir pour ne pas se tromper.
CREATE OR REPLACE TABLE `{projet}.{gold}.regles_mesures` (
  objet STRING NOT NULL, regle STRING NOT NULL, type_regle STRING NOT NULL
)
OPTIONS(description = "Définitions métier, règles d'agrégation et limites des tables Gold")
AS SELECT * FROM UNNEST([
  STRUCT('nb_vald' AS objet, 'Nombre de validations d\'entrée sur le réseau ferré. Une validation n\'est pas un voyageur unique : une personne peut valider plusieurs fois par jour.' AS regle, 'définition' AS type_regle),
  ('nb_vald', 'Additive : se somme sur les jours, les zones et les catégories. Ne jamais faire la moyenne de moyennes.', 'agrégation'),
  ('nb_arrets', 'Non additif : ne pas sommer sur plusieurs jours ou zones.', 'agrégation'),
  ('jour', 'Jour d\'exploitation, de 04 h 00 à 03 h 59 le lendemain : une validation à 01 h appartient à la veille.', 'définition'),
  ('categorie_titre', 'Harmonisée entre deux nomenclatures. Avant juillet 2023, Forfait Navigo, Contrat Solidarité Transport et Autres titres reposent sur une correspondance « probable » ; Navigo Jour, FGT et « ? » n\'ont pas d\'équivalent après.', 'limite'),
  ('nb_vald_plancher_5', 'En 2023 S1, NB_VALD = 5 signifie « 5 validations ou moins » : les totaux de cette période sont légèrement majorés.', 'limite'),
  ('dim_zone', 'Référentiel actuel (snapshot) : une zone supprimée avant le snapshot n\'y figure pas ; voir zone_referencee.', 'limite'),
  ('code_stif_trns / code_stif_res', 'Codes à lire ensemble ; ne pas en déduire une ligne commerciale ni un exploitant non confirmé.', 'limite'),
  ('tm_c / rr_mm', 'Météo de la station éligible la plus proche du centre de la zone ; repli sur la moyenne IDF si la station n\'a pas de mesure. Voir source_meteo.', 'définition'),
  ('rr_mm', 'Cumul de J 06 h UTC à J+1 06 h UTC, décalé par rapport au jour d\'exploitation IDFM.', 'limite'),
  ('dim_date', 'Les vacances scolaires et les grèves ne sont pas renseignées : aucune source fournie.', 'limite'),
  ('categorie_titre', 'Rupture de classement en 2025 T1 : Forfaits courts passe d\'environ 1 % à 10-19 % du volume et Autres titres de 9 % à moins de 3 %. Cause non documentée : ne pas comparer ces deux catégories de part et d\'autre de janvier 2025.', 'limite')
]);

-- Catalogue des colonnes Gold avec leurs descriptions, lu depuis les métadonnées BigQuery.
CREATE OR REPLACE VIEW `{projet}.{gold}.v_catalogue_colonnes`
OPTIONS(description = "Dictionnaire des colonnes Gold (descriptions déclarées dans les schémas)")
AS
SELECT table_name AS table_gold, column_name AS colonne, data_type AS type, description
FROM `{projet}.{gold}.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`;

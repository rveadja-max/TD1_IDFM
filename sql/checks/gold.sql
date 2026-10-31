-- Contrôles Gold : unicité des clés de dimension, conservation des volumes,
-- taux de correspondance des jointures, couverture météo.
WITH
silv AS (SELECT COUNT(*) AS n, SUM(nb_vald) AS s FROM `{projet}.{silver}.validations`),
fait AS (SELECT COUNT(*) AS n, SUM(nb_lignes_source) AS lignes, SUM(nb_vald) AS s FROM `{projet}.{gold}.fait_validations_jour`),
zone_match AS (
  SELECT COUNT(*) AS lignes, COUNTIF(z.zdc_id IS NULL) AS lignes_sans, SUM(v.nb_vald) AS vald,
         SUM(IF(z.zdc_id IS NULL, v.nb_vald, 0)) AS vald_sans
  FROM `{projet}.{silver}.validations` AS v
  LEFT JOIN `{projet}.{gold}.dim_zone` AS z ON z.zdc_id = v.id_zdc),
date_match AS (
  SELECT COUNT(*) AS lignes, COUNTIF(d.jour IS NULL) AS sans, SUM(f.nb_vald) AS s
  FROM `{projet}.{gold}.fait_validations_jour` AS f LEFT JOIN `{projet}.{gold}.dim_date` AS d USING (jour)),
ds AS (
  SELECT COUNT(*) AS n, COUNT(DISTINCT FORMAT('%s|%t', zdc_id, jour)) AS cles, COUNTIF(jour_observe) AS observes,
         SUM(nb_vald) AS s, COUNTIF(source_meteo = 'station de référence') AS meteo_station,
         COUNTIF(source_meteo = 'moyenne IDF (repli)') AS meteo_repli, COUNTIF(source_meteo = 'indisponible') AS meteo_absente
  FROM `{projet}.{gold}.ds_zone_jour`),
fait_ref AS (SELECT SUM(nb_vald) AS s FROM `{projet}.{gold}.fait_validations_jour` WHERE zone_referencee)
SELECT 'G01' AS id, 'Unicité de dim_date.jour' AS controle,
  FORMAT('%d lignes, %d jours', COUNT(*), COUNT(DISTINCT jour)) AS mesure, 'égalité' AS attendu,
  IF(COUNT(*) = COUNT(DISTINCT jour), 'conforme', 'anomalie') AS statut,
  'Jointure fait -> date sans multiplication' AS interpretation FROM `{projet}.{gold}.dim_date`
UNION ALL
SELECT 'G02', 'Unicité de dim_zone.zdc_id', FORMAT('%d lignes, %d zones', COUNT(*), COUNT(DISTINCT zdc_id)), 'égalité',
  IF(COUNT(*) = COUNT(DISTINCT zdc_id), 'conforme', 'anomalie'), 'Jointure fait -> zone sans multiplication' FROM `{projet}.{gold}.dim_zone`
UNION ALL
SELECT 'G03', 'Unicité du grain de fait_validations_jour (jour × zone × catégorie)',
  FORMAT('%d lignes, %d clés', COUNT(*), COUNT(DISTINCT FORMAT('%t|%s|%s', jour, IFNULL(zdc_id, '∅'), categorie_titre))), 'égalité',
  IF(COUNT(*) = COUNT(DISTINCT FORMAT('%t|%s|%s', jour, IFNULL(zdc_id, '∅'), categorie_titre)), 'conforme', 'anomalie'),
  'Le niveau de correspondance ne crée pas de doublon de grain' FROM `{projet}.{gold}.fait_validations_jour`
UNION ALL
SELECT 'G04', 'Conservation Silver -> fait (lignes source et somme NB_VALD)',
  FORMAT('lignes %d -> %d ; NB_VALD %d -> %d', silv.n, fait.lignes, silv.s, fait.s), 'égalité',
  IF(silv.n = fait.lignes AND silv.s = fait.s, 'conforme', 'anomalie'), 'Agrégation sans perte ni ajout' FROM silv, fait
UNION ALL
SELECT 'G05', 'Jointure validations -> dim_zone : non-correspondance en lignes',
  FORMAT('%d / %d lignes (%.3f %%)', lignes_sans, lignes, 100 * lignes_sans / lignes), 'faible et expliqué',
  'information', 'Zones absentes du référentiel actuel ou ID_ZDC manquant' FROM zone_match
UNION ALL
SELECT 'G06', 'Jointure validations -> dim_zone : non-correspondance en volume',
  FORMAT('%d / %d validations (%.3f %%)', vald_sans, vald, 100 * vald_sans / vald), 'faible et expliqué',
  'information', 'Volume non localisable par zone ; conservé dans le fait avec zone_referencee = faux' FROM zone_match
UNION ALL
SELECT 'G07', 'Jointure fait -> dim_date : lignes sans date', FORMAT('%d / %d', sans, lignes), '0',
  IF(sans = 0, 'conforme', 'anomalie'), 'Toutes les dates du fait sont dans le calendrier' FROM date_match
UNION ALL
SELECT 'G08', 'Unicité du grain ds_zone_jour (zone × jour)', FORMAT('%d lignes, %d clés', n, cles), 'égalité',
  IF(n = cles, 'conforme', 'anomalie'), 'Jointures météo et retards sans multiplication' FROM ds
UNION ALL
SELECT 'G09', 'Conservation fait (zones référencées) -> ds_zone_jour', FORMAT('NB_VALD %d -> %d', fait_ref.s, ds.s), 'égalité',
  IF(fait_ref.s = ds.s, 'conforme', 'anomalie'), 'La grille zone × jour n\'ajoute ni ne retire de validations' FROM ds, fait_ref
UNION ALL
SELECT 'G10', 'Grille ds_zone_jour : jours observés', FORMAT('%d / %d (%.2f %%)', observes, n, 100 * observes / n), 'information',
  'information', 'Jour non observé : aucune ligne publiée pour la zone ce jour (nb_vald NULL, non imputé à 0)' FROM ds
UNION ALL
SELECT 'G11', 'Source de la météo dans ds_zone_jour',
  FORMAT('station %d, repli IDF %d, indisponible %d', meteo_station, meteo_repli, meteo_absente), 'repli minoritaire',
  IF(meteo_absente = 0, 'conforme', 'à examiner'), 'Part des zone-jours avec la météo de leur station de référence' FROM ds
UNION ALL
SELECT 'G12', 'Distance zone -> station de référence (zones avec validations)',
  FORMAT('médiane %.1f km, max %.1f km', APPROX_QUANTILES(distance_station_km, 2)[OFFSET(1)], MAX(distance_station_km)),
  'information', 'information', 'Précision géographique du rattachement météo'
FROM `{projet}.{gold}.dim_zone` WHERE presente_dans_validations
UNION ALL
SELECT 'G13', 'Stations de référence distinctes utilisées', FORMAT('%d', COUNT(DISTINCT num_poste_ref)), 'information',
  'information', 'Diversité spatiale de la météo affectée' FROM `{projet}.{gold}.dim_zone` WHERE presente_dans_validations
ORDER BY id

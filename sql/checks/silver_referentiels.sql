-- Contrôles Silver des zones, jours fériés et météo.
SELECT 'Z01' AS id, 'Unicité de zdc_id' AS controle,
  FORMAT('%d lignes, %d identifiants', COUNT(*), COUNT(DISTINCT zdc_id)) AS mesure, 'égalité' AS attendu,
  IF(COUNT(*) = COUNT(DISTINCT zdc_id), 'conforme', 'anomalie') AS statut,
  'Condition pour joindre les validations sans multiplier les lignes' AS interpretation
FROM `{projet}.{silver}.zones_correspondance`
UNION ALL
SELECT 'Z02', 'Zones sans coordonnées WGS84', FORMAT('%d', COUNTIF(point IS NULL)), '0',
  IF(COUNTIF(point IS NULL) = 0, 'conforme', 'anomalie'), 'Conversion Lambert 93 -> WGS84 appliquée à toutes les zones'
FROM `{projet}.{silver}.zones_correspondance`
UNION ALL
SELECT 'Z03', 'Zones hors de l\'emprise Île-de-France (lon 1,4–3,6 ; lat 48,1–49,3)',
  FORMAT('%d', COUNTIF(NOT (longitude BETWEEN 1.4 AND 3.6 AND latitude BETWEEN 48.1 AND 49.3))), '0 ou justifié',
  IF(COUNTIF(NOT (longitude BETWEEN 1.4 AND 3.6 AND latitude BETWEEN 48.1 AND 49.3)) = 0, 'conforme', 'à examiner'),
  'Vérifie que les coordonnées ont bien été lues comme Lambert 93'
FROM `{projet}.{silver}.zones_correspondance`
UNION ALL
SELECT 'F01', FORMAT('Jours fériés %d', annee), FORMAT('%d dates, %d distinctes', COUNT(*), COUNT(DISTINCT date_ferie)), '11 distinctes',
  IF(COUNT(DISTINCT date_ferie) = 11 AND COUNT(*) = 11, 'conforme', 'à examiner'), 'Nombre légal de jours fériés en métropole'
FROM `{projet}.{silver}.jours_feries` GROUP BY annee
UNION ALL
SELECT 'F02', 'Dates fériées illisibles ou hors de l\'année', FORMAT('%d', COUNTIF(date_ferie IS NULL OR EXTRACT(YEAR FROM date_ferie) != annee)), '0',
  IF(COUNTIF(date_ferie IS NULL OR EXTRACT(YEAR FROM date_ferie) != annee) = 0, 'conforme', 'anomalie'), 'Typage DATE sans perte'
FROM `{projet}.{silver}.jours_feries`
UNION ALL
SELECT 'M01', 'Unicité station × jour', FORMAT('%d lignes, %d clés', COUNT(*), COUNT(DISTINCT FORMAT('%s|%t', num_poste, jour))), 'égalité',
  IF(COUNT(*) = COUNT(DISTINCT FORMAT('%s|%t', num_poste, jour)), 'conforme', 'anomalie'), 'Les deux périodes de fichiers ne se recouvrent pas'
FROM `{projet}.{silver}.meteo_quotidienne`
UNION ALL
SELECT 'M02', FORMAT('Codes qualité de TM : %s', IFNULL(qtm, 'absent')), FORMAT('%d jours-station', COUNT(*)), 'information', 'information',
  '0/1 validée, 9 filtrée (retenue), 2 douteuse (exclue), absent = pas de mesure'
FROM `{projet}.{silver}.meteo_quotidienne` GROUP BY qtm
UNION ALL
SELECT 'M03', FORMAT('Codes qualité de RR : %s', IFNULL(qrr, 'absent')), FORMAT('%d jours-station', COUNT(*)), 'information', 'information',
  '0/1 validée, 9 filtrée (retenue), 2 douteuse (exclue), absent = pas de mesure'
FROM `{projet}.{silver}.meteo_quotidienne` GROUP BY qrr
UNION ALL
SELECT 'M04', 'Incohérences TN > TX ou RR < 0', FORMAT('%d TN>TX, %d RR<0', COUNTIF(tn_retenu > tx_retenu), COUNTIF(rr_retenu < 0)), '0',
  IF(COUNTIF(tn_retenu > tx_retenu) + COUNTIF(rr_retenu < 0) = 0, 'conforme', 'à examiner'), 'Cohérence physique des mesures retenues'
FROM `{projet}.{silver}.meteo_quotidienne`
UNION ALL
SELECT 'M05', 'Températures retenues hors de [-25 ; 45] °C', FORMAT('%d', COUNTIF(tn_retenu < -25 OR tx_retenu > 45)), '0',
  IF(COUNTIF(tn_retenu < -25 OR tx_retenu > 45) = 0, 'conforme', 'à examiner'), 'Plage plausible en Île-de-France'
FROM `{projet}.{silver}.meteo_quotidienne`
UNION ALL
SELECT 'M06', 'Stations avec TM et RR retenus sur au moins 95 % des jours',
  FORMAT('%d / %d stations', COUNTIF(nb_jours_tm >= 0.95 * nb_jours_periode AND nb_jours_rr >= 0.95 * nb_jours_periode), COUNT(*)),
  'au moins 1', IF(COUNTIF(nb_jours_tm >= 0.95 * nb_jours_periode AND nb_jours_rr >= 0.95 * nb_jours_periode) > 0, 'conforme', 'anomalie'),
  'Seules ces stations servent au rattachement météo des zones'
FROM `{projet}.{silver}.stations_meteo`
UNION ALL
SELECT 'M07', 'Stations à plusieurs noms ou positions sur la période', FORMAT('%d', COUNTIF(nb_noms > 1 OR nb_latitudes > 1)), '0',
  IF(COUNTIF(nb_noms > 1 OR nb_latitudes > 1) = 0, 'conforme', 'à examiner'), 'Une station = un point fixe'
FROM `{projet}.{silver}.stations_meteo`
ORDER BY id, controle

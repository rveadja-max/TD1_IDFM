-- Contrôles Silver des validations. Une ligne par contrôle : mesure, attendu, statut.
WITH
charg AS (
  SELECT COUNT(*) AS n,
         SUM(SAFE_CAST(REGEXP_REPLACE(NB_VALD, r'[\s\x{00A0}\x{202F}]', '') AS INT64)) AS s
  FROM `{projet}.{silver}.validations_chargement`),
silv AS (SELECT COUNT(*) AS n, SUM(nb_vald) AS s FROM `{projet}.{silver}.validations`),
rej AS (SELECT COUNT(*) AS n, IFNULL(SUM(nb_vald), 0) AS s FROM `{projet}.{silver}.validations_rejets`),
cle AS (
  SELECT COUNT(*) AS n_doublons, IFNULL(SUM(nb_vald_doublon), 0) AS vald_doublons FROM (
    SELECT COUNT(*) AS c, SUM(nb_vald) AS nb_vald_doublon
    FROM `{projet}.{silver}.validations`
    GROUP BY jour, code_stif_trns, code_stif_res, code_stif_arret, categorie_source HAVING c > 1)),
-- Clé étendue : un même code d'arrêt peut couvrir plusieurs arrêts (libellé et zone distincts).
cle_etendue AS (
  SELECT COUNT(*) AS n_doublons, IFNULL(STRING_AGG(DISTINCT FORMAT('%s (%s)', lib, f), ', '), '') AS ou FROM (
    SELECT ANY_VALUE(UPPER(libelle_arret)) AS lib, ANY_VALUE(REGEXP_EXTRACT(fichier_source, r'([^/]+)$')) AS f
    FROM `{projet}.{silver}.validations`
    GROUP BY jour, code_stif_trns, code_stif_res, code_stif_arret, UPPER(libelle_arret), id_zdc_source, categorie_source
    HAVING COUNT(*) > 1)),
zone AS (
  SELECT origine_id_zdc, COUNT(*) AS n, SUM(nb_vald) AS s FROM `{projet}.{silver}.validations` GROUP BY origine_id_zdc),
jours AS (
  SELECT EXTRACT(YEAR FROM d) AS annee, COUNT(*) AS attendus, COUNTIF(v.jour IS NOT NULL) AS presents
  FROM UNNEST(GENERATE_DATE_ARRAY(DATE({annee_debut}, 1, 1), DATE({annee_fin}, 12, 31))) AS d
  LEFT JOIN (SELECT DISTINCT jour FROM `{projet}.{silver}.validations`) AS v ON v.jour = d
  GROUP BY annee),
cat AS (
  SELECT niveau_correspondance, SUM(nb_vald) AS s, COUNT(*) AS n
  FROM `{projet}.{silver}.validations` GROUP BY niveau_correspondance),
-- Équivalence lda (2023 S1) / ID_ZDC (fichiers suivants) pour un même arrêt.
lda AS (
  SELECT COUNT(*) AS arrets_communs, COUNTIF(a.id_zdc = b.id_zdc) AS identiques FROM
    (SELECT DISTINCT code_stif_trns, code_stif_res, code_stif_arret, UPPER(libelle_arret) AS lib, id_zdc_source AS id_zdc
     FROM `{projet}.{silver}.validations` WHERE fichier_source LIKE '%2023_S1%' AND NOT arret_non_determine) AS a
  JOIN
    (SELECT code_stif_trns, code_stif_res, code_stif_arret, UPPER(libelle_arret) AS lib, ANY_VALUE(id_zdc_source) AS id_zdc
     FROM `{projet}.{silver}.validations` WHERE fichier_source LIKE '%2023_S2%' AND NOT arret_non_determine
     GROUP BY 1, 2, 3, 4 HAVING COUNT(DISTINCT id_zdc_source) = 1) AS b
  USING (code_stif_trns, code_stif_res, code_stif_arret, lib))
SELECT 'V01' AS id, 'Conservation des lignes : chargement = Silver + rejets' AS controle,
  FORMAT('%d = %d + %d', charg.n, silv.n, rej.n) AS mesure, 'égalité' AS attendu,
  IF(charg.n = silv.n + rej.n, 'conforme', 'anomalie') AS statut,
  'Aucune ligne perdue ni ajoutée par la transformation' AS interpretation FROM charg, silv, rej
UNION ALL
SELECT 'V02', 'Conservation de la somme NB_VALD lisible', FORMAT('%d = %d + %d', charg.s, silv.s, rej.s), 'égalité',
  IF(charg.s = silv.s + rej.s, 'conforme', 'anomalie'), 'Les validations sont conservées à l\'unité' FROM charg, silv, rej
UNION ALL
SELECT 'V03', 'Lignes rejetées', FORMAT('%d lignes, %d validations', rej.n, rej.s), '0 ou justifié',
  IF(rej.n = 0, 'conforme', 'à examiner'), 'Voir validations_rejets pour le motif de chaque ligne' FROM rej
UNION ALL
SELECT 'V04', 'Unicité de la clé jour × transporteur × réseau × arrêt × catégorie source',
  FORMAT('%d groupes en doublon (%d validations)', n_doublons, vald_doublons), '0',
  IF(n_doublons = 0, 'conforme', 'information'), 'Grain publié non unique : un même code d\'arrêt couvre plusieurs arrêts (libellés et zones distincts), voir V04b' FROM cle
UNION ALL
SELECT 'V04b', 'Unicité de la clé étendue (+ libellé + ID_ZDC publié)', FORMAT('%d groupes en doublon : %s', n_doublons, ou), '0 ou expliqué',
  IF(n_doublons = 0, 'conforme', 'à examiner'), 'Lignes complémentaires (valeurs différentes, somme cohérente avec la tendance) : conservées et sommées' FROM cle_etendue
UNION ALL
SELECT 'V05', FORMAT('Jours présents en %d', annee), FORMAT('%d / %d', presents, attendus), 'tous les jours',
  IF(presents = attendus, 'conforme', 'lacune'), 'Couverture calendaire de l\'année civile' FROM jours
UNION ALL
SELECT 'V06', 'Valeurs NB_VALD négatives ou nulles',
  FORMAT('%d négatives, %d nulles', COUNTIF(nb_vald < 0), COUNTIF(nb_vald = 0)), '0',
  IF(COUNTIF(nb_vald <= 0) = 0, 'conforme', 'à examiner'), 'Une ligne publiée porte au moins une validation'
FROM `{projet}.{silver}.validations`
UNION ALL
SELECT 'V07', 'Codes transporteur, réseau ou arrêt non numériques',
  FORMAT('%d lignes', COUNTIF(NOT REGEXP_CONTAINS(code_stif_trns, r'^\d+$') OR NOT REGEXP_CONTAINS(IFNULL(code_stif_res, '0'), r'^\d+$')
                                OR NOT REGEXP_CONTAINS(code_stif_arret, r'^\d+$'))), '0',
  IF(COUNTIF(NOT REGEXP_CONTAINS(code_stif_trns, r'^\d+$') OR NOT REGEXP_CONTAINS(IFNULL(code_stif_res, '0'), r'^\d+$')
             OR NOT REGEXP_CONTAINS(code_stif_arret, r'^\d+$')) = 0, 'conforme', 'à examiner'),
  'Codes conservés en texte ; cohérence de forme vérifiée'
FROM `{projet}.{silver}.validations`
UNION ALL
SELECT 'V08', FORMAT('Origine de la zone : %s', origine_id_zdc), FORMAT('%d lignes, %.4f %% des validations', n, 100 * s / SUM(s) OVER ()),
  'information', 'information', 'Zone publiée, complétée par le même arrêt (unique et référencée) ou absente' FROM zone
UNION ALL
SELECT 'V08b', 'Validations sur arrêt non déterminé (« Inconnu », ND, 999999)',
  FORMAT('%d lignes, %.4f %% des validations', COUNTIF(arret_non_determine), 100 * SAFE_DIVIDE(SUM(IF(arret_non_determine, nb_vald, 0)), SUM(nb_vald))),
  'information', 'information', 'Conservées dans les totaux réseau ; non localisables par zone' FROM `{projet}.{silver}.validations`
UNION ALL
SELECT 'V09', FORMAT('Part des validations à catégorie « %s »', niveau_correspondance),
  FORMAT('%.3f %% (%d lignes)', 100 * s / SUM(s) OVER (), n), 'information', 'information',
  'Fiabilité de l\'harmonisation des catégories entre nomenclatures' FROM cat
UNION ALL
SELECT 'V10', 'Équivalence lda (2023 S1) et ID_ZDC (2023 S2), même arrêt et libellé',
  FORMAT('%d / %d arrêts identiques', identiques, arrets_communs), 'tous',
  IF(identiques = arrets_communs, 'conforme', 'à examiner'), 'Justifie le renommage de lda en ID_ZDC' FROM lda
UNION ALL
SELECT 'V11', 'Valeurs plancher « 5 ou moins » (ancienne codification)',
  FORMAT('%d lignes, %.3f %% des validations', COUNTIF(nb_vald_plancher_5),
         100 * SAFE_DIVIDE(SUM(IF(nb_vald_plancher_5, nb_vald, 0)), SUM(nb_vald))), 'information', 'information',
  'Ces valeurs majorent le volume réel (entre 1 et 5) ; effet négligeable si la part est faible'
FROM `{projet}.{silver}.validations`
UNION ALL
SELECT 'V12', 'Arrêts portant plusieurs libellés', FORMAT('%d arrêts', COUNT(*)), 'information', 'information',
  'Libellés variables d\'un fichier à l\'autre : le libellé n\'est pas une clé' FROM (
  SELECT code_stif_trns, code_stif_res, code_stif_arret FROM `{projet}.{silver}.validations`
  GROUP BY 1, 2, 3 HAVING COUNT(DISTINCT UPPER(libelle_arret)) > 1)
ORDER BY id, controle

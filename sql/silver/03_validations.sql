-- Silver des validations : typage, nettoyage tracé, harmonisation, rejets explicites.
-- Entrée : validations_chargement (texte brut + provenance), voir src/silver/chargement.py.
-- Sorties : validations (lignes valides) et validations_rejets (lignes écartées + motif).
-- Invariant contrôlé : lignes(chargement) = lignes(validations) + lignes(rejets).

CREATE TEMP TABLE typees AS
WITH brut AS (
  SELECT
    *,
    TRIM(JOUR) AS jour_txt,
    -- Année et période déclarées par le nom du fichier : 2024_T3_NB_FER, 2023_S1_NB_FER…
    CAST(REGEXP_EXTRACT(FICHIER_SOURCE, r'(\d{4})_[ST]\d') AS INT64) AS annee_fichier,
    REGEXP_EXTRACT(FICHIER_SOURCE, r'\d{4}_([ST]\d)') AS periode_fichier
  FROM `{projet}.{silver}.validations_chargement`
),
periodes AS (
  SELECT
    *,
    DATE(annee_fichier,
         CASE periode_fichier WHEN 'S1' THEN 1 WHEN 'S2' THEN 7 WHEN 'T1' THEN 1
                              WHEN 'T2' THEN 4 WHEN 'T3' THEN 7 WHEN 'T4' THEN 10 END, 1) AS debut_periode
  FROM brut
)
SELECT
  -- Trois formats de date observés ; le format est choisi par motif, jamais deviné.
  CASE
    WHEN REGEXP_CONTAINS(jour_txt, r'^\d{4}-\d{2}-\d{2}') THEN SAFE.PARSE_DATE('%Y-%m-%d', SUBSTR(jour_txt, 1, 10))
    WHEN REGEXP_CONTAINS(jour_txt, r'^\d{2}/\d{2}/\d{4}$') THEN SAFE.PARSE_DATE('%d/%m/%Y', jour_txt)
    WHEN REGEXP_CONTAINS(jour_txt, r'^\d{2}/\d{2}/\d{2}$') THEN SAFE.PARSE_DATE('%d/%m/%y', jour_txt)
  END AS jour,
  jour_txt,
  -- Codes conservés en texte ; seul l'artefact décimal « .0 » des exports est retiré.
  NULLIF(REGEXP_REPLACE(TRIM(CODE_STIF_TRNS), r'\.0+$', ''), '') AS code_stif_trns,
  -- « ND » (non déterminé) est une valeur sentinelle de la source : traitée comme absente.
  NULLIF(NULLIF(REGEXP_REPLACE(TRIM(CODE_STIF_RES), r'\.0+$', ''), ''), 'ND') AS code_stif_res,
  NULLIF(NULLIF(REGEXP_REPLACE(TRIM(CODE_STIF_ARRET), r'\.0+$', ''), ''), 'ND') AS code_stif_arret,
  NULLIF(TRIM(LIBELLE_ARRET), '') AS libelle_arret,
  NULLIF(REGEXP_REPLACE(TRIM(ID_ZDC), r'\.0+$', ''), '') AS id_zdc_source,
  NULLIF(TRIM(CATEGORIE_TITRE), '') AS categorie_source,
  NB_VALD AS nb_vald_txt,
  -- Séparateurs de milliers (espaces, y compris insécables) retirés avant conversion.
  SAFE_CAST(REGEXP_REPLACE(NB_VALD, r'[\s\x{00A0}\x{202F}]', '') AS INT64) AS nb_vald,
  debut_periode,
  DATE_SUB(DATE_ADD(debut_periode, INTERVAL IF(STARTS_WITH(periode_fichier, 'S'), 6, 3) MONTH), INTERVAL 1 DAY) AS fin_periode,
  FICHIER_SOURCE AS fichier_source, LIGNE_SOURCE AS ligne_source,
  ENCODAGE_SOURCE AS encodage_source, NOM_COLONNE_ZDC AS nom_colonne_zdc
FROM periodes;

-- Valeurs sentinelles d'ID_ZDC observées : 999999 (arrêt « Inconnu ») et -1.
CREATE TEMP TABLE zdc AS
SELECT t.*,
  IF(id_zdc_source IN ('999999', '-1', '0'), NULL, id_zdc_source) AS id_zdc_lu,
  code_stif_arret IS NULL OR UPPER(IFNULL(libelle_arret, '')) = 'INCONNU' AS arret_non_determine,
  -- IFNULL : « NULL IN (…) » vaut NULL, ce qui exclurait à tort les zones absentes.
  IFNULL(id_zdc_source IN (SELECT zdc_id FROM `{projet}.{silver}.zones_correspondance`), FALSE) AS zdc_reference
FROM typees AS t;

-- Zone absente ou hors du référentiel actuel : on reprend la zone publiée pour le même
-- arrêt (transporteur × réseau × arrêt × libellé) dans les autres lignes, uniquement si
-- elle est unique ET présente dans le référentiel. Constat : jusqu'en 2025 T1, de grandes
-- gares (Montparnasse 74040, La Chapelle 74000…) sont publiées avec un ancien identifiant
-- absent du référentiel actuel ; à partir de 2025 T2 le même arrêt porte l'identifiant actuel.
-- La zone publiée reste disponible dans id_zdc_source.
CREATE TEMP TABLE complement AS
SELECT code_stif_trns, IFNULL(code_stif_res, '') AS res, code_stif_arret, UPPER(libelle_arret) AS lib,
       ANY_VALUE(id_zdc_lu) AS id_zdc_complete
FROM (SELECT DISTINCT code_stif_trns, code_stif_res, code_stif_arret, libelle_arret, id_zdc_lu FROM zdc
      WHERE id_zdc_lu IS NOT NULL AND NOT arret_non_determine) AS d
WHERE id_zdc_lu IN (SELECT zdc_id FROM `{projet}.{silver}.zones_correspondance`)
GROUP BY 1, 2, 3, 4
HAVING COUNT(DISTINCT id_zdc_lu) = 1;

CREATE TEMP TABLE motifs AS
SELECT
  z.* EXCEPT (id_zdc_lu, zdc_reference),
  CASE WHEN z.zdc_reference THEN z.id_zdc_lu ELSE COALESCE(c.id_zdc_complete, z.id_zdc_lu) END AS id_zdc,
  CASE WHEN z.zdc_reference THEN 'source'
       WHEN c.id_zdc_complete IS NOT NULL AND z.id_zdc_lu IS NULL THEN 'complétée (même arrêt, autres lignes)'
       WHEN c.id_zdc_complete IS NOT NULL THEN 'remplacée (ancien identifiant hors référentiel)'
       WHEN z.id_zdc_lu IS NOT NULL THEN 'source hors référentiel'
       ELSE 'absente' END AS origine_id_zdc,
  CASE
    WHEN z.jour IS NULL THEN 'date illisible'
    WHEN z.jour NOT BETWEEN z.debut_periode AND z.fin_periode THEN 'date hors de la période du fichier'
    WHEN z.nb_vald IS NULL THEN 'NB_VALD non numérique'
    WHEN z.nb_vald < 0 THEN 'NB_VALD négatif'
    WHEN z.code_stif_trns IS NULL THEN 'code transporteur absent'
    WHEN z.categorie_source IS NULL THEN 'catégorie absente'
  END AS motif_rejet,
  -- Ancienne codification : NB_VALD = 5 signifie « 5 validations ou moins » (doc. IDFM).
  -- Repérée par les données : fichiers dont le minimum de NB_VALD vaut 5.
  MIN(z.nb_vald) OVER (PARTITION BY z.fichier_source) = 5 AS fichier_plancher_5
FROM zdc AS z
LEFT JOIN complement AS c
  ON NOT z.zdc_reference AND NOT z.arret_non_determine
 AND c.code_stif_trns = z.code_stif_trns AND c.res = IFNULL(z.code_stif_res, '')
 AND c.code_stif_arret = z.code_stif_arret AND c.lib = UPPER(z.libelle_arret);

CREATE OR REPLACE TABLE `{projet}.{silver}.validations_rejets`
OPTIONS(description = "Lignes de validations écartées de Silver, avec leur motif et leur provenance")
AS SELECT * FROM motifs WHERE motif_rejet IS NOT NULL;

CREATE OR REPLACE TABLE `{projet}.{silver}.validations` (
  jour DATE NOT NULL OPTIONS(description = "Jour d'exploitation (04 h 00 à 03 h 59 le lendemain)"),
  code_stif_trns STRING NOT NULL OPTIONS(description = "Code transporteur (texte), à lire avec code_stif_res"),
  code_stif_res STRING OPTIONS(description = "Code réseau administratif (texte) ; NULL si « ND » ou vide dans la source"),
  code_stif_arret STRING OPTIONS(description = "Code de l'arrêt (texte) ; NULL si « ND » ou vide. Un même code peut désigner plusieurs arrêts (ex. T13)"),
  libelle_arret STRING OPTIONS(description = "Nom de l'arrêt, espaces de bord retirés"),
  arret_non_determine BOOL NOT NULL OPTIONS(description = "Arrêt « Inconnu » ou sans code : validations non localisables"),
  id_zdc_source STRING OPTIONS(description = "ID_ZDC tel que publié (lda en 2023 S1), artefact « .0 » retiré"),
  id_zdc STRING OPTIONS(description = "Zone retenue : publiée si référencée, sinon zone actuelle unique du même arrêt ; clé vers zones_correspondance"),
  origine_id_zdc STRING NOT NULL OPTIONS(description = "source | complétée (même arrêt, autres lignes) | remplacée (ancien identifiant hors référentiel) | source hors référentiel | absente"),
  categorie_source STRING NOT NULL OPTIONS(description = "Catégorie de titre telle que publiée"),
  categorie_titre STRING NOT NULL OPTIONS(description = "Catégorie harmonisée (ref_categorie_titre)"),
  niveau_correspondance STRING NOT NULL OPTIONS(description = "Fiabilité de l'harmonisation de la catégorie"),
  nb_vald INT64 NOT NULL OPTIONS(description = "Nombre de validations d'entrée ; une validation n'est pas un voyageur unique"),
  nb_vald_plancher_5 BOOL NOT NULL OPTIONS(description = "Vrai si NB_VALD = 5 dans un fichier à l'ancienne codification : valeur réelle comprise entre 1 et 5"),
  fichier_source STRING NOT NULL OPTIONS(description = "Fichier de l'archive Bronze d'origine"),
  ligne_source INT64 NOT NULL OPTIONS(description = "Numéro de ligne dans ce fichier ; (fichier_source, ligne_source) est la clé technique")
)
PARTITION BY jour
CLUSTER BY id_zdc, categorie_titre
OPTIONS(description = "Validations quotidiennes du réseau ferré IDFM ; grain publié jour × transporteur × réseau × arrêt × catégorie, voir contrôles V04")
AS
SELECT
  m.jour, m.code_stif_trns, m.code_stif_res, m.code_stif_arret, m.libelle_arret, m.arret_non_determine,
  m.id_zdc_source, m.id_zdc, m.origine_id_zdc,
  m.categorie_source,
  COALESCE(r.categorie_titre, CONCAT('Non référencée : ', m.categorie_source)) AS categorie_titre,
  COALESCE(r.niveau_correspondance, 'non_etablie') AS niveau_correspondance,
  m.nb_vald,
  (m.fichier_plancher_5 AND m.nb_vald = 5) AS nb_vald_plancher_5,
  m.fichier_source, m.ligne_source
FROM motifs AS m
LEFT JOIN `{projet}.{silver}.ref_categorie_titre` AS r USING (categorie_source)
WHERE m.motif_rejet IS NULL;

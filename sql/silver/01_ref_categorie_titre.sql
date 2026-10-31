-- Référentiel d'harmonisation des catégories de titres.
-- Deux nomenclatures coexistent (constaté sur le snapshot 2026-10-31) :
--   * ancienne, en majuscules, dans 2023 S1 : NAVIGO, IMAGINE R, AMETHYSTE, TST, FGT,
--     AUTRE TITRE, NAVIGO JOUR, NON DEFINI, « ? » ;
--   * nouvelle, à partir de 2023 S2 : Forfait Navigo, Imagine R, Amethyste,
--     Contrat Solidarité Transport, Forfaits courts, Autres titres, NON DEFINI.
-- Source des définitions de l'ancienne nomenclature : documentation IDFM
-- « Données de validation » (pièce jointe du jeu histo-validations-reseau-ferre).
-- Aucune correspondance n'est inventée : une catégorie sans équivalent établi garde
-- un libellé propre et le niveau « non_etablie ».

CREATE OR REPLACE TABLE `{projet}.{silver}.ref_categorie_titre` (
  categorie_source STRING NOT NULL OPTIONS(description = "Libellé exact lu dans la source, après suppression des espaces de bord"),
  categorie_titre STRING NOT NULL OPTIONS(description = "Catégorie harmonisée utilisée en Silver et Gold"),
  niveau_correspondance STRING NOT NULL OPTIONS(description = "identique | variante_orthographique | probable | non_etablie"),
  justification STRING OPTIONS(description = "Raison du rattachement")
)
OPTIONS(description = "Harmonisation des catégories de titres entre ancienne et nouvelle nomenclature IDFM")
AS SELECT * FROM UNNEST([
  STRUCT('Forfait Navigo' AS categorie_source, 'Forfait Navigo' AS categorie_titre, 'identique' AS niveau_correspondance, 'Nouvelle nomenclature' AS justification),
  ('Imagine R', 'Imagine R', 'identique', 'Nouvelle nomenclature'),
  ('Amethyste', 'Amethyste', 'identique', 'Nouvelle nomenclature'),
  ('Contrat Solidarité Transport', 'Contrat Solidarité Transport', 'identique', 'Nouvelle nomenclature'),
  ('Contrat Solidarite Transport', 'Contrat Solidarité Transport', 'variante_orthographique', 'Accent absent dans 2025 T4'),
  ('Forfaits courts', 'Forfaits courts', 'identique', 'Nouvelle nomenclature'),
  ('Autres titres', 'Autres titres', 'identique', 'Nouvelle nomenclature'),
  ('NON DEFINI', 'Non défini', 'identique', 'Validations dont le titre n\'est pas défini (anomalies selon IDFM)'),
  ('IMAGINE R', 'Imagine R', 'variante_orthographique', 'Même libellé en majuscules ; définition IDFM : forfaits annuels Imagine R scolaire et étudiant'),
  ('AMETHYSTE', 'Amethyste', 'variante_orthographique', 'Même libellé en majuscules ; définition IDFM : forfait Améthyste'),
  ('NAVIGO', 'Forfait Navigo', 'probable', 'Définition IDFM : forfaits Navigo annuel, mois et semaine ; libellé différent'),
  ('TST', 'Contrat Solidarité Transport', 'probable', 'Définition IDFM : forfaits à tarif réduit de la Réduction Solidarité Transport'),
  ('AUTRE TITRE', 'Autres titres', 'probable', 'Définition IDFM : forfaits spéciaux ; libellé proche'),
  ('NAVIGO JOUR', 'Navigo Jour (ancienne nomenclature)', 'non_etablie', 'Non décrite par la documentation IDFM ; rattachement à « Forfaits courts » non vérifié'),
  ('FGT', 'FGT (ancienne nomenclature)', 'non_etablie', 'Forfait Gratuité Transport ; pas d\'équivalent explicite dans la nouvelle nomenclature'),
  ('?', 'Inconnue « ? » (ancienne nomenclature)', 'non_etablie', 'Libellé illisible dans la source ; non assimilé à NON DEFINI')
]);

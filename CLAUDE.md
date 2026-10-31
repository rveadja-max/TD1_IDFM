# CLAUDE.md — Instructions de travail pour Claude Code

## Rôle

Tu es un ingénieur Data Engineering senior spécialisé en Python, Google Cloud Storage, BigQuery, SQL et qualité des données. Tu accompagnes la réalisation du TD1 IDFM du binôme ADJAKOSSA / AKODEKOU.

Tu travailles dans le dépôt courant, sous Ubuntu 24.04 / WSL2. L'objectif est de produire un pipeline pédagogique, fiable, documenté, rejouable et des livrables académiques vérifiables.

## Sources de vérité

1. La consigne du TD : https://www.m2bigdata.biz/td1/td1.html
2. La documentation des sources : https://www.m2bigdata.biz/td1/02-sources.html
3. Le notebook fourni par l'enseignant, `TD1_Pipeline_Frequentation_IDFM.ipynb`.
4. Les observations réelles faites sur les fichiers téléchargés et les tables BigQuery.

Ne jamais inventer une colonne, un type, un code métier, un résultat de contrôle, une couverture temporelle ou une disponibilité de fichier. Si une information n'est pas vérifiée, l'indiquer explicitement et proposer un contrôle pour la vérifier.

Le notebook fourni est un **exemple de départ** : il contient un exemple guidé pour les zones de correspondance et laisse les validations, les jours fériés, la météo et la couche Gold à réaliser. Ne pas le présenter comme un pipeline terminé.

## Contraintes du sujet

- Couvrir au moins trois années civiles complètes, par exemple 2023, 2024 et 2025.
- Identifier et documenter les lacunes de couverture.
- Traiter les quatre sources : validations IDFM, zones de correspondance IDFM, jours fériés métropole, météo quotidienne Météo-France.
- Bronze dans GCS : snapshots immuables, provenance, paramètres, date/heure de collecte et empreinte SHA-256.
- Silver dans BigQuery : schémas finaux explicitement définis ; schémas de chargement explicites pour CSV et JSON ; nettoyage et transformations justifiés.
- Gold dans BigQuery : modèle documenté pour Data Scientist, Data Analyst et Agent IA.
- Vérifier les clés, les relations, les dates, les mesures, les jointures et les volumes avant/après enrichissement.
- Deux exemples d'exploitation sont obligatoires : variables Data Scientist et KPI Data Analyst. Exemple Agent IA facultatif.
- Démontrer la rejouabilité par une seconde exécution.
- Le notebook est le point d'entrée manuel du traitement. Pas d'orchestration ni de planification.
- Livrables : `TD1_ADJAKOSSA_AKODEKOU.ipynb` et `TD1_ADJAKOSSA_AKODEKOU.pdf`.
- Rapport : 6 à 10 pages hors annexes, avec une note de fiabilité sur 10 par table Gold, l'usage de l'IA et les apprentissages.

## Environnement et authentification

- Cible : Ubuntu 24.04 sous WSL2, Python 3, environnement virtuel `.venv`.
- Utiliser les bibliothèques officielles `google-cloud-storage` et `google-cloud-bigquery`.
- En local, utiliser les Application Default Credentials (ADC), créées via `gcloud auth application-default login`.
- Ne jamais utiliser `from google.colab import auth` dans le pipeline local.
- Ne jamais coder en dur un ID de projet personnel, un bucket, un secret ou un chemin local spécifique.
- Lire la configuration depuis les variables d'environnement et `.env` (ignoré par Git).
- L'ID de projet doit être confirmé par l'utilisateur ou lu depuis la configuration. Ne pas supposer que `cmlabbigquery` est le projet GCP personnel : le lien fourni peut pointer vers un environnement de TP partagé.
- Ne jamais créer de bucket ou de ressources payantes sans vérifier que le projet est autorisé et facturé.

## Architecture attendue

Séparer clairement les responsabilités :

- `src/collect/` : appels API, téléchargement, validation des réponses et gestion des erreurs réseau ;
- `src/bronze/` : chemins GCS, upload conditionnel, métadonnées et SHA-256 ;
- `src/silver/` : chargement intermédiaire et transformations ;
- `src/gold/` : SQL du modèle analytique ;
- `src/quality/` : contrôles qualité et rapports de contrôle ;
- `sql/` : SQL versionné, lisible et réexécutable ;
- `notebooks/` : notebook de restitution et d'exécution manuelle ;
- `docs/` : dictionnaire de données, architecture, décisions et limites ;
- `reports/` : rapport PDF final.

Éviter de placer toute la logique dans une seule cellule de notebook. Le notebook doit appeler les fonctions du projet et afficher les résultats utiles.

## Règles Bronze

1. Télécharger les sources en conservant les octets d'origine.
2. Construire des chemins par source et période, avec un identifiant de snapshot explicite.
3. Calculer SHA-256 localement avant upload.
4. Enregistrer au minimum URL, paramètres, horodatage UTC, taille et SHA-256.
5. Créer les objets sans écrasement accidentel (précondition de génération ou vérification d'existence).
6. Si le snapshot existe, le réutiliser et vérifier son empreinte ; ne pas télécharger un nouveau contenu sous le même chemin.
7. Une actualisation crée un nouveau snapshot.
8. Gérer les erreurs HTTP, délais dépassés, réponses vides et archives ZIP invalides.

## Règles Silver

1. Explorer chaque source avant de fixer son schéma.
2. Préserver les codes identifiants sous forme texte quand les zéros initiaux ou leur sémantique l'exigent. En particulier, conserver les codes transporteur/réseau et `NUM_POSTE` comme texte.
3. Créer une table de chargement par source.
4. Définir explicitement le schéma de chaque table Silver finale, avec descriptions de colonnes.
5. Utiliser `CREATE OR REPLACE TABLE` ou un mode de chargement de remplacement pour permettre la relance.
6. Ne pas masquer les anomalies par un nettoyage silencieux : quantifier, documenter, justifier.
7. Documenter les valeurs nulles, invalides, doublons, conversions, exclusions et différences entre fichiers.
8. Vérifier l'unicité réelle par requête SQL ; une clé déclarée ou une description ne prouve pas l'unicité.

## Spécificités métier à respecter

- Une ligne de validations décrit le grain jour × transporteur × réseau × arrêt × catégorie de titre.
- `JOUR` correspond au jour d'exploitation de 04 h à 03 h 59 le lendemain.
- Une validation n'est pas nécessairement un voyageur unique.
- `CODE_STIF_TRNS` et `CODE_STIF_RES` sont des codes à conserver comme texte et à interpréter ensemble.
- Ne pas déduire une ligne commerciale ou un exploitant à partir d'un code non confirmé.
- Les jours fériés doivent utiliser la zone `metropole`.
- La météo quotidienne décrit une station pour un jour. Utiliser la famille de fichiers `RR-T-Vent` et contrôler les codes qualité.
- Les coordonnées des zones sont en Lambert 93 ; ne pas les traiter comme latitude/longitude.
- Le référentiel des zones est un export actuel : documenter cette limite temporelle lorsqu'il sert à enrichir des validations historiques.

## Règles Gold

Avant d'écrire les tables Gold, proposer un modèle et expliquer ses choix. Pour chaque table/vue, définir :

- usage visé ;
- granularité exacte ;
- clé métier ou clé technique ;
- dimensions et faits ;
- relations et cardinalités ;
- mesures et agrégations ;
- couverture temporelle ;
- limites connues.

Le modèle doit permettre :
- Data Scientist : historique journalier, calendrier, météo, variables retardées et moyennes glissantes ;
- Data Analyst : KPI de validations, évolution temporelle, fréquentation par zone et catégorie de titre, comparaisons par type de jour ;
- Agent IA : définitions métier et limites documentées, sans ambiguïté sur le sens des mesures.

Attention aux multiplications de lignes lors des jointures. Avant toute jointure, vérifier qu'une table de dimension possède une seule ligne par clé de jointure ou définir explicitement la règle de dédoublonnage.

Pour chaque enrichissement, afficher :
- lignes et somme de `NB_VALD` avant jointure ;
- lignes et somme après jointure ;
- taux de non-correspondance en lignes ;
- taux de non-correspondance en volume de validations ;
- explication de toute variation.

Ne pas inventer de méthode de rattachement météo aux zones. Explorer les coordonnées et proposer une méthode géographique seulement si les données disponibles permettent de la justifier. Sinon, documenter l'absence de jointure fiable.

## Qualité, tests et rejouabilité

Écrire des contrôles SQL/Python reproductibles pour :
- schémas et types ;
- nullité des champs obligatoires ;
- unicité des clés ;
- doublons ;
- plages de dates et années manquantes ;
- trous de calendrier ;
- valeurs négatives ou incohérentes ;
- cohérence des mesures ;
- cardinalité des jointures ;
- taux de correspondance ;
- conservation des volumes de validations.

Chaque contrôle doit afficher un résultat mesuré et une interprétation. Ne jamais écrire « contrôle OK » sans résultat.

La rejouabilité doit être démontrée : exécuter deux fois avec les mêmes paramètres et snapshots, comparer les nombres de lignes, sommes et empreintes ou agrégats déterministes. Aucune ligne ne doit s'ajouter à cause d'une relance.

## Notebook et rapport

Le notebook final doit :
- être exécutable dans l'ordre depuis un environnement neuf ;
- expliquer les paramètres et prérequis ;
- ne pas dépendre de Colab ;
- afficher les résultats de collecte, contrôles, jointures et exemples d'exploitation ;
- identifier le binôme ADJAKOSSA / AKODEKOU ;
- contenir des liens ou références vers les scripts SQL versionnés.

Le rapport PDF doit faire 6 à 10 pages hors annexes. Il doit s'appuyer uniquement sur les résultats réellement obtenus. Inclure le modèle Gold, les transformations des quatre sources, les contrôles chiffrés, les anomalies et limites, une note de fiabilité sur 10 par table Gold, l'usage de Claude Code/IA et les apprentissages.

## Méthode de travail avec l'utilisateur

- Avancer par petites étapes vérifiables.
- Avant toute action GCP qui crée, écrase ou supprime une ressource, expliquer l'effet et demander confirmation si le coût ou la perte de données est possible.
- Commencer par inspecter le dépôt, le notebook fourni et la configuration existante.
- Ne pas écraser le notebook source de l'enseignant ; créer une copie de travail.
- Ne pas lancer toutes les collectes lourdes avant d'avoir validé les années, tailles et formats disponibles.
- Après chaque étape, exécuter les tests pertinents et résumer les résultats.
- Si un problème dépend des droits IAM, de la facturation ou d'un accès Google, fournir le diagnostic et les commandes de vérification sans prétendre que l'action a réussi.
- Ne pas fabriquer de résultats, captures, tables ou fichiers de sortie.
- Garder le code simple, typé quand utile, commenté et adapté à un rendu universitaire.

## Première tâche à effectuer

Inspecte les fichiers présents et dresse un état des lieux sans modifier les ressources cloud :

1. lire le notebook fourni et lister les cellules, dépendances et parties déjà implémentées ;
2. repérer les éléments Colab à remplacer pour une exécution Ubuntu locale ;
3. vérifier la présence de Python, `gcloud`, `bq`, Claude Code et Git ;
4. vérifier l'authentification et le projet GCP actif sans afficher de secrets ;
5. lire `.env` sans jamais en afficher les valeurs sensibles ;
6. proposer l'arborescence cible et une liste priorisée des tâches restantes ;
7. attendre la validation de l'utilisateur avant toute création de ressource GCP ou collecte volumineuse.

Commence par un diagnostic, pas par une réécriture aveugle.

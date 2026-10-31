# TD1 — ETL des données de fréquentation IDFM

**Binôme :** ADJAKOSSA / AKODEKOU  
**Échéance :** 1er novembre 2026 à minuit  
**Environnement :** Ubuntu 24.04 sous Windows (WSL2), Python, Claude Code, Google Cloud Storage et BigQuery.

## 1. Objectif

Construire un pipeline ETL rejouable pour préparer au moins trois années civiles complètes de données de fréquentation du réseau ferré francilien, à partir de quatre sources :

1. Validations quotidiennes IDFM ;
2. Zones de correspondance IDFM ;
3. Jours fériés (zone métropole) ;
4. Météo quotidienne Météo-France.

Le pipeline suit l'architecture médaillon :

- **Bronze (GCS)** : fichiers bruts conservés en snapshots immuables, avec provenance et empreinte SHA-256 ;
- **Silver (BigQuery)** : données nettoyées, typées, contrôlées et dotées de schémas explicites ;
- **Gold (BigQuery)** : modèle documenté pour les usages Data Scientist, Data Analyst et Agent IA.

L'entraînement ML, le tableau de bord et le développement d'un agent IA ne font pas partie du périmètre.

## 2. Prérequis Google Cloud

Avant toute exécution, vérifier dans Google Cloud Console :

- le bon **ID de projet** (pas seulement son nom) ;
- la facturation active sur le projet ;
- les API Cloud Storage et BigQuery activées ;
- les droits nécessaires pour créer un bucket, des datasets, des tables et exécuter des requêtes ;
- une région cohérente pour le bucket et les datasets.

> Attention : le lien BigQuery fourni dans le sujet pointe vers le projet `cmlabbigquery` et l'espace `tp_lab`. Ne pas supposer que ce projet est votre projet personnel ou qu'il autorise la création d'un bucket GCS. Le sujet précise que Cloud Storage nécessite un projet lié à un compte de facturation. Vérifier les droits et la facturation avant de l'utiliser. Ne jamais publier de clé ou de secret dans Git.

## 3. Préparer Ubuntu 24.04 / WSL2

Installer Google Cloud CLI en suivant la procédure officielle pour Debian/Ubuntu :
https://cloud.google.com/sdk/docs/install

Puis initialiser et s'authentifier :

```bash
gcloud init
gcloud auth application-default login
gcloud config set project VOTRE_PROJECT_ID
gcloud config get-value project
gcloud auth list
```

Les bibliothèques Python utilisent les Application Default Credentials (ADC). Il n'est pas nécessaire de mettre un fichier JSON de clé de service dans le dépôt.

Installer les outils Python :

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip git build-essential

python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

Si `gcloud` n'est pas reconnu, fermer puis rouvrir le terminal WSL après l'installation.

## 4. Configuration du projet

Créer un fichier `.env` à partir du modèle :

```bash
cp .env.example .env
```

Renseigner au minimum :

```dotenv
GCP_PROJECT_ID=VOTRE_PROJECT_ID
GCP_LOCATION=EU
GCS_BUCKET=VOTRE_BUCKET_UNIQUE
BQ_DATASET_SILVER=silver_idfm
BQ_DATASET_GOLD=gold_idfm
START_YEAR=2023
END_YEAR=2025
SNAPSHOT_DATE=2026-10-31
```

Le fichier `.env` doit rester local et être ignoré par Git. Ne pas confondre l'ID du projet, le nom du projet, le nom du bucket et le nom d'un dataset.

Vérifier les ressources et les permissions avant de lancer le pipeline :

```bash
gcloud projects describe "$GCP_PROJECT_ID"
gcloud services list --enabled --project "$GCP_PROJECT_ID"
gcloud storage buckets list
bq ls --project_id="$GCP_PROJECT_ID"
```

La création du bucket et des datasets doit utiliser la même localisation compatible. La localisation d'un dataset BigQuery ne se modifie pas après sa création.

## 5. Installation et lancement

Le dépôt final doit contenir au minimum :

```text
.
├── README.md
├── CLAUDE.md
├── requirements.txt
├── .env.example
├── .gitignore
├── notebooks/
│   └── TD1_ADJAKOSSA_AKODEKOU.ipynb
├── src/
│   ├── config.py
│   ├── collect/
│   ├── bronze/
│   ├── silver/
│   ├── gold/
│   └── quality/
├── sql/
│   ├── silver/
│   ├── gold/
│   └── checks/
├── docs/
│   ├── dictionnaire_donnees.md
│   └── architecture.md
├── reports/
│   └── TD1_ADJAKOSSA_AKODEKOU.pdf
└── tests/
```

Installer les dépendances :

```bash
pip install -r requirements.txt
```

Lancer Jupyter :

```bash
jupyter lab
```

Exécuter le notebook `notebooks/TD1_ADJAKOSSA_AKODEKOU.ipynb` de haut en bas. Le notebook doit piloter le traitement et afficher les résultats des contrôles et des deux exemples d'exploitation obligatoires.

## 6. Règles de traitement à respecter

### Bronze

- Conserver les fichiers sources sans modification.
- Organiser les objets GCS par source et période, avec un chemin de snapshot daté.
- Enregistrer URL source, paramètres, horodatage UTC, taille et SHA-256.
- Réutiliser le snapshot existant lors d'une relance ; ne pas l'écraser.
- Créer un nouveau chemin de snapshot pour toute actualisation.

### Silver

- Explorer les formats et les colonnes avant de définir les schémas.
- Définir explicitement le schéma final de chaque table Silver.
- Définir aussi le schéma de chargement des CSV et JSON.
- Utiliser des tables de chargement distinctes, puis créer/alimenter les tables Silver en SQL.
- Utiliser un mode de remplacement contrôlé (`WRITE_TRUNCATE` / `CREATE OR REPLACE`) pour rendre les relances idempotentes.
- Documenter les conversions, exclusions, corrections, valeurs manquantes et doublons.
- Conserver les codes transporteur/réseau comme texte ; ne pas inventer les libellés inconnus.

### Gold

Le modèle doit expliciter pour chaque table ou vue :

- le rôle métier et la granularité (ce que représente une ligne) ;
- les colonnes, clés et relations ;
- les règles d'agrégation des mesures ;
- la période couverte, les limites et les règles de jointure.

Prévoir un socle commun utilisable par les trois publics. Les validations sont au grain jour × transporteur × réseau × arrêt × catégorie de titre dans la source IDFM. Une validation n'est pas nécessairement un voyageur unique.

### Contrôles obligatoires

- Conformité des types et schémas ;
- unicité des clés et doublons ;
- dates couvertes, trous de calendrier et valeurs manquantes ;
- valeurs négatives ou incohérentes ;
- cardinalité de chaque jointure ;
- nombre de lignes et somme de validations avant/après enrichissement ;
- taux de non-correspondance en nombre de lignes et en volume de validations ;
- absence de multiplication des validations par une table de dimension non unique ;
- seconde exécution sans ajout de doublons et avec des résultats identiques à paramètres et snapshots identiques.

Présenter deux exemples d'exploitation : calcul de variables pour Data Scientist et KPI pour Data Analyst. L'exemple Agent IA est facultatif.

## 7. Livrables

Produire les deux fichiers finaux, avec les résultats exécutés visibles :

- `TD1_ADJAKOSSA_AKODEKOU.ipynb`
- `TD1_ADJAKOSSA_AKODEKOU.pdf`

Le rapport vise 6 à 10 pages hors annexes et doit inclure :

1. modèle Gold et granularités ;
2. transformations appliquées aux quatre sources et justifications ;
3. contrôles, résultats chiffrés, anomalies et limites ;
4. note de fiabilité sur 10 pour chaque table Gold ;
5. usage de l'IA, évaluation et corrections ;
6. apprentissages du binôme.

Envoyer les deux fichiers ensemble à `ouael@mailbox.org` avant le 1er novembre 2026 à minuit.

## 8. Sécurité et coûts

- Ne jamais committer `.env`, les jetons, les identifiants ADC ou une clé de service.
- Utiliser un projet de TD autorisé et facturé ; surveiller les coûts GCS et BigQuery.
- Limiter les requêtes BigQuery avec un plafond de bytes facturés lorsque c'est possible.
- Ne pas lancer de gros traitements avant d'avoir inspecté les fichiers et estimé leur volume.
- Supprimer les ressources temporaires devenues inutiles après validation, sans supprimer les snapshots Bronze à conserver pour le rendu.

## 9. Références

- Consigne du TD : https://www.m2bigdata.biz/td1/td1.html
- Sources du TD : https://www.m2bigdata.biz/td1/02-sources.html
- Préparation Google Cloud : https://www.m2bigdata.biz/td1/03-avant-de-commencer.html
- Authentification BigQuery : https://cloud.google.com/bigquery/docs/authentication
- Authentification Cloud Storage : https://cloud.google.com/storage/docs/authentication
- Créer des datasets BigQuery : https://cloud.google.com/bigquery/docs/datasets

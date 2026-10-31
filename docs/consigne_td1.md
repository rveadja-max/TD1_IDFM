---
title: "ETL des données de fréquentation IDFM sur GCS et BigQuery"
source: "https://www.m2bigdata.biz/td1/td1.html"
date: "2026-10-31"
description: "Construire sur GCP un pipeline pour étudier la fréquentation du réseau ferré francilien à partir de quatre sources :"
---

## 1\. Objectif[](#objectif)

Construire sur GCP un pipeline pour étudier la fréquentation du réseau ferré francilien à partir de quatre sources :

*   [validations quotidiennes IDFM](https://www.m2bigdata.biz/td1/02-sources.html#validations-idfm) ;
*   [zones de correspondance IDFM](https://www.m2bigdata.biz/td1/02-sources.html#zones-correspondance) ;
*   [jours fériés](https://www.m2bigdata.biz/td1/02-sources.html#jours-feries) ;
*   [météo quotidienne](https://www.m2bigdata.biz/td1/02-sources.html#meteo-quotidienne).

Les données préparées doivent couvrir **au moins trois années civiles complètes**, par exemple 2023-2025. Les éventuelles lacunes doivent être identifiées et documentées.

Votre modèle de données doit répondre aux besoins de trois publics :

 

Public

Besoin

**Data Scientist**

Préparer un modèle de prévision grâce à l’historique des validations et à des variables explicatives : calendrier, météo, validations passées, moyennes glissantes.

**Data Analyst**

Calculer des KPI pour un tableau de bord : évolution des validations, fréquentation par zone, répartition par catégorie de titre et comparaison selon les jours.

**Agent IA**

Interroger des données documentées pour répondre aux questions métier sur la fréquentation, son évolution et les périodes couvertes.

Le travail demandé porte sur la préparation des données. L’entraînement d’un modèle ML, la création d’un tableau de bord et le développement d’un agent IA sont hors périmètre.

## 2\. Collecter les données - Bronze dans Cloud Storage[](#collecter-les-données---bronze-dans-cloud-storage)

Récupérer les sources et stocker les fichiers bruts dans un bucket GCS.

Organiser les fichiers par source et par période. Conserver leur provenance afin de pouvoir retrouver les données utilisées et relancer le traitement.

Un snapshot Bronze est conservé : une relance réutilise le fichier déjà collecté. Pour actualiser une source, créer un nouveau snapshot sous un nouveau chemin. Enregistrer l’URL, les paramètres, l’horodatage de collecte et une empreinte du fichier (par exemple SHA-256).

Les sources sont présentées dans la page [Données sources](https://www.m2bigdata.biz/td1/02-sources.html).

## 3\. Préparer les données - Silver dans BigQuery[](#préparer-les-données---silver-dans-bigquery)

Après exploration des sources, définir explicitement le schéma de chaque table Silver avant son chargement.

Pour chaque colonne, préciser :

*   son nom ;
*   son type ;
*   ses contraintes (unicité, valeur obligatoire, etc.) ;
*   une courte description.

**Les tables Silver finales doivent avoir un schéma défini explicitement.** Une table intermédiaire peut reprendre le schéma embarqué d’un fichier Parquet. Elle sert à explorer et préparer les données ; elle ne remplace pas la définition du schéma final. Pour les CSV et JSON, définir aussi le schéma de chargement.

Charger chaque source dans une table de chargement, puis créer la table Silver avec son schéma explicite et l’alimenter par une requête SQL. À chaque relance, remplacer le contenu des tables au lieu d’ajouter les mêmes lignes. Afficher ensuite les contrôles et commenter les résultats.

L’unicité et les relations entre clés doivent être vérifiées par des contrôles : une description de colonne ou une clé déclarée dans BigQuery ne suffit pas.

Examiner et traiter les formats, les valeurs manquantes ou invalides, les doublons et les différences entre fichiers. Vérifier la couverture des dates et des zones ainsi que les possibilités de jointure entre sources.

Justifier les transformations appliquées aux données : corrections, filtrages, agrégations, conservations ou exclusions.

## 4\. Concevoir le modèle cible - Gold dans BigQuery[](#concevoir-le-modèle-cible---gold-dans-bigquery)

Construire un modèle adapté aux trois publics. Plusieurs tables ou vues peuvent être proposées à partir d’un socle commun.

Pour chaque table ou vue, préciser :

*   son rôle et sa granularité : ce que représente une ligne ;
*   ses colonnes, ses clés et ses relations ;
*   ses mesures et leurs règles d’agrégation.

Documenter les tables et les colonnes : définitions métier, unités, périodes couvertes, règles de jointure et limites connues. Cette documentation permet notamment à un agent IA d’interpréter les résultats sans inventer leur sens.

## 5\. Vérifier et démontrer[](#vérifier-et-démontrer)

Réaliser des contrôles sur :

*   la conformité aux schémas ;
*   l’unicité des clés ;
*   les dates couvertes et les valeurs manquantes ;
*   la cohérence des mesures ;
*   les résultats des jointures.

Pour chaque jointure, préciser les clés et la cardinalité attendue. Présenter le nombre de lignes et les totaux de validations avant et après enrichissement, ainsi que le taux de non-correspondance en lignes et en volume de validations. Justifier toute variation de volume. Vérifier que les tables utilisées pour enrichir les validations ont une seule ligne par clé de jointure, afin de ne pas multiplier les lignes ni les totaux de validations.

Présenter **deux exemples d’exploitation obligatoires** :

1.  Un calcul de variables pour le Data Scientist.
2.  Une requête de KPI pour le Data Analyst.

Une requête répondant à une question métier pour l’agent IA est **optionnelle**. Pour chaque exemple présenté, expliquer la question, fournir la requête ou le calcul, afficher le résultat et en commenter les limites.

Le traitement doit être **rejouable** : à sources et paramètres identiques, une relance doit produire les mêmes données, sans doublons supplémentaires.

L’exécution est manuelle, depuis le notebook. L’orchestration et la planification sont hors périmètre.

## 6\. Livrables[](#livrables)

### Un notebook[](#un-notebook)

Présenter la collecte, les schémas Silver, les transformations, l’alimentation des couches Bronze/Silver/Gold, les contrôles et les exemples d’exploitation (dont celui de l’agent IA, optionnel).

Rendre le fichier `.ipynb` avec ses résultats de contrôles et d’exploitation visibles, les paramètres nécessaires et les instructions pour une exécution depuis un environnement neuf. Un lien Colab peut compléter ce fichier.

### Un rapport PDF[](#un-rapport-pdf)

Viser **6 à 10 pages hors annexes**. Identifier les deux membres du binôme dans le rapport et le notebook. Remettre ensemble les deux fichiers, nommés `TD1_Nom1_Nom2.ipynb` et `TD1_Nom1_Nom2.pdf`, pour le **1er novembre 2026**.

Inclure :

*   **Le modèle Gold** : tables ou vues, granularités, clés, relations et mesures.
*   **Les transformations par source** : traitements, justifications et conséquences.
*   **Une note de fiabilité sur 10 par table Gold**, argumentée à partir de vos observations : qualité, couverture, limites et adéquation aux besoins.
*   **Les vérifications réalisées** : résultats, anomalies détectées et problèmes restants.
*   **L’usage de l’IA** : parties concernées, manière de l’utiliser, évaluation des résultats et corrections apportées.
*   **Ce que vous avez appris** pendant le TD.

## 7\. Évaluation[](#évaluation)

Le notebook et le rapport sont évalués ensemble, sur **20 points**.

  

Critère

Points

Attendu pour obtenir tous les points

**Qualité des données**

5

Schémas explicites, traitements justifiés sur les quatre sources et limites documentées.

**Utilité des données**

4

Granularités, clés et agrégations cohérentes ; deux exemples obligatoires exploitables ; documentation pour les trois publics.

**Vérifications**

4

Contrôles des clés, valeurs, dates et jointures ; résultats chiffrés ; anomalies traitées ou justifiées ; notes de fiabilité argumentées.

**Qualité du code**

2

Code lisible, structuré et exécutable dans l’ordre avec les paramètres indiqués.

**Bonnes pratiques**

3

Couches organisées, provenance conservée, snapshots Bronze préservés, erreurs gérées et livrables documentés.

**Rejouabilité**

2

Seconde exécution démontrée, contenu identique sans doublons supplémentaires.



## Avant de commencer


Le TD se déroule dans un notebook Colab, sur votre propre projet Google Cloud. Préparez votre environnement **avant la séance** en suivant ces étapes.

## 1\. Demander votre coupon Google Cloud[](#demander-votre-coupon-google-cloud)

Google fournit au cours un coupon de **50 $** par étudiant :

1.  Ouvrir la [page de demande de coupon](https://gcp.secure.force.com/GCPEDU?cid=DxAtageUlo4UYKtmfn3ZkP9T6pFyBH2LQfElsi%2BJlm0eEoqvjpDE4I%2FSZPgHAvFk/).
2.  Indiquer votre nom et votre adresse `@etudiant.univ-reims.fr`, puis confirmer via l’e-mail reçu : un code vous est envoyé.
3.  Utiliser le code dans la [console de facturation](https://console.cloud.google.com/billing) pour créditer un compte de facturation. Les [slides d’aide](https://docs.google.com/presentation/d/1LMB4PFOYiZGew0tk_D6E6iEKuaveP_6ED_jOBB6r8aU/edit?slide=id.g1bcc591acc_0_13#slide=id.g1bcc591acc_0_13) détaillent l’activation pas à pas.

Un seul code par adresse e-mail. Demande et utilisation possibles jusqu’au **7 février 2027** ; le coupon reste valable jusqu’au **7 octobre 2027**.

## 2\. Créer le projet et activer la facturation[](#créer-le-projet-et-activer-la-facturation)

1.  Dans la [console Google Cloud](https://console.cloud.google.com/), créer un projet réservé au TD et le lier au compte de facturation crédité.
2.  Contrairement au lab du CM2, le Sandbox ne suffit pas : **Cloud Storage exige un projet lié à un compte de facturation**. Le volume du TD reste très faible face aux 50 $ de crédit.
3.  Copier l’**ID du projet**, visible dans le sélecteur en haut de la console (par exemple `td1-idfm-123456`). C’est l’ID qu’il faut, pas le nom.

## 3\. Ouvrir le notebook[](#ouvrir-le-notebook)

1.  Ouvrir le [notebook Colab](https://colab.research.google.com/drive/1xo-AwK5-32nqQ7u-1an66qYE02AHRCRL?usp=sharing).
2.  Dans Colab : **Fichier -> Enregistrer une copie dans Drive**, puis travailler dans cette copie.
3.  Coller l’ID du projet dans la variable `PROJET` de la cellule **Configuration**, l’exécuter, puis autoriser l’accès à votre compte Google.
4.  Exécuter les cellules **dans l’ordre**.


### Données sources du TD.

Quatre sources pour étudier la fréquentation du réseau ferré francilien selon le calendrier et la météo.

Les exemples utilisent **Python avec `requests`** et portent sur **2023**.

Installation : `python -m pip install requests`. Les API présentées sont publiques, sans clé d’accès.

## 1\. Validations quotidiennes IDFM[](#validations-idfm)

Une ligne décrit les validations d’entrée pour un **jour × transporteur × réseau × arrêt × catégorie de titre**.

[Source : historique des validations IDFM](https://data.iledefrance-mobilites.fr/explore/dataset/histo-validations-reseau-ferre/)

**Rôle :** mesurer la fréquentation par jour, arrêt et catégorie de titre. Une validation ne correspond pas nécessairement à un voyageur unique.

### Colonnes[](#colonnes)

 

Colonne

Signification

`JOUR`

Jour d’exploitation, de 04 h à 03 h 59 le lendemain.

`CODE_STIF_TRNS`

Code du transporteur dans la codification des validations ; voir les correspondances ci-dessous.

`CODE_STIF_RES`

Code du réseau administratif, à interpréter avec `CODE_STIF_TRNS` ; voir ci-dessous.

`CODE_STIF_ARRET`

Code de l’arrêt.

`ID_ZDC`

Identifiant de la zone de correspondance.

`LIBELLE_ARRET`

Nom de l’arrêt.

`CATEGORIE_TITRE`

Catégorie du titre de transport.

`NB_VALD`

Nombre de validations.

### Signification des codes transporteur et réseau[](#codes-transporteur-reseau)

Conserver ces codes comme du texte. Les correspondances suivantes servent à lire les validations ; elles ne constituent pas une cinquième source à collecter pour le TD.

#### Transporteur : `CODE_STIF_TRNS`[](#transporteur-code_stif_trns)

 

Code

Signification

`100`

RATP.

`800`

SNCF.

`810`

Code utilisé pour les RER A et B dans la codification STIF–SNCF, avec les réseaux `801` et `802`. Ces lignes sont exploitées par la RATP et la SNCF : ce code ne suffit pas à identifier l’exploitant de chaque validation.

`760`, `762`

Codes présents dans les données de validations, dont le libellé transporteur n’a pas été confirmé par les sources ci-dessous. Conserver les codes.

Sources : [liste officielle des transporteurs IDFM](https://data.iledefrance-mobilites.fr/explore/dataset/liste-transporteurs/) pour `100` et `800` ; [annexes du contrat STIF–SNCF, page PDF 104](https://www.iledefrance-mobilites.fr/medias/portail-idfm/7601a3ae-932b-499e-93d9-164200828509_contrat-stif-sncf-annexes.pdf#page=104) pour `810` et les réseaux associés.

#### Réseau : couple `CODE_STIF_TRNS`, `CODE_STIF_RES`[](#réseau-couple-code_stif_trns-code_stif_res)

**Un réseau administratif n’est pas toujours une ligne commerciale.** Lire les deux codes ensemble. Le tableau reprend la codification historique des contrats STIF de 2016 ; ses regroupements ne garantissent pas le périmètre exact des validations de 2023–2025.

  

Transporteur

Réseau

Signification dans la codification historique

`100`

`110`

Métro RATP ; la codification inclut aussi le funiculaire et Orlyval.

`100`

`112`

Tramways RATP, généralement présents dans les données du réseau de surface.

`810`

`801`

RER A.

`810`

`802`

RER B.

`800`

`803`

RER C.

`800`

`804`

RER D.

`800`

`805`

RER E.

`800`

`850`

Réseau Paris Est : lignes P et T4 dans cette codification.

`800`

`851`

Réseau Paris Sud Est : ligne R.

`800`

`852`

Réseau Paris Rive Gauche : ligne N.

`800`

`853`

Réseau Paris Nord : lignes H et K.

`800`

`854`

Réseau Paris Saint-Lazare : lignes J et L.

`800`

`855`

Liaison La Verrière–La Défense : ligne U.

`800`

`800`

Code observé dans les données de validations ; libellé réseau non confirmé.

`760`

`760`

Couple observé dans les données de validations ; libellé réseau non confirmé.

`762`

`762`

Couple observé dans les données de validations ; libellé réseau non confirmé.

`100`

`ND`

Valeur observée sans correspondance réseau confirmée ; traiter le réseau comme non renseigné.

Sources : [annexes du contrat STIF–RATP 2016–2020, page PDF 121](https://www.iledefrance-mobilites.fr/medias/portail-idfm/8911c1bc-40cb-4ec3-940e-0cc47fa53896_annexes-contrat-stif-ratp-2016-2020.pdf#page=121) pour les réseaux RATP ; [annexes du contrat STIF–SNCF, page PDF 104](https://www.iledefrance-mobilites.fr/medias/portail-idfm/7601a3ae-932b-499e-93d9-164200828509_contrat-stif-sncf-annexes.pdf#page=104) pour les réseaux SNCF.

Pour un code absent de ces tableaux, conserver sa valeur et indiquer « libellé non confirmé ». Ne pas déduire la ligne empruntée de ce seul code : les validations ferrées sont rattachées à l’entrée d’une station ou d’une gare, comme l’explique la [documentation IDFM des validations](https://data.iledefrance-mobilites.fr/api/v2/catalog/datasets/histo-validations-reseau-ferre/attachments/donnees_de_validation_pdf).

### Appel Python[](#appel-python)

Le catalogue renvoie le lien de l’archive annuelle :

```
import requests

url = (
    "https://data.iledefrance-mobilites.fr/api/explore/v2.1/"
    "catalog/datasets/histo-validations-reseau-ferre/records"
)
reponse = requests.get(url, params={"where": "annee = '2023'", "limit": 1}, timeout=30)
reponse.raise_for_status()
print(reponse.json())
```

La réponse contient, pour l’année demandée, un champ `reseau_ferre` dont l’attribut `url` désigne l’archive ZIP à télécharger.

## 2\. Zones de correspondance IDFM[](#zones-correspondance)

Une zone regroupe des arrêts proches entre lesquels une correspondance à pied est possible. Elle peut réunir plusieurs modes de transport.

[Source : zones de correspondance IDFM](https://data.iledefrance-mobilites.fr/explore/dataset/zones-de-correspondance/)

**Rôle :** nommer et localiser les zones des validations, puis rechercher des stations météo proches.

### Colonnes[](#colonnes-1)

Colonne

Signification

`ZdCId`

Identifiant de la zone.

`ZdCVersion`

Version de la zone.

`ZdCCreated`

Date de création.

`ZdCChanged`

Date de dernière modification.

`ZdCName`

Nom de la zone.

`ZdCXEpsg2154`

Coordonnée X du centre de la zone, en Lambert 93.

`ZdCYEpsg2154`

Coordonnée Y du même point, en Lambert 93.

`ZdCTown`

Commune de ce point.

`ZdCPostalRegion`

Code INSEE de la commune, pas le code postal.

`ZdCType`

Type de zone selon le mode de transport principal.

### Appel Python[](#appel-python-1)

L’API exporte le référentiel actuel. Préférer le format **Parquet** : plus compact, et le schéma (noms et types des colonnes) est embarqué dans le fichier, ce qui simplifie le chargement dans BigQuery :

```
import requests

url = (
    "https://data.iledefrance-mobilites.fr/api/explore/v2.1/"
    "catalog/datasets/zones-de-correspondance/exports/parquet"
)
reponse = requests.get(url, params={"limit": -1}, timeout=120)
reponse.raise_for_status()
print(len(reponse.content), "octets")
```

L’export CSV existe aussi : remplacer `parquet` par `csv`.

Cette source est traitée en exemple guidé dans le [notebook](https://colab.research.google.com/drive/1xo-AwK5-32nqQ7u-1an66qYE02AHRCRL?usp=sharing).

## 3\. Jours fériés[](#jours-feries)

L’API fournit les dates et les noms des jours fériés. Utiliser la zone **métropole** pour l’Île-de-France.

[Source : jours fériés de 2023](https://calendrier.api.gouv.fr/jours-feries/metropole/2023.json)

**Rôle :** enrichir le calendrier pour comparer les jours fériés aux autres jours.

### Structure de la réponse[](#structure-de-la-réponse)

La réponse est un objet JSON :

Élément

Signification

Exemple

Clé

Date du jour férié.

`2023-07-14`

Valeur

Nom du jour férié.

`14 juillet`

### Appel Python[](#appel-python-2)

```
import requests

url = "https://calendrier.api.gouv.fr/jours-feries/metropole/2023.json"
reponse = requests.get(url, timeout=30)
reponse.raise_for_status()
print(reponse.json())
```

## 4\. Météo quotidienne Météo-France[](#meteo-quotidienne)

Une ligne décrit les observations d’**une station pour un jour**. Les fichiers sont des CSV compressés en GZIP, répartis par département et période.

[Source : données météo quotidiennes](https://www.data.gouv.fr/datasets/donnees-climatologiques-de-base-quotidiennes)

**Rôle :** rapprocher la pluie et les températures de la fréquentation. La famille de fichiers **`RR-T-Vent`** contient les variables utiles au TD.

### Colonnes utiles[](#colonnes-utiles)

 

Colonne

Signification

`NUM_POSTE`

Identifiant de station sur 8 chiffres, à conserver comme du texte.

`NOM_USUEL`

Nom de la station.

`LAT`, `LON`

Latitude et longitude, en degrés décimaux.

`ALTI`

Altitude, en mètres.

`AAAAMMJJ`

Date, par exemple `20230714`.

`RR`

Précipitations quotidiennes, en mm.

`TN`

Température minimale, en °C.

`TM`

Moyenne des températures horaires, en °C.

`TX`

Température maximale, en °C.

`QRR`, `QTN`, `QTM`, `QTX`

Codes qualité des mesures correspondantes.

### Appel Python[](#appel-python-3)

L’API renvoie le catalogue des fichiers disponibles :

```
import requests

url = (
    "https://www.data.gouv.fr/api/1/datasets/"
    "donnees-climatologiques-de-base-quotidiennes/"
)
reponse = requests.get(url, timeout=30)
reponse.raise_for_status()
ressources = reponse.json()["resources"]
```
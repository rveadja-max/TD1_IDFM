"""Description des quatre sources et des objets à collecter pour une période donnée.

Chaque source produit une liste de `Cible` : un objet Bronze à déposer, la fonction qui
le télécharge et la fonction qui valide son contenu. La résolution des URL passe par
les catalogues officiels (IDFM, data.gouv.fr) : aucune URL de fichier n'est figée.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from functools import partial
from typing import Callable

from src.collect import validation
from src.collect.http import ErreurCollecte, Reponse, lire_json, telecharger

API_IDFM = "https://data.iledefrance-mobilites.fr/api/explore/v2.1/catalog/datasets"
URL_VALIDATIONS = f"{API_IDFM}/histo-validations-reseau-ferre/records"
URL_ZONES = f"{API_IDFM}/zones-de-correspondance/exports/parquet"
URL_FERIES = "https://calendrier.api.gouv.fr/jours-feries/metropole/{annee}.json"
URL_CATALOGUE_METEO = "https://www.data.gouv.fr/api/1/datasets/donnees-climatologiques-de-base-quotidiennes/"

# Départements d'Île-de-France : Paris, petite et grande couronne.
DEPARTEMENTS_IDF = ("75", "77", "78", "91", "92", "93", "94", "95")
COLONNES_ZONES = {"zdcid", "zdcname", "zdcxepsg2154", "zdcyepsg2154", "zdctype"}
ENTETE_METEO = "NUM_POSTE;NOM_USUEL;LAT;LON;ALTI;AAAAMMJJ;RR;QRR;TN;QTN"
# Titre d'une ressource météo : QUOT_departement_75_periode_1950-2024_RR-T-Vent
MOTIF_METEO = re.compile(r"^QUOT_departement_(\d{2})_periode_(\d{4})-(\d{4})_RR-T-Vent$")


@dataclass(frozen=True)
class Cible:
    source: str
    partition: str
    nom_fichier: str
    telecharger: Callable[[], Reponse]
    valider: Callable[[bytes], object]


def cibles_validations(annees: list[int]) -> list[Cible]:
    """Une archive ZIP annuelle ; son URL est lue dans le catalogue IDFM."""
    cibles = []
    for annee in annees:
        params = {"where": f"annee = '{annee}'", "limit": 1}
        resultats = lire_json(URL_VALIDATIONS, params)["results"]
        if not resultats:
            raise ErreurCollecte(f"Aucune archive de validations publiée pour {annee}")
        fichier = resultats[0]["reseau_ferre"]
        cibles.append(Cible(
            source="validations", partition=f"annee={annee}", nom_fichier=fichier["filename"],
            telecharger=partial(telecharger, fichier["url"], None, 600),
            valider=partial(validation.verifier_zip, motif_attendu="NB_FER"),
        ))
    return cibles


def cibles_zones() -> list[Cible]:
    """Export Parquet du référentiel actuel (pas d'historique disponible)."""
    return [Cible(
        source="zones", partition="", nom_fichier="zones-de-correspondance.parquet",
        telecharger=partial(telecharger, URL_ZONES, {"limit": -1}, 300),
        valider=partial(validation.verifier_parquet, colonnes_attendues=COLONNES_ZONES),
    )]


def cibles_feries(annees: list[int]) -> list[Cible]:
    return [Cible(
        source="jours_feries", partition=f"annee={a}", nom_fichier=f"metropole_{a}.json",
        telecharger=partial(telecharger, URL_FERIES.format(annee=a), None, 60),
        valider=partial(validation.verifier_json_feries, annee=a),
    ) for a in annees]


def ressources_meteo(annees: list[int]) -> list[dict]:
    """Ressources RR-T-Vent des départements d'IDF dont la période recoupe les années."""
    debut, fin = min(annees), max(annees)
    retenues = []
    for r in lire_json(URL_CATALOGUE_METEO)["resources"]:
        m = MOTIF_METEO.match(r["title"])
        if m and m.group(1) in DEPARTEMENTS_IDF and int(m.group(2)) <= fin and int(m.group(3)) >= debut:
            retenues.append({"departement": m.group(1), "periode": f"{m.group(2)}-{m.group(3)}",
                             "titre": r["title"], "url": r["url"]})
    manquants = set(DEPARTEMENTS_IDF) - {r["departement"] for r in retenues}
    if manquants:
        raise ErreurCollecte(f"Pas de fichier météo pour les départements {sorted(manquants)}")
    return retenues


def cibles_meteo(annees: list[int]) -> list[Cible]:
    return [Cible(
        source="meteo", partition=f"departement={r['departement']}",
        nom_fichier=r["url"].rsplit("/", 1)[-1],
        telecharger=partial(telecharger, r["url"], None, 300),
        valider=partial(validation.verifier_gzip, entete_attendue=ENTETE_METEO),
    ) for r in ressources_meteo(annees)]


def toutes_les_cibles(annees: list[int]) -> list[Cible]:
    return cibles_validations(annees) + cibles_zones() + cibles_feries(annees) + cibles_meteo(annees)

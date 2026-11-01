"""Couche Bronze : chemins GCS, dépôt sans écrasement, métadonnées et SHA-256.

Règles appliquées :
- un objet Bronze n'est jamais écrasé (précondition `if_generation_match=0`) ;
- si l'objet existe déjà, la source n'est pas re-téléchargée : l'objet est réutilisé
  et son empreinte SHA-256 est recalculée puis comparée à celle enregistrée ;
- chaque objet porte sa provenance (URL, paramètres, horodatage UTC, taille, SHA-256)
  dans ses métadonnées GCS et dans un manifeste JSON voisin (`<objet>.manifest.json`) ;
- une actualisation se fait en changeant SNAPSHOT_DATE, ce qui crée de nouveaux chemins ;
- chaque objet Bronze et son manifeste portent un hold temporaire GCS : tant qu'il est
  posé, GCS refuse toute suppression ou tout remplacement, quel que soit l'outil utilisé.
  Levée volontaire : gcloud storage objects update <objet> --no-temporary-hold.
"""

from __future__ import annotations

import hashlib
import json
from dataclasses import asdict, dataclass
from typing import Callable

from google.api_core.exceptions import PreconditionFailed
from google.cloud import storage

from src.collect.http import Reponse

RACINE_BRONZE = "bronze"


class ErreurBronze(RuntimeError):
    """Incohérence d'intégrité ou de provenance dans la couche Bronze."""


def sha256(contenu: bytes) -> str:
    return hashlib.sha256(contenu).hexdigest()


def chemin_bronze(source: str, snapshot: str, partition: str, nom_fichier: str) -> str:
    """Ex. bronze/validations/snapshot=2026-10-31/annee=2023/data-rf-2023.zip"""
    morceaux = [RACINE_BRONZE, source, f"snapshot={snapshot}"]
    if partition:
        morceaux.append(partition)
    morceaux.append(nom_fichier)
    return "/".join(morceaux)


@dataclass
class EntreeManifeste:
    source: str
    chemin_gcs: str
    url: str
    url_finale: str
    parametres: dict
    collecte_utc: str
    taille_octets: int
    sha256: str
    type_contenu: str
    statut_http: int
    snapshot: str
    statut_depot: str = ""  # "créé" ou "réutilisé" (rempli à chaque exécution)
    hold_temporaire: str = ""  # "posé" ou "déjà posé" (rempli à chaque exécution)


def _metadonnees(e: EntreeManifeste) -> dict[str, str]:
    """Métadonnées GCS (chaînes uniquement)."""
    return {
        "source": e.source, "url": e.url, "url_finale": e.url_finale,
        "parametres": json.dumps(e.parametres, ensure_ascii=False, sort_keys=True),
        "collecte_utc": e.collecte_utc, "taille_octets": str(e.taille_octets),
        "sha256": e.sha256, "snapshot": e.snapshot,
    }


def _creer_sans_ecraser(blob: storage.Blob, contenu: bytes, type_contenu: str) -> None:
    try:
        blob.upload_from_string(contenu, content_type=type_contenu or None, if_generation_match=0)
    except PreconditionFailed as e:
        # Un autre processus a créé l'objet entre la vérification et l'envoi.
        raise ErreurBronze(f"{blob.name} existe déjà : dépôt refusé pour ne pas l'écraser") from e


def proteger(blob: storage.Blob) -> str:
    """Pose un hold temporaire sur l'objet s'il n'en a pas (opération idempotente)."""
    blob.reload()
    if blob.temporary_hold:
        return "déjà posé"
    blob.temporary_hold = True
    blob.patch()
    return "posé"


def lire_manifeste(bucket: storage.Bucket, chemin: str) -> EntreeManifeste:
    brut = bucket.blob(chemin + ".manifest.json").download_as_bytes()
    return EntreeManifeste(**json.loads(brut))


def deposer(bucket: storage.Bucket, source: str, snapshot: str, chemin: str,
            telecharger: Callable[[], Reponse], valider: Callable[[bytes], object] | None = None,
            verifier_existant: bool = True) -> EntreeManifeste:
    """Dépose un objet Bronze une seule fois, puis le réutilise aux exécutions suivantes.

    `telecharger` n'est appelé que si l'objet n'existe pas encore : une relance ne
    contacte pas la source et ne peut donc pas introduire un contenu différent.
    """
    blob = bucket.blob(chemin)
    if blob.exists():
        entree = lire_manifeste(bucket, chemin)
        if verifier_existant:
            empreinte = sha256(blob.download_as_bytes())
            if empreinte != entree.sha256:
                raise ErreurBronze(
                    f"Empreinte divergente pour {chemin} : manifeste {entree.sha256[:12]}…, "
                    f"objet {empreinte[:12]}…"
                )
        entree.statut_depot = "réutilisé"
        entree.hold_temporaire = proteger(blob)
        proteger(bucket.blob(chemin + ".manifest.json"))
        return entree

    rep = telecharger()
    if valider is not None:
        valider(rep.contenu)  # lève une exception : rien n'est déposé
    entree = EntreeManifeste(
        source=source, chemin_gcs=chemin, url=rep.url, url_finale=rep.url_finale,
        parametres=rep.parametres, collecte_utc=rep.horodatage_utc,
        taille_octets=rep.taille, sha256=sha256(rep.contenu),
        type_contenu=rep.type_contenu, statut_http=rep.statut_http, snapshot=snapshot,
    )
    blob.metadata = _metadonnees(entree)
    _creer_sans_ecraser(blob, rep.contenu, rep.type_contenu)

    manifeste = {k: v for k, v in asdict(entree).items() if k not in ("statut_depot", "hold_temporaire")}
    blob_manifeste = bucket.blob(chemin + ".manifest.json")
    _creer_sans_ecraser(blob_manifeste, json.dumps(manifeste, ensure_ascii=False, indent=2).encode(),
                        "application/json")
    entree.statut_depot = "créé"
    entree.hold_temporaire = proteger(blob)
    proteger(blob_manifeste)
    return entree


def lister_snapshot(bucket: storage.Bucket, source: str, snapshot: str) -> list[EntreeManifeste]:
    """Relit tous les manifestes d'une source pour un snapshot (provenance complète)."""
    prefixe = f"{RACINE_BRONZE}/{source}/snapshot={snapshot}/"
    return [EntreeManifeste(**json.loads(b.download_as_bytes()))
            for b in bucket.list_blobs(prefix=prefixe) if b.name.endswith(".manifest.json")]

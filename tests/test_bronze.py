"""Tests de la couche Bronze avec un faux bucket en mémoire (ni réseau ni GCP)."""

import gzip
import io
import json
import zipfile

import pytest
from google.api_core.exceptions import PreconditionFailed

from src.bronze.storage import ErreurBronze, chemin_bronze, deposer, sha256
from src.collect import validation
from src.collect.http import ErreurCollecte, Reponse


class FauxBlob:
    def __init__(self, bucket, nom):
        self.bucket, self.name, self.metadata = bucket, nom, None

    def exists(self):
        return self.name in self.bucket.objets

    def upload_from_string(self, contenu, content_type=None, if_generation_match=None):
        if if_generation_match == 0 and self.exists():
            raise PreconditionFailed("existe")
        self.bucket.objets[self.name] = contenu if isinstance(contenu, bytes) else contenu.encode()

    def download_as_bytes(self):
        return self.bucket.objets[self.name]


class FauxBucket:
    def __init__(self):
        self.objets = {}

    def blob(self, nom):
        return FauxBlob(self, nom)


def reponse(contenu=b"octets d'origine"):
    return Reponse("https://ex.org/f", "https://ex.org/f", {"a": 1}, 200, "application/zip",
                   contenu, "2026-11-01T00:00:00+00:00")


CHEMIN = chemin_bronze("validations", "2026-10-31", "annee=2023", "data-rf-2023.zip")


def test_chemin_par_source_snapshot_et_partition():
    assert CHEMIN == "bronze/validations/snapshot=2026-10-31/annee=2023/data-rf-2023.zip"


def test_premier_depot_conserve_octets_et_provenance():
    b = FauxBucket()
    e = deposer(b, "validations", "2026-10-31", CHEMIN, lambda: reponse())
    assert e.statut_depot == "créé"
    assert b.objets[CHEMIN] == b"octets d'origine"
    manifeste = json.loads(b.objets[CHEMIN + ".manifest.json"])
    assert manifeste["sha256"] == sha256(b"octets d'origine")
    assert manifeste["url"] == "https://ex.org/f" and manifeste["parametres"] == {"a": 1}
    assert manifeste["taille_octets"] == 16 and manifeste["collecte_utc"].endswith("+00:00")


def test_relance_reutilise_sans_retelecharger():
    b = FauxBucket()
    deposer(b, "validations", "2026-10-31", CHEMIN, lambda: reponse())

    def interdit():
        raise AssertionError("la source ne doit pas être recontactée")

    e = deposer(b, "validations", "2026-10-31", CHEMIN, interdit)
    assert e.statut_depot == "réutilisé"
    assert b.objets[CHEMIN] == b"octets d'origine"


def test_objet_altere_detecte():
    b = FauxBucket()
    deposer(b, "validations", "2026-10-31", CHEMIN, lambda: reponse())
    b.objets[CHEMIN] = b"contenu modifie"
    with pytest.raises(ErreurBronze, match="Empreinte divergente"):
        deposer(b, "validations", "2026-10-31", CHEMIN, lambda: reponse())


def test_contenu_invalide_jamais_depose():
    b = FauxBucket()
    with pytest.raises(ErreurCollecte):
        deposer(b, "validations", "2026-10-31", CHEMIN, lambda: reponse(b"pas un zip"),
                valider=validation.verifier_zip)
    assert b.objets == {}


def _zip(membres):
    tampon = io.BytesIO()
    with zipfile.ZipFile(tampon, "w") as zf:
        for nom, contenu in membres.items():
            zf.writestr(nom, contenu)
    return tampon.getvalue()


def test_verifier_zip():
    assert validation.verifier_zip(_zip({"a/2023_S1_NB_FER.txt": "x"}), "NB_FER") == ["a/2023_S1_NB_FER.txt"]
    with pytest.raises(ErreurCollecte, match="NB_FER"):
        validation.verifier_zip(_zip({"a/autre.txt": "x"}), "NB_FER")


def test_verifier_gzip_et_json():
    validation.verifier_gzip(gzip.compress(b"NUM_POSTE;NOM\n1;2"), "NUM_POSTE;")
    with pytest.raises(ErreurCollecte):
        validation.verifier_gzip(b"pas du gzip", "NUM_POSTE;")
    assert validation.verifier_json_feries(b'{"2023-01-01": "1er janvier"}', 2023)
    with pytest.raises(ErreurCollecte, match="hors"):
        validation.verifier_json_feries(b'{"2024-01-01": "1er janvier"}', 2023)

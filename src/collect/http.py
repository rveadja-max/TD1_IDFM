"""Téléchargement HTTP commun aux quatre sources.

Gère les erreurs réseau (nouvelles tentatives avec attente croissante), les codes HTTP
d'erreur, les délais dépassés et les réponses vides. Les octets reçus ne sont jamais
modifiés : ils sont conservés tels quels pour la couche Bronze.
"""

from __future__ import annotations

import json
import time
from dataclasses import dataclass
from datetime import datetime, timezone

import requests

ESSAIS_MAX = 4
ATTENTE_INITIALE_S = 2.0
# Codes pour lesquels une nouvelle tentative a un sens (surcharge ou panne passagère).
CODES_TRANSITOIRES = {429, 500, 502, 503, 504}


class ErreurCollecte(RuntimeError):
    """Téléchargement impossible ou réponse inexploitable."""


@dataclass(frozen=True)
class Reponse:
    url: str  # URL demandée
    url_finale: str  # URL après redirections
    parametres: dict
    statut_http: int
    type_contenu: str
    contenu: bytes
    horodatage_utc: str  # fin du téléchargement, ISO 8601

    @property
    def taille(self) -> int:
        return len(self.contenu)


def telecharger(url: str, parametres: dict | None = None, delai_s: int = 120,
                session: requests.Session | None = None) -> Reponse:
    """Télécharge `url` et renvoie les octets bruts avec leur provenance."""
    parametres = dict(parametres or {})
    client = session or requests.Session()
    derniere_erreur: Exception | None = None

    for essai in range(1, ESSAIS_MAX + 1):
        try:
            r = client.get(url, params=parametres, timeout=delai_s)
            if r.status_code in CODES_TRANSITOIRES:
                raise ErreurCollecte(f"HTTP {r.status_code} (transitoire)")
            if r.status_code >= 400:
                # Erreur définitive (404, 403…) : inutile de réessayer.
                raise ErreurCollecte(f"HTTP {r.status_code} pour {url}") from None
            if not r.content:
                raise ErreurCollecte(f"Réponse vide pour {url}")
            return Reponse(
                url=url,
                url_finale=r.url,
                parametres=parametres,
                statut_http=r.status_code,
                type_contenu=r.headers.get("content-type", ""),
                contenu=r.content,
                horodatage_utc=datetime.now(timezone.utc).isoformat(timespec="seconds"),
            )
        except ErreurCollecte as e:
            if "transitoire" not in str(e):
                raise
            derniere_erreur = e
        except (requests.Timeout, requests.ConnectionError) as e:
            derniere_erreur = e
        if essai < ESSAIS_MAX:
            time.sleep(ATTENTE_INITIALE_S * 2 ** (essai - 1))

    raise ErreurCollecte(f"Échec après {ESSAIS_MAX} essais pour {url} : {derniere_erreur}")


def lire_json(url: str, parametres: dict | None = None, delai_s: int = 60) -> object:
    """Appel d'API de catalogue : renvoie le JSON décodé."""
    rep = telecharger(url, parametres, delai_s)
    try:
        return json.loads(rep.contenu)
    except ValueError as e:
        raise ErreurCollecte(f"JSON invalide pour {url} : {e}") from e

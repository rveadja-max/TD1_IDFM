"""Validation des contenus téléchargés, avant tout dépôt en Bronze.

Un fichier refusé ici n'est jamais déposé : on évite de figer un contenu corrompu
dans un snapshot immuable.
"""

from __future__ import annotations

import gzip
import io
import json
import zipfile

from src.collect.http import ErreurCollecte


def verifier_zip(contenu: bytes, motif_attendu: str = "") -> list[str]:
    """Vérifie qu'une archive ZIP est lisible et intègre ; renvoie la liste des membres."""
    try:
        with zipfile.ZipFile(io.BytesIO(contenu)) as zf:
            corrompu = zf.testzip()  # relit chaque membre et contrôle son CRC
            if corrompu:
                raise ErreurCollecte(f"Membre corrompu dans l'archive : {corrompu}")
            membres = [n for n in zf.namelist() if not n.endswith("/")]
    except zipfile.BadZipFile as e:
        raise ErreurCollecte(f"Archive ZIP invalide : {e}") from e
    if not membres:
        raise ErreurCollecte("Archive ZIP vide")
    if motif_attendu and not any(motif_attendu in m for m in membres):
        raise ErreurCollecte(f"Aucun fichier « {motif_attendu} » dans l'archive : {membres}")
    return membres


def verifier_gzip(contenu: bytes, entete_attendue: str) -> None:
    """Vérifie qu'un CSV GZIP se décompresse entièrement et commence par l'en-tête attendu."""
    try:
        texte = gzip.decompress(contenu)
    except (OSError, EOFError) as e:
        raise ErreurCollecte(f"GZIP invalide : {e}") from e
    if not texte.startswith(entete_attendue.encode()):
        raise ErreurCollecte(f"En-tête inattendu : {texte[:80]!r}")


def verifier_json_feries(contenu: bytes, annee: int) -> dict:
    """La réponse doit être un objet {date: nom} dont toutes les dates sont dans l'année."""
    try:
        donnees = json.loads(contenu)
    except ValueError as e:
        raise ErreurCollecte(f"JSON invalide : {e}") from e
    if not isinstance(donnees, dict) or not donnees:
        raise ErreurCollecte("Réponse jours fériés vide ou mal formée")
    hors_annee = [d for d in donnees if not str(d).startswith(f"{annee}-")]
    if hors_annee:
        raise ErreurCollecte(f"Dates hors de l'année {annee} : {hors_annee}")
    return donnees


def verifier_parquet(contenu: bytes, colonnes_attendues: set[str]) -> int:
    """Lit le schéma Parquet ; renvoie le nombre de lignes."""
    import pyarrow.parquet as pq
    try:
        f = pq.ParquetFile(io.BytesIO(contenu))
    except Exception as e:  # pyarrow lève plusieurs types d'erreurs
        raise ErreurCollecte(f"Parquet invalide : {e}") from e
    manquantes = colonnes_attendues - set(f.schema_arrow.names)
    if manquantes:
        raise ErreurCollecte(f"Colonnes absentes du Parquet : {sorted(manquantes)}")
    return f.metadata.num_rows

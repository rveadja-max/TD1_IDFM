"""Tests de la comparaison des empreintes de rejouabilité."""

import pandas as pd

from src.quality.checks import comparer_empreintes


def _e(lignes, empreinte):
    return pd.DataFrame({"couche": ["silver"], "table_bq": ["t"], "lignes": [lignes],
                         "empreinte": pd.array([empreinte], dtype="Int64")})


def test_contenu_identique_et_different():
    assert comparer_empreintes(_e(3, 42), _e(3, 42)).contenu_identique.all()
    assert not comparer_empreintes(_e(3, 42), _e(3, 7)).contenu_identique.any()


def test_table_vide_identique():
    m = comparer_empreintes(_e(0, None), _e(0, None))
    assert m.contenu_identique.all() and m.lignes_identiques.all()

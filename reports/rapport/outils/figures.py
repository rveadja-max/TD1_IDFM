"""Figures du rapport, calculées depuis les tables Gold (aucune valeur saisie à la main).

Usage, depuis la racine du dépôt : .venv/bin/python reports/rapport/outils/figures.py
"""

import sys
import warnings
from pathlib import Path

RACINE = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(RACINE))
warnings.filterwarnings("ignore")

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import pandas as pd

from src import bq as B
from src.config import charger_config

SORTIE = Path(__file__).resolve().parents[1] / "figures"
SORTIE.mkdir(exist_ok=True)
plt.rcParams.update({"font.size": 9, "axes.spines.top": False, "axes.spines.right": False})

config = charger_config()
bq = B.client(config)
G = f"{config.projet}.{config.dataset_gold}"

# Figure 1 : validations quotidiennes du réseau, colorées par type de jour.
j = B.requete(bq, f"SELECT jour, type_jour, nb_vald FROM `{G}.v_kpi_reseau_jour` ORDER BY jour")
j["jour"] = pd.to_datetime(j["jour"])
fig, ax = plt.subplots(figsize=(7.2, 2.6))
couleurs = {"Ouvré": "#4b0000", "Samedi": "#ac7232", "Dimanche": "#9aa5ad", "Férié": "#2a7ab0"}
for t, c in couleurs.items():
    d = j[j.type_jour == t]
    ax.scatter(d.jour, d.nb_vald / 1e6, s=3, color=c, label=t)
ax.set_ylabel("millions de validations")
ax.legend(ncol=4, fontsize=7, frameon=False, loc="upper left", markerscale=3)
fig.tight_layout()
fig.savefig(SORTIE / "validations_jour.png", dpi=200)

# Figure 2 : parts trimestrielles des catégories harmonisées.
c = B.requete(bq, f"""
SELECT FORMAT_DATE('%Y-T%Q', jour) AS trimestre, categorie_titre, SUM(nb_vald) AS v
FROM `{G}.fait_validations_jour` GROUP BY 1, 2""")
p = c.pivot_table(index="trimestre", columns="categorie_titre", values="v", aggfunc="sum").fillna(0)
p = 100 * p.div(p.sum(axis=1), axis=0)
p = p[p.sum().sort_values(ascending=False).index]
fig, ax = plt.subplots(figsize=(7.2, 3.0))
p.plot.bar(stacked=True, ax=ax, width=0.8, colormap="tab20", legend=False)
ax.set_ylabel("% des validations"); ax.set_xlabel("")
ax.legend(fontsize=6, frameon=False, bbox_to_anchor=(1.01, 1), loc="upper left")
plt.xticks(rotation=45, ha="right")
fig.tight_layout()
fig.savefig(SORTIE / "categories_trimestre.png", dpi=200)
print("figures :", sorted(p.name for p in SORTIE.glob("*.png")))

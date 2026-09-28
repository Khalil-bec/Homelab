#!/usr/bin/env bash
#
# install.sh — configure les outils locaux du projet pour ce dépôt : un
# environnement virtuel Python avec Ansible épinglé, la collection
# community.docker, et le certificat TLS. Ne modifie RIEN au niveau
# système (aucune installation de paquets, aucune configuration Docker,
# aucun sudo). Suppose que vous avez déjà :
#   - Docker installé et en cours d'exécution
#   - mkcert et nss installés, et `mkcert -install` déjà exécuté une fois
#     (pour que l'autorité de certification locale soit approuvée sur cette machine)
#
set -euo pipefail


REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN="homelab.lab"
CERT_DIR="${REPO_ROOT}/traefik/certs"
VENV_DIR="${REPO_ROOT}/.venv"
COLLECTIONS_DIR="${REPO_ROOT}/.collections"

log() { echo -e "\n\033[1;34m==>\033[0m $1"; }

# ---- 0. Vérifier que les prérequis sont présents, ne pas les installer ----
for cmd in docker mkcert python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Erreur : '$cmd' introuvable dans le PATH." >&2
    echo "Ce script suppose qu'il est déjà installé — consultez le README" \
         "pour les étapes de configuration système à usage unique." >&2
    exit 1
  fi
done


# ---- 1. Environnement virtuel Python local au projet ----------------------
log "Création de l'environnement virtuel (si absent)"
if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
else
  echo "Existe déjà dans ${VENV_DIR}, réutilisation."
fi

source "${VENV_DIR}/bin/activate"
# Tout ce qui suit s'exécute avec le pip/python de l'environnement virtuel,


# ---- 2. Ansible épinlé ------------------------------------------------------
log "Installation des dépendances épinglées"

pip install --upgrade pip --quiet
pip install  ansible-core~=2.21.0 --quiet
pip install docker requests

# ---- 3. Collections Ansible (locales au projet, pas ~/.ansible) -----------
log "Installation des collections dans ./.collections"
mkdir -p "$COLLECTIONS_DIR"
if [[ -f "${REPO_ROOT}/ansible/requirements.yml" ]]; then
  ansible-galaxy collection install -r "${REPO_ROOT}/ansible/requirements.yml" \
    -p "$COLLECTIONS_DIR"
else
  echo "Aucun requirements.yml trouvé — installation des collections ignorée."
  echo "(Nécessaire uniquement si site.yml utilise des modules comme community.docker.*)"
fi

# ---- 4. Certificat TLS (écrit uniquement dans le dépôt) --------------------
log "Génération du certificat TLS pour *.${DOMAIN}"
mkdir -p "$CERT_DIR"
mkcert \
  -cert-file "${CERT_DIR}/homelab.pem" \
  -key-file "${CERT_DIR}/homelab-key.pem" \
  "*.${DOMAIN}" "${DOMAIN}"
chmod 600 "${CERT_DIR}/homelab-key.pem"
# Cela n'écrit que des fichiers sous traefik/certs/. N'exécute PAS
# `mkcert -install` — cela modifie les magasins de confiance du système/navigateur,
# ce qui est hors de portée de ce script. Si les certificats ne sont pas approuvés,
# exécutez `mkcert -install` vous-même une fois, séparément.

deactivate

log "Terminé"
cat <<EOF
Configuration locale du projet terminée :
  - Ansible (épinglé) dans ${VENV_DIR}
  - Collections dans ${COLLECTIONS_DIR}
  - Certificat TLS dans ${CERT_DIR}

Pour exécuter le playbook :
  source .venv/bin/activate
  ansible-playbook site.yml
EOF

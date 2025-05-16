#!/bin/bash

# Sujet : Envirronnement Sécurisé
# Author : ShHawk 

set -euo pipefail
export PATH="$PATH:/sbin:/usr/sbin"

# être root
if [ "$(id -u)" -ne 0 ]; then
  echo "[Erreur] veuillez exécuter en root" >&2
  exit 1
fi
# dépendances
for cmd in cryptsetup mkfs.ext4 mount umount fallocate dd lsblk; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[Erreur] $cmd non installé"; exit 1; }
done

# Variables par défaut
DEFAULT_SIZE="5G"
CONTAINER="$HOME/env_sec.img"
MAPPING="env_sec"
MOUNT_POINT="$HOME/env_sec_mount"

# Préparation du répertoire parent
CONTAINER_DIR="${CONTAINER%/*}"
if [[ ! -d "$CONTAINER_DIR" ]]; then
  mkdir -p "$CONTAINER_DIR"
fi

#  Affichage de l’état des devices 
show_lsblk() {
    echo
    echo "=== État block devices ==="
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "(loop|mapper|$(basename "$CONTAINER"))" \
      || lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    echo "=========================="
    echo
}

# Install 
install() {
    echo ">>> INSTALL ENVIRRONNEMENT <<<"
    show_lsblk

    # taille (défaut)
    read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " size
    size=${size:-$DEFAULT_SIZE}

    # passphrase LUKS (confirmation)
    read -s -p "Mot de passe LUKS : " pass; echo
    read -s -p "Confirmer le mot de passe : " pass2; echo
    [[ "$pass" != "$pass2" ]] && { echo "[Erreur] mots de passe différents"; exit 1; }

    # ne pas écraser un conteneur existant
    if [[ -f "$CONTAINER" ]]; then
        echo "[Erreur] $CONTAINER existe déjà"
        exit 1
    fi
    # mapping existant
    if cryptsetup status "$MAPPING" &>/dev/null; then
        echo "[Erreur] /dev/mapper/$MAPPING existe déjà"
        exit 1
    fi

    # création du fichier conteneur
    echo "Création de $CONTAINER de taille $size..."
    if fallocate -l "$size" "$CONTAINER" 2>/dev/null; then
        :
    else
        if [[ "$size" =~ [Gg]$ ]]; then
            cnt=$(echo "${size%?}*1024" | bc)
        else
            cnt=${size%M}
        fi
        dd if=/dev/zero of="$CONTAINER" bs=1M count="$cnt" status=progress
    fi
    show_lsblk

    # chiffrement LUKS
    echo "Initialisation LUKS (tapez YES en majuscules)…"
    printf '%s' "$pass" | \
      cryptsetup luksFormat --type luks1 --batch-mode "$CONTAINER" --key-file=-
    show_lsblk

    # ouverture du volume
    echo "Ouverture du volume chiffré…"
    printf '%s' "$pass" | \
      cryptsetup open --type luks1 --key-file=- "$CONTAINER" "$MAPPING"
    show_lsblk

    # format ext4
    echo "Formatage ext4…"
    mkfs.ext4 /dev/mapper/"$MAPPING"
    show_lsblk

    # montage
    echo "Montage sur $MOUNT_POINT…"
    mkdir -p "$MOUNT_POINT"
    mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
    show_lsblk

    echo "[GOOD] Installé et monté sur $MOUNT_POINT"
}

open() {
    echo ">>> OPEN ENVIRRONNEMENT <<<"
    show_lsblk

    [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur, lancez 'install'"; exit 1; }

    if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
        read -s -p "Passphrase LUKS : " pass; echo
        printf '%s' "$pass" | \
          cryptsetup open --type luks1 --key-file=- "$CONTAINER" "$MAPPING"
        echo "[GOOD] mapping /dev/mapper/$MAPPING créé"
    else
        echo "Volume déjà déverrouillé"
    fi
    show_lsblk

    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
        echo "[GOOD] Monté sur $MOUNT_POINT"
    else
        echo "Déjà monté"
    fi
    show_lsblk
}

close() {
    echo ">>> CLOSE ENVIRRONNEMENT <<<"
    show_lsblk

    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT"
        echo "[GOOD] Démonté $MOUNT_POINT"
    else
        echo "Rien à démonter"
    fi
    show_lsblk

    if cryptsetup status "$MAPPING" &>/dev/null; then
        cryptsetup close "$MAPPING"
        echo "[GOOD] Verrouillé /dev/mapper/$MAPPING"
    else
        echo "Volume déjà fermé"
    fi
    show_lsblk
}

#Usage 
usage() {
    echo "Usage: $0 {install|open|close}"
    exit 1
}

# Main
[[ $# -ne 1 ]] && usage
case "$1" in
    install) install ;;
    open)    open    ;;
    close)   close   ;;
    *) usage ;;
esac

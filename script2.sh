#!/bin/bash

set -euo pipefail
export PATH="$PATH:/sbin:/usr/sbin"

DEFAULT_SIZE="5G"
CONTAINER="$HOME/env_sec.img"
MAPPING="env_sec"
MOUNT_POINT="$HOME/env_sec_mount"

# Crée le dossier parent si besoin
mkdir -p "$(dirname "$CONTAINER")"

# Affiche l’état des block devices
show_lsblk() {
    echo
    echo "===  LSBLK ==="
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT | grep -E "(loop|mapper|${MAPPING}|$(basename $CONTAINER))" || lsblk -o NAME,SIZE,TYPE,MOUNTPOINT
    echo "=============================="
    echo
}

install() {
    echo ">>> INSTALLATION ENVIRONNEMENT <<<"
    show_lsblk

    # 1) Choix de la taille
    read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " size
    size=${size:-$DEFAULT_SIZE}

    # 2) Mot de passe LUKS
    read -s -p "Password LUKS : " pass;   echo
    read -s -p "Confirmer : "       pass2; echo
    [[ "$pass" != "$pass2" ]] && { echo "[Erreur] mots de passe différents"; exit 1; }

    # 3) Ne pas écraser existing file
    [[ -f "$CONTAINER" ]] && { echo "[Erreur] $CONTAINER existe déjà"; exit 1; }

    # 4) Création du fichier
    echo "Création de $CONTAINER de taille $size..."
    if command -v fallocate &>/dev/null; then
        fallocate -l "$size" "$CONTAINER"
    else
        if [[ "$size" =~ [Gg]$ ]]; then
            cnt=$(echo "${size%?}*1024" | bc)
        else
            cnt=${size%M}
        fi
        dd if=/dev/zero of="$CONTAINER" bs=1M count="$cnt" status=progress
    fi

    # 5) Chiffrement LUKS
    echo "Initialisation LUKS (tapez YES en majuscules)…"
    cryptsetup luksFormat "$CONTAINER"

    show_lsblk

    # 6) Ouverture du volume
    echo "Ouverture du volume chiffré…"
    cryptsetup open "$CONTAINER" "$MAPPING"

    show_lsblk

    # 7) Format ext4
    echo "Formatage ext4…"
    mkfs.ext4 /dev/mapper/"$MAPPING"

    # 8) Montage
    echo "Montage sur $MOUNT_POINT…"
    mkdir -p "$MOUNT_POINT"
    mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"

    show_lsblk
    echo "[GOOD] Installé et monté sur $MOUNT_POINT"
}

open() {
    echo ">>> OPEN ENVIRONNEMENT <<<"
    show_lsblk
    [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur, lancez 'install'"; exit 1; }

    # Déverrouillage si nécessaire
    if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
        read -s -p "Password LUKS : " pass; echo
        cryptsetup open "$CONTAINER" "$MAPPING"
    else
        echo "  • Volume déjà déverrouillé"
    fi

    show_lsblk

    # Montage si besoin
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
    else
        echo "Déjà monté"
    fi

    show_lsblk
    echo "[GOOD] Monté sur $MOUNT_POINT"
}

close() {
    echo ">>> CLOSE ENVIRONNEMENT <<<"
    show_lsblk

    # Démontage si monté
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT"
    else
        echo "Rien à démonter"
    fi

    show_lsblk

    # Verrouillage si ouvert
    if [[ -e /dev/mapper/"$MAPPING" ]]; then
        cryptsetup close "$MAPPING"
    else
        echo "Déjà fermé"
    fi

    show_lsblk
    echo "[GOOD] Verrouillé et démonté"
}

usage() {
    echo "Usage: $0 {install|open|close}"
    exit 1
}

[[ $# -ne 1 ]] && usage
case "$1" in
    install) install ;;
    open)    open    ;;
    close)   close   ;;
    *) usage ;;
esac

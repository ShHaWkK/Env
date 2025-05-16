#!/bin/bash

set -euo pipefail
export PATH="$PATH:/sbin:/usr/sbin"

DEFAULT_SIZE="5G"
CONTAINER="$HOME/env_sec.img"      
MAPPING="env_sec"                 
MOUNT_POINT="$HOME/env_sec_mount"   

mkdir -p "$(dirname "$CONTAINER")"

install() {
    echo ">>> INSTALL ENVIRONNEMENT <<<"

    # choix de la taille
    read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " size
    size=${size:-$DEFAULT_SIZE}

    # mot de passe LUKS
    read -s -p "Password LUKS : " pass; echo
    read -s -p "Confirmer : "       pass2; echo
    [[ "$pass" != "$pass2" ]] && { echo "[Erreur] mots de passe différents"; exit 1; }

    # ne pas écraser
    [[ -f "$CONTAINER" ]] && { echo "[Erreur] $CONTAINER existe déjà"; exit 1; }

    # 4) création du fichier
    echo "Création de $CONTAINER de taille $size..."
    if command -v fallocate &>/dev/null; then
        fallocate -l "$size" "$CONTAINER"
    else
        if [[ "$size" =~ [Gg]$ ]]; then
            count=$(echo "${size%?}*1024" | bc)
        else
            count=${size%M}
        fi
        dd if=/dev/zero of="$CONTAINER" bs=1M count="$count" status=progress
    fi

    # chiffrement LUKS
    echo "Initialisation LUKS (tapez YES en majuscules)…"
    cryptsetup luksFormat "$CONTAINER"

    # ouverture du volume
    echo "Ouverture du volume chiffré…"
    cryptsetup open "$CONTAINER" "$MAPPING"

    # format ext4
    echo "Formatage ext4…"
    mkfs.ext4 /dev/mapper/"$MAPPING"

    # montage
    echo "Montage sur $MOUNT_POINT…"
    mkdir -p "$MOUNT_POINT"
    mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"

    echo "[GOOD] Installé et monté sur $MOUNT_POINT"
}

open() {
    echo ">>> OPEN ENVIRONNEMENT <<<"
    [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur, lancez 'install'"; exit 1; }

    # déverrouillage si nécessaire
    if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
        read -s -p "Password LUKS : " pass; echo
        cryptsetup open "$CONTAINER" "$MAPPING"
    else
        echo "  • Volume déjà déverrouillé"
    fi

    # montage si besoin
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
        echo "[GOOD] Monté sur $MOUNT_POINT"
    else
        echo "  • Déjà monté"
    fi
}

close() {
    echo ">>> CLOSE L'ENVIRONNEMENT  <<<"

    # démontage si monté
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT"
        echo "Démonté"
    else
        echo "Rien à démonter"
    fi

    # verrouillage si ouvert
    if [[ -e /dev/mapper/"$MAPPING" ]]; then
        cryptsetup close "$MAPPING"
        echo "[GOOD] Verrouillé"
    else
        echo "Déjà fermé"
    fi
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

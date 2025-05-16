#!/bin/bash

set -euo pipefail

DEFAULT_SIZE="500M"               # taille par défaut
CONTAINER="$HOME/env_sec.img"     # fichier conteneur
MAPPING="env_sec"                 # /dev/mapper/env_sec
MOUNT_POINT="$HOME/env_sec_mount" # point de montage

# crée le dossier parent si nécessaire
mkdir -p "$(dirname "$CONTAINER")"

install() {
    echo ">>> INSTALL ENV_SEC <<<"

    # 1. taille (défaut 500M)
    read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " size
    size=${size:-$DEFAULT_SIZE}

    # 2. mot de passe LUKS
    read -s -p "Mot de passe LUKS : " pass;   echo
    read -s -p "Confirmer : " pass2;         echo
    [[ "$pass" != "$pass2" ]] && { echo "[Erreur] mots de passe différents"; exit 1; }

    # 3. conteneur inexistant
    [[ -f "$CONTAINER" ]] && { echo "[Erreur] $CONTAINER existe déjà"; exit 1; }

    # 4. création fichier
    echo "Création du fichier $CONTAINER de taille $size..."
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

    # 5. chiffrement LUKS
    echo "Initialisation LUKS (tapez YES en majuscules)…"
    echo -n "$pass" | cryptsetup luksFormat "$CONTAINER" --key-file=-

    # 6. ouverture pour formater
    echo "Ouverture du volume…"
    echo -n "$pass" | cryptsetup open "$CONTAINER" "$MAPPING" --key-file=-

    # 7. format ext4
    echo "Formatage ext4…"
    mkfs.ext4 /dev/mapper/"$MAPPING"

    # 8. montage
    echo "Montage sur $MOUNT_POINT…"
    mkdir -p "$MOUNT_POINT"
    mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"

    echo "[GOOD] Installé et monté sur $MOUNT_POINT"
}

open() {
    echo ">>> OPEN ENV_SEC <<<"
    [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur, lancez 'install'"; exit 1; }

    # déverrouillage si nécessaire
    if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
        read -s -p "Passphrase LUKS : " pass; echo
        echo -n "$pass" | cryptsetup open "$CONTAINER" "$MAPPING" --key-file=-
    else
        echo "  • Volume déjà déverrouillé"
    fi

    # montage si nécessaire
    mkdir -p "$MOUNT_POINT"
    if ! mountpoint -q "$MOUNT_POINT"; then
        mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
        echo "[GOOD] Monté sur $MOUNT_POINT"
    else
        echo "  • Déjà monté"
    fi
}

close() {
    echo ">>> CLOSE ENV_SEC <<<"
    if mountpoint -q "$MOUNT_POINT"; then
        umount "$MOUNT_POINT"
        echo "  • Démonté"
    else
        echo "  • Rien à démonter"
    fi

    if [[ -e /dev/mapper/"$MAPPING" ]]; then
        cryptsetup close "$MAPPING"
        echo "[GOOD] Verrouillé"
    else
        echo "  • Déjà fermé"
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

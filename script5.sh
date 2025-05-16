#!/bin/bash
# Author  : ShHawk alias Alexandre Uzan
# Sujet : Environnement Sécurisé 

set -euo pipefail
export PATH="$PATH:/sbin:/usr/sbin"

# Vérifications  
(( EUID == 0 )) || { echo "[Erreur] exécuter en root"; exit 1; }
for cmd in cryptsetup mkfs.ext4 mount umount fallocate dd losetup lsblk df blkid; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "[Erreur] $cmd manquant"; exit 1; }
done

#Variables 
DEFAULT_SIZE="5G"
CONTAINER="$HOME/environnement.img"
LOOP_FILE="$HOME/environnement.loop"
MAPPING="environnement"
MOUNT_POINT="$HOME/environnement_mount"

# préparer dossiers
CONTAINER_DIR="${CONTAINER%/*}"
[[ -d "$CONTAINER_DIR" ]] || mkdir -p "$CONTAINER_DIR"
[[ -d "$MOUNT_POINT" ]]    || mkdir -p "$MOUNT_POINT"

#Affichages
show_lsblk() {
  echo; echo "=== lsblk ==="; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT; echo
}
show_df() {
  echo; echo "=== df -Th ==="; df -Th | grep -E "$MAPPING|Filesystem"; echo
}
show_blkid() {
  echo; echo "=== blkid /dev/mapper/$MAPPING ==="
  blkid /dev/mapper/"$MAPPING" 2>/dev/null || echo "(pas de mapping ouvert)"
  echo
}

#INSTALL
install() {
  echo ">>> INSTALL environnement <<<"
  show_lsblk

  read -p "Taille du conteneur (ex: 5G, 500M) [${DEFAULT_SIZE}] : " size
  size=${size:-$DEFAULT_SIZE}

  read -s -p "Passphrase LUKS : " pass; echo
  read -s -p "Confirmer la passphrase : " pass2; echo
  [[ "$pass" != "$pass2" ]] && { echo "[Erreur] mots de passe différents"; exit 1; }

  [[ -f "$CONTAINER" ]] && { echo "[Erreur] $CONTAINER existe déjà"; exit 1; }
  cryptsetup status "$MAPPING" &>/dev/null && { echo "[Erreur] /dev/mapper/$MAPPING existe déjà"; exit 1; }

  echo "Création de $CONTAINER de taille $size..."
  if fallocate -l "$size" "$CONTAINER" 2>/dev/null; then :; else
    if [[ "$size" =~ [Gg]$ ]]; then cnt=$(echo "${size%?}*1024" | bc); else cnt=${size%M}; fi
    dd if=/dev/zero of="$CONTAINER" bs=1M count="$cnt" status=progress
  fi
  show_lsblk

  echo "Attacher le fichier comme loop device..."
  loopdev=$(losetup --find --show "$CONTAINER")
  echo "$loopdev" > "$LOOP_FILE"
  show_lsblk

  echo "Initialisation LUKS (tapez YES)…"
  printf '%s' "$pass" | cryptsetup luksFormat --type luks1 --batch-mode "$loopdev" --key-file=-
  show_lsblk

  echo "Ouverture du volume…"
  printf '%s' "$pass" | cryptsetup open --type luks1 --key-file=- "$loopdev" "$MAPPING"
  show_lsblk

  echo "Formatage ext4…"
  mkfs.ext4 /dev/mapper/"$MAPPING"
  show_lsblk

  echo "Montage sur $MOUNT_POINT…"
  mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
  show_lsblk
  show_df
  show_blkid

  echo "[GOOD] environnement installé et monté sur $MOUNT_POINT"
}

#OPEN 
open() {
  echo ">>> OPEN environnement <<<"
  show_lsblk

  [[ ! -f "$CONTAINER" ]] && { echo "[Erreur] pas de conteneur, lancez 'install'"; exit 1; }

  if [[ ! -e /dev/mapper/"$MAPPING" ]]; then
    read -s -p "Passphrase LUKS : " pass; echo
    # rattacher loop si besoin
    if [[ -f "$LOOP_FILE" ]]; then
      loopdev=$(<"$LOOP_FILE")
    else
      loopdev=$(losetup --find --show "$CONTAINER")
      echo "$loopdev" > "$LOOP_FILE"
    fi
    printf '%s' "$pass" | cryptsetup open --type luks1 --key-file=- "$loopdev" "$MAPPING"
    echo "[GOOD] volume déverrouillé"
  else
    echo "mapping déjà déverrouillé"
  fi
  show_lsblk

  if ! mountpoint -q "$MOUNT_POINT"; then
    mount /dev/mapper/"$MAPPING" "$MOUNT_POINT"
    echo "[GOOD] monté sur $MOUNT_POINT"
  else
    echo "point de montage déjà utilisé"
  fi
  show_lsblk
  show_df
}

# CLOSE
close() {
  echo ">>> CLOSE environnement <<<"
  show_lsblk

  if mountpoint -q "$MOUNT_POINT"; then
    umount "$MOUNT_POINT"
    echo "[GOOD] démonté $MOUNT_POINT"
  else
    echo "rien à démonter"
  fi
  show_lsblk

  if cryptsetup status "$MAPPING" &>/dev/null; then
    cryptsetup close "$MAPPING"
    echo "[GOOD] verrouillé /dev/mapper/$MAPPING"
  else
    echo "mapping déjà fermé"
  fi
  show_lsblk

  if [[ -f "$LOOP_FILE" ]]; then
    loopdev=$(<"$LOOP_FILE")
    losetup -d "$loopdev"
    rm -f "$LOOP_FILE"
    echo "[GOOD] détaché $loopdev"
  fi
  show_lsblk
}

# DELETE
delete() {
  echo ">>> DELETE environnement <<<"
  close || true

  if [[ -f "$CONTAINER" ]]; then
    rm -f "$CONTAINER"
    echo "[GOOD] supprimé $CONTAINER"
  else
    echo "pas de fichier conteneur à supprimer"
  fi

  if [[ -d "$MOUNT_POINT" ]]; then
    rmdir "$MOUNT_POINT" 2>/dev/null && echo "[GOOD] supprimé $MOUNT_POINT"
  fi
  show_lsblk
}

usage() {
  echo "Usage: $0 {install|open|close|delete}"
  exit 1
}

[[ $# -ne 1 ]] && usage
case "$1" in
  install) install ;;
  open)    open    ;;
  close)   close   ;;
  delete)  delete  ;;
  *) usage ;;
esac

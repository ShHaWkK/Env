# Env

## commandes
ls /dev/ = > il peut servir un fichier de configuration de l'envirronment sécurisé 
- loop
dd id=/dev/zero of=env.img bs=2G count=5 

créer un fichier de 100 Mo, nommé « MonFichier.txt » (stocké dans le répertoire courant) et qui sera constitué de 100 000 blocs de 1 Ko. La seconde commande permet de lister le contenu du répertoire en affichant la taille sous une forme lisible.

- dd if=/dev/zero of=MonFichier.txt bs=1k count=100000

Le paramètre « bs » correspond à « block_size » c’est-à-dire la taille d’un bloc et, « count » au nombre de blocs de cette taille qu’on doit créer. En ce qui concerne « if=/dev/zero », on appelle comme fichier d’entrée un fichier spécial qui génère des caractères nuls. De ce fait, le fichier sera rempli de 0.
Créer un fichier taille définie sous Linux avec la commande dd

Partant de ce constant, nous pouvons jouer sur les paramètres "bs" et "count" pour atteindre le même résultat en créant un fichier avec un seul bloc de 100 Mo. Ce qui donnerait :

- dd if=/dev/zero of=MonFichier2.txt bs=100M count=1

Si vous cherchez à mesurer les performances d'un disque, vous pouvez utiliser la commande "dd" d'une autre façon qui consiste à ajouter le flag "oflag=direct". Voici comment effectuer un test avec 10 blocs de 1 Go :

- dd if=/dev/zero of=MonFichier.txt bs=1G count=10 oflag=direct

À la fin, vous allez obtenir le résultat (débit) directement dans la console :
Linux - Commande dd mesurer performances disque

Sachez que vous pouvez remplacer « /dev/zero » par "/dev/random" ou "/dev/urandom" pour remplir un fichier avec des nombres aléatoires, plutôt que d'utiliser des valeurs nulles.
 ls -lAshi 
 
losetup => permet d'afficher les loop de 0 à 10 
cryptsetup lucksClose crypt
losetup -d /dev/lopp0

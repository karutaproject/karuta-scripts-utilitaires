#!/bin/bash

# ./import_competences.sh $1
# .par ex. ./import_competences.sh "DROIT_L.csv"
# $1 : fichier csv à traiter

# Traitement d'un fichier csv (FILE_COMPETENCES) constitué d'une liste de compétences à importer.
# - instanciation d'une nouvelle composante basée sur la composante modèle des compétences, puis pour chaque ligne du fichier csv :
# - ajout de la compétence
#

## Pre-requis
# installer "dos2unix" et "xmlstarlet"

# Attention : il faut d'abord indiquer le mdp root dans le fichier xml/login.xml

# Plus d'infos sur l'API Karuta : https://github.com/karutaproject/karuta-backend/blob/master/Documentation/REST_API.md

#-----------------
# Base de données
#-----------------
SRV_DB=localhost              # Serveur de la base de donnée
USR_MARIADB=**user_mariadb**  # authentification : user mariadb
PWD_MARIADB=**pass_mariadb**  # authentification : password mariadb
DBN_MARIADB="karuta-backend"  # nom de la bdd karuta
DIR_DUMP="/home/karutabdd"    # répertoire pour la sauvegarde


#-------------
# COMPETENCES
#-------------
PROJECT_ID="ftlv"
PF_REFERENTIEL="$PROJECT_ID.referentiels"    # code du portfolio referentiel
SEMANTICTAG_REF_COMP="ref_comp_metiers"    # tag semantique de la rubrique 'Référentiel de compétences'  voulue dans le PF referentiel competences
PF_COMPOSANTES="$PROJECT_ID.composantes" # code du portfolio "Composantes réutilisables"


#----------------
# PARAMETRES CURL
#----------------
CURL="/usr/bin/curl --silent --show-error --noproxy"
DOMAIN_NAME=$HOSTNAME
CURL="$CURL $DOMAIN_NAME"
API_PATH="https://$DOMAIN_NAME/karuta-backend/rest/api"
COOKIE_FILEPATH="./tmp/cookies.txt"
CONTENT_TYPE='Content-type:application/xml'
#------------

XZ="/usr/bin/xz"
XMLSTARLET="/usr/bin/xmlstarlet"
MYSQLDUMP="/usr/bin/mysqldump"
DIR_COMPETENCES="./competences"    # dossier où sont situés les fichiers csv
FILE_COMPETENCES="$DIR_COMPETENCES/$1"
IMPORT_FILENAME="./tmp/data_import.csv"
LOG_FILENAME="import_competences.log"
DEBUG=true    # -> vers ./tmp/import_competences.log
#------------

# ajoute le texte en parametre au fichier de debug si DEBUG=true
debug() {
  if [ $DEBUG ]
  then
    echo ${1}>>./tmp/$LOG_FILENAME;
  fi
}

# affiche le texte en parametre sur la sortie principale + fichier debug
out() {
  debug ${1}
  echo ${1}
}

mkdir -p ./tmp
rm -f ./tmp/*


if test -z $1
then
  echo "Il manque le nom du fichier cible en argument lors de l'appel à ce script"
  exit
fi

# Conversion du fichier win->linux
#---------------------------------
dos2unix $FILE_COMPETENCES     # Suppression des ^M en fin de ligne
grep -v '^#' $FILE_COMPETENCES> $IMPORT_FILENAME    # Supp. ligne commentaire
# iconv -f ISO-8859-1 -t UTF-8  >$IMPORT_FILENAME <$FILE_COMPETENCES    # Gestion des car. accentués

# Avant tout, sauvegarde de la BDD :
#---------------------------------------
out "-> Sauvegarde BDD"
FORMATTED_DATE=`/bin/date +'%Y%m%d%H%M%S'`
$MYSQLDUMP --host=$SRV_DB --user=$USR_MARIADB --password=$PWD_MARIADB --databases $DBN_MARIADB | $XZ -9z >$DIR_DUMP/karuta-backend-$FORMATTED_DATE.sql.xz


# Connexion et récupération du cookie :
#-------------------------------------
out  "-> Connexion à Karuta"
$CURL -c $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/credential/login --data @./xml/login.xml>./tmp/response.xml

if [ ! -f $COOKIE_FILEPATH ]; then
  echo "Cookie not found!"
  exit
fi

echo  "Creation du referentiel"

# Recherche de l'id du PF qui contient les referentiels
pfcode_encode="${PF_REFERENTIEL// /%20}"
url_encode="$API_PATH/portfolios/portfolio/code/$pfcode_encode"
$CURL -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/response.xml
id_pf_referentiel=$(xmllint --xpath 'string(/portfolio/@id)' ./tmp/response.xml)
debug "-> id du PF referentiel=$id_pf_referentiel"

# Recupere un export du PF
$CURL -b $COOKIE_FILEPATH -X GET -k "$API_PATH/portfolios/portfolio/$id_pf_referentiel">./tmp/portfolio.xml

# Pretty print
$XMLSTARLET ed ./tmp/portfolio.xml>./tmp/portfolio1.xml

# on cherche l'id de la rubrique des ref. de competences
id_node_ref_competence=$(xmllint --xpath "string(//asmRoot/asmUnit/metadata[@semantictag='$SEMANTICTAG_REF_COMP']/../@id)" ./tmp/portfolio1.xml)
debug "-> id de la rubrique des ref. de compétences=$id_node_ref_competence"

# On crée une copie d'un noeud referentiel issu des composants réutilisables
# voir doc Karuta : /nodes/node/[copy|import]/{dest-id}?srcetag={semantictag}&srcecode={code}
# {dest-id} = uuid du noeud parent dans lequel coller l'élément
# {semantictag} = tag sémantique de l'élément à copier ( en prend un s'il y en a plusieurs)
# {code} = code du portfolio dans lequel chercher le tag sémantique
pfcompo_encode="${PF_COMPOSANTES// /%20}"
new_node_referentiel=$($CURL -b $COOKIE_FILEPATH -X POST -k "$API_PATH/nodes/node/copy/$id_node_ref_competence?srcetag=referentiel-generique&srcecode=$pfcompo_encode")
debug "-> id du nouveau ref. de compétences=$new_node_referentiel"

# Recupere un export du nouveau referentiel
$CURL -b $COOKIE_FILEPATH -X GET -k "$API_PATH/nodes/node/$new_node_referentiel">./tmp/referentiel.xml
# Renomme le semantictag :
sed -i "s/semantictag=\"referentiel-generique\"/semantictag=\"referentiel-metier\"/g" ./tmp/referentiel.xml


echo "----------------------------------------"
echo "-> TRAITEMENT DU FICHIER COMPETENCES ..."
echo "----------------------------------------"

# Import des compétences
#-----------------------
n_line=0
while IFS=';' read code_ref code_comp intitule_comp desc_comp
do line="$code_ref $code_comp $intitule_comp $desc_comp"

  case $n_line in
    # Traitement de la premiere ligne du fichier csv (parametres)
    0)
      CODE_REF="$code_ref@"
      TITRE_REF="$code_comp"

      # Change le code :
      sed -i "s/<code>REF_COMP@<\/code>/<code>$CODE_REF<\/code>/g" ./tmp/referentiel.xml
      # Change le titre :
      sed -i "s/<label lang=\"fr\">referentiel de compétences générique<\/label>/<label lang=\"fr\"> - $TITRE_REF<\/label>/g" ./tmp/referentiel.xml
      # On renvoie le referentiel modifié
      $CURL -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/nodes/node/$new_node_referentiel --data @./tmp/referentiel.xml>./tmp/response.xml
    ;;
    # on ne traite pas la 2e ligne (entetes)
    1)
      debug "-> ligne $n_line ignorée : $line"
    ;;
    # toutes les autres lignes sont des compétences
    *)
      out  "-> traitement de la ligne : $code_ref - $code_comp"

      # au préalable, je filtre les caractères "parasites"
      # a completer si necessaire ...
      intitule_comp=$(echo "$intitule_comp" | sed  s/'\/'/'\\\/'/g)  # '/' -> '\/'
      # Fin

      debug "----------------------------"
      debug "-> code_ref=$code_ref"
      debug "-> code_comp=$code_comp"
      debug "-> intitule_comp=$intitule_comp"
      # debug "-> desc_comp=$desc_comp"
      debug "----------------------------"

      # On crée une copie d'un noeud compétence issu des composants réutilisables
      new_node_competence=$($CURL -b $COOKIE_FILEPATH -X POST -k "$API_PATH/nodes/node/copy/$new_node_referentiel?srcetag=competence-generique&srcecode=$pfcompo_encode")

      if [[ $new_node_competence =~ "erreur" ]]
      then
        # erreur
        # possibilité : Subquery returns more than 1 row
        out "### erreur lors de la creation de la nouvelle compétence : $new_node_competence"
      else
        debug "-> nouveau noeud competence : $new_node_competence"

        # export XML de la compétence
        url_encode="$API_PATH/nodes/node/$new_node_competence"
        url_encode="${url_encode// /\%20}"
        $CURL -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/competence.xml

        # je change le code competence :
        # sed -i "s/<code>c97<\/code>/<code>@$prec_code_competence<\/code>/g" ./tmp/competence.xml
        # Change le label competence :
        sed -i "s/<label lang=\"fr\">Rubrique - intitulé compétence/<label lang=\"fr\">$intitule_comp/g" ./tmp/competence.xml
        # Renomme le semantictag :
        sed -i "s/semantictag=\"competence-generique\"/semantictag=\"competence-metier\"/g" ./tmp/competence.xml

        # On renvoie la compétences modifiée
        $CURL -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/nodes/node/$new_node_competence --data @./tmp/competence.xml>./tmp/response.xml
      fi
    ;;
  esac
  n_line=`expr $n_line + 1`
done < $IMPORT_FILENAME

# deconnexion :
#-------------
$CURL -b $COOKIE_FILEPATH -X POST -k $API_PATH/credential/logout
rm $COOKIE_FILEPATH
out "-> FIN du script. Déconnexion."
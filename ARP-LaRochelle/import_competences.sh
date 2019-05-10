#!/bin/bash

# ./import_competences.sh $1 $2 [$3]
# .par ex. ./import_competences.sh "DEG-L-DROIT.csv" "droit"
# $1 : fichier csv à traiter
# $2 : diplome (suffixe ajouté au code et libellé de l'instance)
# $3 : sauvegarde DB (1 par defaut)

# Traitement d'un fichier csv (FILE_COMPETENCES) constitué d'une liste
#   de compétences et Résultats d'acquisition.
# - instanciation d'une nouvelle composante basée sur la composante modèle des compétences,
#   puis pour chaque ligne du fichier csv :
# - ajout de la compétence et RA
#

## Pre-requis
# installer "dos2unix" et "xmlstarlet"


# Attention : il faut d'abord indiquer le mdp root dans le fichier xml/login.xml


#-----------------
# Base de données
#-----------------
DIR_MARIADB="/KarutaApps/apps/mariadb"  # répertoire bdd
SRV_DB=localhost                  # Serveur de la base de donnée
USR_MARIADB=**user_mariadb**      # authentification : user bdd
PWD_MARIADB=**password_mariadb**  # authentification : password bdd
DBN_MARIADB="karuta-backend"      # nom de la bdd karuta
DIR_DUMP="/KarutaData/_backup"    # répertoire pour la sauvegarde


#-------------
# COMPETENCES
#-------------
PROJECT_ID="portfolio-ARP"
PREFIX_CODE_COMPETENCES="competences"     #prefixe pour le code de la nouvelle composante
PREFIX_LABEL_COMPETENCES="Composante competences"     #prefixe pour le libellé de la nouvelle composante
LABEL_COMPETENCES="Composante competences"    # libellé de la Composante competences
TEMPLATE_COMPOSANTES="$PROJECT_ID.composante-competences"    # code de la Composante competences
SEMANTICTAG_MODELE_COMPOSANTE="Section-CompetencesDeLaFormation"    # tag semantic de 'Compétences de la formation' dans la Composante competences
CODE_MODELE_COMPETENCE="c999"     # code du modele de competence ('Ma compétence' dans la Composante competences)
DIPLOME=$2


#----------------
# PARAMETRES CURL
#----------------
DOMAIN_NAME=$HOSTNAME
API_PATH="https://$DOMAIN_NAME/karuta-backend/rest/api"
COOKIE_FILEPATH="/tmp/cookies.txt"
CONTENT_TYPE='Content-type:application/xml'
#------------

XZ="/usr/bin/xz"
MYSQLDUMP="/usr/bin/mysqldump"
DIR_COMPETENCES="./competences"    # dossier où sont situés les fichiers csv
FILE_COMPETENCES="$DIR_COMPETENCES/$1"
IMPORT_FILENAME="./tmp/data_import.csv"
LOG_FILENAME="import_competences.log"
DEBUG=true    #-> dans ./tmp/import_competences.log
debut_RA="\&lt;p\&gt;Liste des résultats d'apprentissage de cette compétence :\&lt;\\/p\&gt; \&lt;ul\&gt;"
fin_RA="\&lt;\\/ul\&gt;"
#------------


genpasswd() {
  local length=${1:-20}
  tr -dc A-Za-z0-9_ < /dev/urandom | head -c ${length} | xargs
}

debug() {
  if [ $DEBUG ]
  then
    echo ${1}>>./tmp/$LOG_FILENAME;
  fi
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
grep -v '^#' $FILE_COMPETENCES|iconv -f ISO-8859-1 -t UTF-8  > $IMPORT_FILENAME    # Supp. ligne commentaire + gestion des car. accentués

# Avant tout, sauvegarde de la bdd :
#---------------------------------------
save_db=$3
if test -z $save_db
then
  save_db=1
fi
if [ $save_db = 1 ]
then
  FORMATTED_DATE=`/bin/date +'%Y%m%d%H%M%S'`
  $MYSQLDUMP --host=$SRV_DB --user=$USR_MARIADB --password=$PWD_MARIADB --databases $DBN_MARIADB | $XZ -9z >$DIR_DUMP/karuta-backend-$FORMATTED_DATE.sql.xz
  debug "-> Sauvegarde BDD effectuée !"
fi

# Connexion et récupération du cookie :
#-------------------------------------
debug "-> Connexion"
curl --noproxy $DOMAIN_NAME -c $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/credential/login --data @./xml/login.xml>./tmp/response.xml

echo "----------------------------------------"
echo "-> TRAITEMENT DU FICHIER COMPETENCES ..."
echo "----------------------------------------"

# Recherche de l'id de la composante modele
url_encode="$API_PATH/portfolios/portfolio/code/$TEMPLATE_COMPOSANTES"
url_encode="${url_encode// /\%20}"
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/response.xml
id_composante_template=$(xmllint --xpath 'string(/portfolio/@id)' ./tmp/response.xml)
debug "-> id du modele composante=$id_composante_template "

# Copie de la composante modele
targetcode="$PROJECT_ID.$PREFIX_CODE_COMPETENCES $DIPLOME"

targetcode_encode="${targetcode// /\%20}"
debug "-> targetcode=$targetcode_encode"
id_new_composante=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/portfolios/copy/$id_composante_template?targetcode=$targetcode_encode&owner=true")
debug "-> id_new_composante copié=$id_new_composante"
debug "-> en retour=$?"

# Je change quelques infos sur la copie :
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/portfolios/portfolio/$id_new_composante">./tmp/portfolio.xml
# le titre :
sed -i "s/<label lang=\"fr\">$LABEL_COMPETENCES/<label lang=\"fr\">$PREFIX_LABEL_COMPETENCES $DIPLOME/g" ./tmp/portfolio.xml
# Le label de la section compétences :
string_to_replace=$(xmllint --xpath "string(//asmStructure[metadata/@semantictag='$SEMANTICTAG_MODELE_COMPOSANTE']/asmResource[1]/label[@lang='fr'])" ./tmp/portfolio.xml)
sed -i "s/$string_to_replace/Compétences $DIPLOME/g" ./tmp/portfolio.xml
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/portfolios/portfolio/$id_new_composante --data @./tmp/portfolio.xml>./tmp/response.xml

# Pour la gestion des sauts de ligne :
xml ed ./tmp/portfolio.xml>./tmp/portfolio1.xml

prec_code_competence=""
prec_libelle_competence=""
id_node_parent_modele_competence=$(xmllint --xpath "string(//asmRoot/asmStructure/metadata[@semantictag='$SEMANTICTAG_MODELE_COMPOSANTE']/../@id)" ./tmp/portfolio1.xml)
debug "-> id_node_parent_modele_competence=$id_node_parent_modele_competence"

# Structure modèle de compétence :
id_node_modele_competence=$(xmllint --xpath "string(//asmResource[code='$CODE_MODELE_COMPETENCE']/../@id)" ./tmp/portfolio1.xml)
debug "-> id_node_modele_competence=$id_node_modele_competence"

# Import des compétences
#------
while IFS=';' read c_rubrique c_competence c_RA unused1 unused2 unused3 libelle
do line="$c_rubrique $c_competence $c_RA $unused1 $unused2 $unused3 $libelle"
  debug "-> traitement de la ligne : $line"
  echo "traitement de la ligne : $line"

  # au préalable, je filtre les caractères "parasites"
  # a completer si necessaire ...
  libelle=$(echo "$libelle" | sed  s/'\/'/'\\\/'/g)  # '/' -> '\/'
  # Fin

  # RA = Résultat d'apprentissage. Chaque compétence contient un certain nombre de RA.
  libelle_RA=""
  libelle_competence=""
  # Si ce n'est pas un RA
  if test -z $c_RA
  then
    # c_competence indique le code de la compétence
    if test -z $c_competence
    then
      continue
    else
      libelle_competence=$libelle
      code_competence=$c_rubrique.$c_competence
    fi
  else
    libelle_RA=$libelle
    code_RA=$c_rubrique.$c_RA
  fi


  debug "-> code_rubrique=$c_rubrique"
  debug "-> code_competence=$code_competence"
  debug "-> code_RA=$code_RA"
  debug "-> libelle=$libelle"

  case $prec_code_competence in
    "")
      # premiere iteration de $prec_code_competence
      prec_code_competence=$c_rubrique.$c_competence
      prec_libelle_competence=$libelle_competence
      liste_RA=$debut_RA
      ;;
      # $prec_code_competence existe et on est en train d'ajouter une nouvelle RA
    $code_competence)
      liste_RA=$liste_RA"\&lt;li\&gt;"$libelle_RA"\&lt;\\/li\&gt;"
      ;;
    *)
      # $prec_code_competence existe mais c'est un nouveau code :
      # on finalise donc la compétences précédente.
      # je duplique le noeud competence :
      new_node_competence=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/nodes/node/copy/"$id_node_parent_modele_competence"?srcetag=ModeleCompetence-etudiant&srcecode=$CODE_MODELE_COMPETENCE")
      if [[ $new_node_competence =~ "erreur" ]]
      then
        # erreur
        debug "-> erreur lors de la creation de la nouvelle compétence"
      else
        debug "-> nouveau noeud competence : $new_node_competence"

        # COMPETENCE
        url_encode="$API_PATH/nodes/node/$new_node_competence"
        url_encode="${url_encode// /\%20}"
        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/competence.xml

        # je change le code competence :
        sed -i "s/<code>c97<\/code>/<code>@$prec_code_competence<\/code>/g" ./tmp/competence.xml
        # je change le label competence :
        sed -i "s/<label lang=\"fr\">Ma compétence/<label lang=\"fr\">$prec_libelle_competence/g" ./tmp/competence.xml

        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/nodes/node/$new_node_competence --data @./tmp/competence.xml>./tmp/response.xml

        # RESULTAT D'ACQUISITION
        # je repere l'id resource RA pour la maj :
        contextid_node_ra=$(xmllint --xpath "string(//asmResource[code='codelisteRA']/@contextid)" ./tmp/competence.xml)
        debug "-> id resource RA=$contextid_node_ra"
        url_encode="$API_PATH/resources/resource/$contextid_node_ra"
        url_encode="${url_encode// /\%20}"
        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/ra.xml

        # On ferme les balises ouvertes dans liste_RA
        liste_RA=$liste_RA$fin_RA
        # je change le label des RAs :
        sed -i "s/<text lang=\"fr\">Liste des RA/<text lang=\"fr\">$liste_RA/g" ./tmp/ra.xml

        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/resources/resource/$contextid_node_ra --data @./tmp/ra.xml>./tmp/response2.xml
        fi
      prec_code_competence=$c_rubrique.$c_competence
      prec_libelle_competence=$libelle_competence
      liste_RA=$debut_RA
      ;;
  esac

done < $IMPORT_FILENAME

# Traitement pour la dernière compétence :
#----------------------------------------
# je duplique le noeud competence :
new_node_competence=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/nodes/node/copy/"$id_node_parent_modele_competence"?srcetag=ModeleCompetence-etudiant&srcecode=c97")

if [[ $new_node_competence =~ "erreur" ]]
then
  # erreur
  debug "-> erreur lors de la creation de la nouvelle compétence"
else
  debug "-> nouveau noeud competence : $new_node_competence"

  # COMPETENCE
  url_encode="$API_PATH/nodes/node/$new_node_competence"
  url_encode="${url_encode// /\%20}"
  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/competence.xml

  # je change le code competence :
  sed -i "s/<code>c97<\/code>/<code>@$prec_code_competence<\/code>/g" ./tmp/competence.xml
  # je change le label competence :
  sed -i "s/<label lang=\"fr\">Ma compétence/<label lang=\"fr\">$prec_libelle_competence/g" ./tmp/competence.xml

  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/nodes/node/$new_node_competence --data @./tmp/competence.xml>./tmp/response.xml

  # RESULTAT D'ACQUISITION
  # je repere l'id resource RA pour la maj
  contextid_node_ra=$(xmllint --xpath "string(//asmResource[code='codelisteRA']/@contextid)" ./tmp/competence.xml)
  url_encode="$API_PATH/resources/resource/$contextid_node_ra"
  url_encode="${url_encode// /\%20}"
  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/ra.xml

  # On ferme les balises ouvertes dans liste_RA
  liste_RA=$liste_RA$fin_RA
  # Maj du label des RAs
  sed -i "s/<text lang=\"fr\">Liste des RA/<text lang=\"fr\">$liste_RA/g" ./tmp/ra.xml

  debug "-> id resource RA=$contextid_node_ra"
  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/resources/resource/$contextid_node_ra --data @./tmp/ra.xml>./tmp/response2.xml
fi

# suppression de la competence modele :
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X DELETE -k $API_PATH/nodes/node/$id_node_modele_competence

# deconnexion :
#-------------
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k $API_PATH/credential/logout

rm $COOKIE_FILEPATH
# rm users.xml

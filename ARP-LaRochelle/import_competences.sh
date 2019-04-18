#!/bin/bash

# ./import_competences.sh $1 $2 [$3]
# .par ex. ./import_competences.sh "DEG-L-DROIT.csv" "droit"
# $1 : fichier xml à traiter
# $2 : diplome (suffixe ajouté au code et libellé de l'instance)
# $3 : sauvegarde DB (1 par defaut)

# Traitement d'un fichier xml (FILE_COMPETENCES) constitué d'une liste de compétences et Résultats d'acquisition.
# - instanciation d'une nouvelle composante basée sur la composante modèle des compétences, puis pour chaque ligne du fichier xml :
# - ajout de la compétence et RA
#-------------------------------
# nécessite xmlstarlet

#------------
# MARIADB
#------------
DIR_MARIADB="/KarutaApps/apps/mariadb"  #répertoire mariadb
PWD_MARIADB=**password_mariadb**      #authentification : password mariadb
USR_MARIADB=**user_mariadb**        #authentification : user mariadb
DBN_MARIADB="karuta-backend"      #inom de la database karuta
DIR_DUMP="/KarutaData/_backup"    # répertoire pour le backup
#------------

#-------------
# COMPETENCES
#-------------
PREFIX_CODE_COMPETENCES="competences"     #prefixe pour le code de la nouvelle composante
PREFIX_LABEL_COMPETENCES="Composante competences"     #prefixe pour le libellé de la nouvelle composante
LABEL_COMPETENCES="Composante competences"    #libellé de la Composante competences
TEMPLATE_COMPOSANTES="portfolio-ARP.composante-competences"    #code de la Composante competences
SEMANTICTAG_MODELE_COMPOSANTE="Section-CompetencesDeLaFormation"    #tag semantic de 'Compétences de la formation' dans la Composante competences
CODE_MODELE_COMPETENCE="c999"     #code du modele de competence ('Ma compétence' dans la Composante competences)
DIPLOME=$2
#------------

#----------------
# PARAMETRES CURL
#----------------
DOMAIN_NAME=$HOSTNAME
API_PATH="https://$DOMAIN_NAME/karuta-backend/rest/api"
COOKIE_FILEPATH="/tmp/cookies.txt"
CONTENT_TYPE='Content-type:application/xml'
#------------

XZ="/usr/bin/xz"
DIR_COMPETENCES="./competences"    #dossier ou sont situés les fichiers xml
FILE_COMPETENCES="$DIR_COMPETENCES/$1"
IMPORT_FILENAME="./tmp/data_import.csv"
LOG_FILENAME="import_competences.log"
DEBUG=true    #-> dans ./tmp/import_competences.log
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


# Convertion du fichier win->linux
#---------------------------------
dos2unix $FILE_COMPETENCES     #suppression des ^M en fin de ligne
grep -v '^#' $FILE_COMPETENCES|iconv -f ISO-8859-1 -t UTF-8  > $IMPORT_FILENAME    #supp. ligne commentaire + gestion des car. accentués

#Avant tout, sauvegarde de la database :
#---------------------------------------
save_db=$3
if test -z $save_db
then
  save_db=1
fi
if [ $save_db = 1 ]
then
  FORMATTED_DATE=`/bin/date +'%Y%m%d%H%M%S'`
  MYSQL_PWD=$PWD_MARIADB $DIR_MARIADB/bin/mysqldump --user $USR_MARIADB --databases $DBN_MARIADB | $XZ -9z >$DIR_DUMP/karuta-backend-import-$FORMATTED_DATE.sql.xz
  debug "-> Sauvegarde DB effectuée !"
fi

#connexion et récupération du cookie :
#-------------------------------------
debug "-> Connexion"
curl --noproxy $DOMAIN_NAME -c $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/credential/login --data @./xml/login.xml>./tmp/response.xml

echo "----------------------------------------"
echo "-> TRAITEMENT DU FICHIER COMPETENCES ..."
echo "----------------------------------------"

#recherche de l'id de la composante modele
url_encode="$API_PATH/portfolios/portfolio/code/$TEMPLATE_COMPOSANTES"
url_encode="${url_encode// /\%20}"
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/response.xml
id_composante_template=$(xmllint --xpath 'string(/portfolio/@id)' ./tmp/response.xml)
debug "-> id du modele composante=$id_composante_template "

#-copie de la composante modele
targetcode="portfolio-ARP.$PREFIX_CODE_COMPETENCES $DIPLOME"
targetcode_encode="${targetcode// /\%20}"
debug "-> targetcode=$targetcode_encode"
id_new_composante=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/portfolios/copy/$id_composante_template?targetcode=$targetcode_encode&owner=true")
debug "-> id_new_composante copié=$id_new_composante"
debug "-> en retour=$?"

#-je change quelques infos sur la copie :
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/portfolios/portfolio/$id_new_composante">./tmp/portfolio.xml
sed -i "s/<label lang=\"fr\">$LABEL_COMPETENCES/<label lang=\"fr\">$PREFIX_LABEL_COMPETENCES $DIPLOME/g" ./tmp/portfolio.xml
#le label de la section compétences :
string_to_replace=$(xmllint --xpath "string(//asmStructure[metadata/@semantictag='$SEMANTICTAG_MODELE_COMPOSANTE']/asmResource[1]/label[@lang='fr'])" ./tmp/portfolio.xml)
sed -i "s/$string_to_replace/Compétences $DIPLOME/g" ./tmp/portfolio.xml
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/portfolios/portfolio/$id_new_composante --data @./tmp/portfolio.xml>./tmp/response.xml

#pour la gestion des sauts de ligne :
xml ed ./tmp/portfolio.xml>./tmp/portfolio1.xml

prec_code_competence=""
prec_libelle_competence=""
id_node_parent_modele_competence=$(xmllint --xpath "string(//asmRoot/asmStructure/metadata[@semantictag='$SEMANTICTAG_MODELE_COMPOSANTE']/../@id)" ./tmp/portfolio1.xml)
debug "-> id_node_parent_modele_competence=$id_node_parent_modele_competence"

#Structure modèle de compétence :
id_node_modele_competence=$(xmllint --xpath "string(//asmResource[code='$CODE_MODELE_COMPETENCE']/../@id)" ./tmp/portfolio1.xml)
debug "-> id_node_modele_competence=$id_node_modele_competence"

#import
#------
while IFS=';' read c_rubrique c_competence c_RA unused1 unused2 unused3 libelle
do line="$c_rubrique $c_competence $c_RA $unused1 $unused2 $unused3 $libelle"
  debug "-> traitement de la ligne : $line"
  echo "traitement de la ligne : $line"

  #au préalable, je filtre les caractères "parasites"
  #a completer si necessaire ...
  libelle=$(echo "$libelle" | sed  s/'\/'/'\\\/'/g)  # '/' -> '\/'
  #Fin


  libelle_RA=""
  libelle_competence=""
  if test -z $c_RA
  then
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
      prec_code_competence=$c_rubrique.$c_competence
      prec_libelle_competence=$libelle_competence
      liste_RA="Liste des résultats d'apprentissage de cette compétence :\&lt;br\&gt;\&lt;br\&gt;\&lt;div\&gt; \&lt;ul\&gt;"
      ;;
    $code_competence)
      liste_RA=$liste_RA"\&lt;li\&gt;"$libelle_RA"\&lt;\\/li\&gt;"
      ;;
    *)
      #je duplique le noeud competence :
      new_node_competence=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/nodes/node/copy/"$id_node_parent_modele_competence"?srcetag=ModeleCompetence-etudiant&srcecode=$CODE_MODELE_COMPETENCE")
      if [[ $new_node_competence =~ "erreur" ]]
      then
        #erreur
        debug "-> erreur lors de la creation de la nouvelle compétence"
      else
        debug "-> nouveau noeud competence : $new_node_competence"

        #COMPETENCE
        url_encode="$API_PATH/nodes/node/$new_node_competence"
        url_encode="${url_encode// /\%20}"
        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/competence.xml

        #je change le code competence :
        sed -i "s/<code>c97<\/code>/<code>@$prec_code_competence<\/code>/g" ./tmp/competence.xml
        #je change le label competence :
        sed -i "s/<label lang=\"fr\">Ma compétence/<label lang=\"fr\">$prec_libelle_competence/g" ./tmp/competence.xml

        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/nodes/node/$new_node_competence --data @./tmp/competence.xml>./tmp/response.xml

        #RESULTAT D'ACQUISITION
        #je repere l'id resource RA pour la maj :
        contextid_node_ra=$(xmllint --xpath "string(//asmResource[code='codelisteRA']/@contextid)" ./tmp/competence.xml)
        debug "-> id resource RA=$contextid_node_ra"
        url_encode="$API_PATH/resources/resource/$contextid_node_ra"
        url_encode="${url_encode// /\%20}"
        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/ra.xml

        #je change le label des RAs :
        liste_RA=$liste_RA"\&lt;\\/ul\&gt;\&lt;\\/div\&gt;"
        sed -i "s/<text lang=\"fr\">Liste des RA/<text lang=\"fr\">$liste_RA/g" ./tmp/ra.xml

        curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/resources/resource/$contextid_node_ra --data @./tmp/ra.xml>./tmp/response2.xml
        fi
      prec_code_competence=$c_rubrique.$c_competence
      prec_libelle_competence=$libelle_competence
      liste_RA="Liste des résultats d'apprentissage de cette compétence :\&lt;br\&gt;\&lt;br\&gt;\&lt;div\&gt; \&lt;ul\&gt;"
      ;;
  esac

done < $IMPORT_FILENAME

#Traitement pour la dernière compétence :
#----------------------------------------
#je duplique le noeud competence :
new_node_competence=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/nodes/node/copy/"$id_node_parent_modele_competence"?srcetag=ModeleCompetence-etudiant&srcecode=c97")

if [[ $new_node_competence =~ "erreur" ]]
then
  #erreur
  debug "-> erreur lors de la creation de la nouvelle compétence"
else
  debug "-> nouveau noeud competence : $new_node_competence"

  #COMPETENCE
  url_encode="$API_PATH/nodes/node/$new_node_competence"
  url_encode="${url_encode// /\%20}"
  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/competence.xml

  #je change le code competence :
  sed -i "s/<code>c97<\/code>/<code>@$prec_code_competence<\/code>/g" ./tmp/competence.xml
  #je change le label competence :
  sed -i "s/<label lang=\"fr\">Ma compétence/<label lang=\"fr\">$prec_libelle_competence/g" ./tmp/competence.xml

  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/nodes/node/$new_node_competence --data @./tmp/competence.xml>./tmp/response.xml

  #RESULTAT D'ACQUISITION
  #je repere l'id resource RA pour la maj :
  contextid_node_ra=$(xmllint --xpath "string(//asmResource[code='codelisteRA']/@contextid)" ./tmp/competence.xml)
  url_encode="$API_PATH/resources/resource/$contextid_node_ra"
  url_encode="${url_encode// /\%20}"
  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/ra.xml

  #je change le label des RAs :
  liste_RA=$liste_RA"\&lt;\\/ul\&gt;\&lt;\\/div\&gt;"
  sed -i "s/<text lang=\"fr\">Liste des RA/<text lang=\"fr\">$liste_RA/g" ./tmp/ra.xml

  debug "-> id resource RA=$contextid_node_ra"
  curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/resources/resource/$contextid_node_ra --data @./tmp/ra.xml>./tmp/response2.xml
fi

#suppression de la competence modele :
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X DELETE -k $API_PATH/nodes/node/$id_node_modele_competence

#deconnexion :
#-------------
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k $API_PATH/credential/logout

rm $COOKIE_FILEPATH
#rm users.xml


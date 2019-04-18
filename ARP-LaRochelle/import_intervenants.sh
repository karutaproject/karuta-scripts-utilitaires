#!/bin/bash

# APPEL :
# ./import_intervenants [1]
# $1 : sauvegarde MARIADB 0/1 (1 par defaut)

# Traitement d'un fichier xml (FILE_INTERVENANTS) constitué d'une liste d'intervenants. Pour chaque intervenant :
# - création du compte intervenant karuta
# - envoi d'un mail de creation de compte aux intervenants exterieurs à l'établissement
# - ajout de ce compte à un groupe intervenant (par domaine)
# - cwgénération d'un fichier des intervenants par domaine (utile pour reconstituer les partages de groupes)
#----------------------
# nécessite xmlstarlet

#------------
# MARIADB
#------------
DIR_MARIADB="/KarutaApps/apps/mariadb"  #répertoire mariadb
PWD_MARIADB=**password_mariadb**        #authentification : password mariadb
USR_MARIADB=**user_mariadb**            #authentification : user mariadb
DBN_MARIADB="karuta-backend"            #inom de la database karuta
DIR_DUMP="/KarutaData/_backup"          # répertoire pour le backup
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
DIR_INTERVENANTS="./intervenants"
FILE_INTERVENANTS="$DIR_INTERVENANTS/intervenants.csv"
IMPORT_FILENAME="./tmp/data_import.csv"
LOG_FILENAME="import_intervenant.log"
DEBUG=true    #-> dans ./tmp/import_intervenant.log
#------------

#----------------
# MAIL DE CONFIRMATION POUR LES COMPTES EXTERNES
#----------------
SEND_MAIL_NEW_USER=true  #on envoi/ou pas un mail de création de compte
NO_REPLY="noreply@univ.fr"   #email expéditeur
TEST_TO_EMAIL=""   #email destinataire pour tester sinon laisser vide
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


encode_targetcode()
{
  local chaine="${1}"
  chaine=${chaine//é/e}
  chaine=${chaine//è/e}
  chaine=${chaine//ê/e}
  chaine=${chaine//î/i}
  chaine=${chaine//à/a}
  chaine=${chaine//â/a}
  chaine=${chaine//ç/c}
  chaine=${chaine//É/E}
  chaine=${chaine//É/E}
  chaine=${chaine//È/E}
  chaine=${chaine//Ê/E}
  chaine=${chaine//Ç/C}
  chaine=${chaine//Î/I}
  chaine=${chaine//Â/A}
  chaine=${chaine//À/A}
  echo ${chaine}
}

mkdir -p ./tmp
rm -f ./tmp/*

#sauvegarde eventuelle de ma database :
#--------------------------------------
save_db=$1
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
echo "-> Connexion"
curl --noproxy $DOMAIN_NAME -c $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/credential/login --data @./xml/login.xml>./tmp/response.xml


echo "-----------------------------------------"
echo "-> TRAITEMENT DU FICHIER UTILISATEURS ..."
echo "-----------------------------------------"

# Convertion du fichier win->linux
#---------------------------------
dos2unix $FILE_INTERVENANTS     #suppression des ^M en fin de ligne
grep -v '^#' $FILE_INTERVENANTS|iconv -f ISO-8859-1 -t UTF-8  > $IMPORT_FILENAME    #supp. ligne commentaire + gestion des car. accentués

#init. rep. de travail intervenant
rm -Rf $DIR_INTERVENANTS/data/*
mkdir $DIR_INTERVENANTS/data


while IFS=';' read domaine lastname firstname email username
do line="$domaine $lastname $firstname $email $username"
  debug "-> traitement de la ligne : $line"
  echo "traitement de la ligne : $line"

  #-je verifie si l'utilisateur existe
  #--------------------------------------
  id_user=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k -H $CONTENT_TYPE $API_PATH/users/user/username/$username)

  if [[ $id_user =~ "not found" ]]
  then
    #n'existe pas, je le créé
    cp ./xml/template_users.xml ./tmp/users.xml
    pwd_user=`genpasswd 10`
    sed -i "s/\[username\]/$username/g" ./tmp/users.xml
    sed -i "s/\[pwd\]/$pwd_user/g" ./tmp/users.xml
    sed -i "s/\[firstname\]/$firstname/g" ./tmp/users.xml
    sed -i "s/\[lastname\]/$lastname/g" ./tmp/users.xml
    sed -i "s/\[email\]/$email/g" ./tmp/users.xml

    debug "-> pwd_user=$pwd_user"
    fichierDomaineLower=$(echo "$DIR_INTERVENANTS/data/$domaine.xml" | awk '{print tolower($0)}')

    debug "-> Import du fichier ./tmp/users.xml"
    curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/users --data @./tmp/users.xml>./tmp/response.xml

    #je recupere l'id du user créé :
    id_user=$(xmllint --xpath 'string(/users/user/@id)' ./tmp/response.xml)
    debug "-> création de l'utilisateur $username "

    #envoi auto. d'un email pour la création de compte des utilisateurs exterieurs à l'établissement :
    if $SEND_MAIL_NEW_USER && [[ "$username" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,4}$ ]]
    then
      rm -f ./tmp/new_user.eml
      cp ./xml/template_mail_new_user.eml ./tmp/new_user.eml
      sed -i "s/\[login\]/$username/g" ./tmp/new_user.eml
      sed -i "s/\[mdp\]/$pwd_user/g" ./tmp/new_user.eml
      if test -z $TEST_TO_EMAIL
      then
        cat ./tmp/new_user.eml |mail -r $NO_REPLY -s "Compte Karuta" $email
      else
        cat ./tmp/new_user.eml |mail -r $NO_REPLY -s "Compte Karuta" $TEST_TO_EMAIL
      fi
    fi
  else
    debug "-> utilisateur $id_user existant"
  fi
    #je verifie l'existence du fichier 'domaine'.xml
    fichierDomaine=$(echo "$DIR_INTERVENANTS/data/$domaine.xml" | awk '{print tolower($0)}')

    if [ -f $fichierDomaine ]; then
      debug "-> $fichierDomaine existe"
    else
      touch $fichierDomaine
      #balise de début de bloc
      echo "<users>" > $fichierDomaine
    fi

    if test -z $id_user
    then
      debug "-> id_user vide, je passe au suivant"
    else
      echo "<user id='$id_user'/>" >> $fichierDomaine

      #- si nécessaire, j'ajoute ce user au groupe d'utilisateur xxx :
      groupe_utilisateur="intervenant "$domaine
      #je recherche le groupe d'utilisateur
      curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $API_PATH/usersgroups > ./tmp/response.xml
      group_id=$(xmllint --xpath "string(//group[label='$groupe_utilisateur']/@id)" ./tmp/response.xml)

      debug "-> recherche group_id=$group_id"
      if test -z $group_id
      then
        debug "-> je créé ..."
        group_id=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -G $API_PATH/usersgroups --data-urlencode "label=$groupe_utilisateur")
      else
        debug "-> deja trouvé"
      fi
      debug "-> group_id=$group_id"

      #je l'ajoute au groupe utilisateur :
      debug "-> Ajout du user $id_user au groupe utilisateur $group_id"
      curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k "$API_PATH/usersgroups?group=$group_id&user=$id_user">./tmp/response.xml
      #-------------------------------------------------------
  fi

done < $IMPORT_FILENAME

#balise de fin de bloc :
list=`ls $DIR_INTERVENANTS/data/*.xml`
for fichierDomaine in $list
do
  debug "-> ajout dans $fichierDomaine"
  echo "</users>" >> $fichierDomaine
done

#deconnexion :
#-------------
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k $API_PATH/credential/logout

rm $COOKIE_FILEPATH

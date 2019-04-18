#!/bin/bash

# APPEL :
# ./import_utilisateurs [1]
# $1 : sauvegarde MARIADB 0/1 (1 par defaut)
#----------------------

# Traitement d'un fichier xml (FILE_USERS) constitué d'une liste d'etudiants :
# - création du compte etudiant karuta
# - ajout de ce compte  à un groupe étudiants (par niveau du diplome)
# - instanciation du portfolio étudiant et affectation par défaut d'une liste de compétences
# - ajout de l'instance à un groupe de projets iet à un groupe de portfolios (par diplome)
# - partage avec les usagers (role etudiant et enseignant)
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

#------------
# PORTFOLIO
#------------
TEMPLATE_PORTFOLIO_PROJECT="portfolio-ARP"  #Nom du projet dans Karuta
TEMPLATE_CODE_PORTFOLIO="modele"   #Code du portfolio de référence (sans le préfixe projet)
ROLE_ALL="all"
ROLE_STUDENT="etudiant"
ROLE_TEACHER="enseignant"
LABEL_FR_PORTFOLIO="portfolio de"   #prefixe FR du libellé de l'instance portfolio
LABEL_EN_PORTFOLIO="' portfolio"    #prefixe EN du libellé de l'instance portfolio
PREFIX_CODE_COMPETENCES="competences"               #prefixe du code des composantes competences
PREFIX_LABEL_COMPETENCES="Composante competences"   #prefixe du libellé des composantes competences
TMP_COPY="$TEMPLATE_PORTFOLIO_PROJECT.copie tempo"  #copie de travail
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
DIR_USERS="./utilisateurs"     #dossier ou sont situés les fichiers xml
FILE_USERS="$DIR_USERS/utilisateurs.csv"
IMPORT_FILENAME="./tmp/data_import.csv"
LOG_FILENAME="import_utilisateurs.log"
DEBUG=true    #-> dans ./tmp/import_utilisateurs.log
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
debug "-> Connexion"
curl --noproxy $DOMAIN_NAME -c $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/credential/login --data @./xml/login.xml>./tmp/response.xml



#---------------------------------------
#- Partie 1 : CREATION DU PORTFOLIO
#---------------------------------------

# Convertion du fichier win->linux
#---------------------------------
dos2unix $FILE_USERS     #suppression des ^M en fin de ligne
grep -v '^#' $FILE_USERS|iconv -f ISO-8859-1 -t UTF-8  > $IMPORT_FILENAME    #supp. ligne commentaire + gestion des car. accentués



#import
#------
#- A noter que role=0->etudiant   role=1->intervenant
while IFS=';' read username studentid firstname lastname birthdate email role diplome
do line="$username $studentid $firstname $lastname $birthdate $email $role $diplome"
	debug "-> traitement de la ligne : $line"
	echo "traitement de la ligne : $line"

	#Suppression des "." dans le diplome, sinon ca cafouille ... :
	diplome=$(echo "$diplome" | sed  s/'\.'/''/g)
	#suppression des eventuels espaces en fin de chaine :
	diplome=`echo "$diplome" | sed -e "s/ *$//"`
	debug "-> diplome=$diplome"
	debug "-> role=$role"

	# on a choisi de regrouper les comptes utilisateurs par niveau d'etude
	#---------------------------------------------------------------------
	# le libellé du diplome contient le niveau d'etude (L1, L2, ...)
	case $diplome in
		*' L1 '* ) user_group="l1"
			;;
		*' L2 '* ) user_group="l2"
			;;
		* ) user_group="";;
	esac


	#recherche de l'id du modèle projet Karuta
	url_encode="$API_PATH/portfolios/portfolio/code/karuta.project"
	url_encode="${url_encode// /\%20}"
	curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/response.xml
	id_projet_karuta=$(xmllint --xpath 'string(/portfolio/@id)' ./tmp/response.xml)
	debug "-> id_projet_karuta=$id_projet_karuta "

	# Les projets des portfolios correspondent aux diplomes
	#-------------------------------------------------------
	portfolio_project_encode=`encode_targetcode "$diplome"`
	#- creation du projet :
	id_portfolio_project=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -G $API_PATH/portfolios/copy/$id_projet_karuta --data-urlencode "targetcode=$portfolio_project_encode" --data-urlencode "owner=true")
	debug "-> id_portfolio_project=$id_portfolio_project"

	if [[ $id_portfolio_project =~ "code exist" ]]
	then
		debug "-> groupe projet $diplome existant"
		exist_project=false;
	else
		#-modification du label projet
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $API_PATH/portfolios/portfolio/$id_portfolio_project > ./tmp/portfoliotest.xml
		xml ed -u "portfolio/asmRoot/asmResource/label[@lang='fr']" -v "Diplome $diplome" ./tmp/portfoliotest.xml>./tmp/portfoliotest2.xml
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/portfolios/portfolio/$id_portfolio_project --data @./tmp/portfoliotest2.xml>./tmp/response.xml
		exist_project=true;
	fi


	# De même, les groupes de portfolios correspondent aux diplomes
	#---------------------------------------------------------------
	curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $API_PATH/portfoliogroups > ./tmp/response.xml
	id_portfolio_group=$(xmllint --xpath "string(//group[label='$diplome']/@id)" ./tmp/response.xml)

  if test -z $id_portfolio_group
	then
		debug "-> je créé le groupe de portfolio $diplome ..."
		id_portfolio_group=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -G $API_PATH/portfoliogroups --data-urlencode "type=portfolio" --data-urlencode "label=$diplome")
	else
		debug "-> groupe portfolio $diplome existant"
	fi
	debug "-> id_portfolio_group=$id_portfolio_group"


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
		debug "-> Import du fichier ./tmp/users.xml"

 		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/users --data @./tmp/users.xml>./tmp/response3.xml

		#je récupère l'id du user créé :
		id_user=$(xmllint --xpath 'string(/users/user/@id)' ./tmp/response3.xml)
		debug "-> Création de l'utilisateur $username"
	else
		debug "-> utilisateur $id_user existant"
	fi


	debug "-> role=$role"
  if [ $role = "0" ]   #etudiant
	then
		#par defaut, j'essaie de créer le groupe de l'étudiant
		debug "-> Tentative de création du groupe $user_group"
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -G -k $API_PATH/usersgroups --data-urlencode "label=$user_group"

		#recherche de l'id du groupe
		debug "-> Recherche de l'Id du groupe $user_group"
		rm ./tmp/response.xml
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k -H $CONTENT_TYPE $API_PATH/usersgroups>./tmp/response.xml
		id_user_group=$(xmllint --xpath "string(//groups/group[label='$user_group']/@id)" ./tmp/response.xml)
		debug  "-> id_user_group= $id_user_group "

		#j'ajoute l'étudiant au groupe
		debug "-> Ajout du user $id_user au groupe $id_user_group"
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k "$API_PATH/usersgroups?group=$id_user_group&user=$id_user">./tmp/response.xml

		#je verifie si le portfolio de l'étudiant existe déjà ou pas :
		code_portfolio="$diplome.$TEMPLATE_CODE_PORTFOLIO-$username $firstname $lastname"
		debug "-> Recherche si ce portfolio existe deja : $code_portfolio"
		#rm ./tmp/test.xml

		#il faut encoder à cause des espaces et autres caractères non compatibles :
		code_portfolio_encode=`encode_targetcode "$code_portfolio"`
		code_portfolio_encode="${code_portfolio_encode// /\%20}"
		debug "-> code_portfolio_encode=$code_portfolio_encode"
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $API_PATH/portfolios/portfolio/code/$code_portfolio_encode>./tmp/test.xml
		id_portfolio=$(xmllint --xpath "string(//portfolio/@id)" ./tmp/test.xml)

		debug "-> test existance portfolio, retour= $id_portfolio"

  	if test -z $id_portfolio
		then
			#rm ./tmp/portfolio*.xml

			#recherche de l'id du template portfolio
			url_encode="$API_PATH/portfolios/portfolio/code/"$TEMPLATE_PORTFOLIO_PROJECT"."$TEMPLATE_CODE_PORTFOLIO
			url_encode="${url_encode// /\%20}"
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/response.xml
			id_template_portfolio=$(xmllint --xpath 'string(/portfolio/@id)' ./tmp/response.xml)
			debug "-> id_template_portfolio=$id_template_portfolio "


			#-Creation d'une copie de travail à partir du template portfolio
			tmp_copy_target_code=$TMP_COPY
			tmp_copy_target_code_encode="${tmp_copy_target_code// /\%20}"
			debug "-> tmp_copy_target_code=$tmp_copy_target_code_encode"
			id_copie_travail=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/portfolios/copy/$id_template_portfolio?targetcode=$tmp_copy_target_code_encode&owner=true")
			debug "-> id portfolio copie de travail=$id_copie_travail"
			debug "-> en retour=$?"

			#- récupération du fichier XML :
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/portfolios/portfolio/$id_copie_travail">./tmp/portfolio_template.xml
			#pour la gestion des sauts de ligne :
			xml ed ./tmp/portfolio_template.xml>./tmp/portfolio.xml

			#-je change le libellé dans ma copie de travail :
			label_instance_portfolio=$(xmllint --xpath "string(//portfolio/asmRoot/asmResource/label[@lang='fr']/text())" ./tmp/portfolio.xml)
			debug "-> label_instance_portfolio = $label_instance_portfolio"
			debug "-> changement libellé pour $firstname $lastname"
			xml ed -u "portfolio/asmRoot/asmResource/label[@lang='fr']" -v "$LABEL_FR_PORTFOLIO $firstname $lastname"  ./tmp/portfolio.xml>./tmp/portfolio1.xml
			xml ed -u "portfolio/asmRoot/asmResource/label[@lang='en']" -v "$firstname $lastname $LABEL_EN_PORTFOLIO"  ./tmp/portfolio1.xml>./tmp/portfolio2.xml
			#--------------
			# COMPETENCES
			#--------------

			#je cherche studentReferentiel en me basant sur diplome :
			debug "-> diplome= $diplome"
			case $diplome in
				*'CHINOIS' ) studentReferentiel=("leach")
					domaine=$user_group"-lea"
					;;
				*'INDONESIEN' ) studentReferentiel=("leain")
					domaine=$user_group"-lea"
					;;
				*'CORÉEN' ) studentReferentiel=("leaco")
					domaine=$user_group"-lea"
					;;
				*'PORTUGAIS' ) studentReferentiel=("leaes")
					domaine=$user_group"-lea"
					;;
				*'de la vie' ) studentReferentiel=("sv")
					domaine=$user_group"-sciences"
					;;
				*'de la Terre' ) studentReferentiel=("st")
					domaine=$user_group"-sciences"
					;;
				*'pour la santé' ) studentReferentiel=("sps")
					domaine=$user_group"-sciences"
					;;     		#en-cours de saisi
				*'Informatique' ) studentReferentiel=("info")
					domaine=$user_group"-sciences"
					;;
				*'Mathématiques' ) studentReferentiel=("math")
					domaine=$user_group"-sciences"
					;;
				*'Génie civil' ) studentReferentiel=("gc")
					domaine=$user_group"-sciences"
					;;
				*'chimie' ) studentReferentiel=("pc")
					domaine=$user_group"-sciences"
					;;
				*'Droit' ) studentReferentiel=("droit")
					domaine=$user_group"-droit"
					;;
				*'Gestion' ) studentReferentiel=("gestion")
					domaine=$user_group"-droit"
					;;
				*'Histoire' ) studentReferentiel=("histoire")
					domaine=$user_group"-hgl"
					;;
				*'aménagement' ) studentReferentiel=("geo")
					domaine=$user_group"-hgl"
					;;
				*'LETTRES' ) studentReferentiel=("")
					domaine=$user_group"-hgl"
					;;     		#non renseigné actuellement
				* ) studentReferentiel="";;
			esac
			debug "-> studentReferentiel= ${studentReferentiel[@]}"
			debug "-> domaine= $domaine"

			# get length of an array
			lenReferentiel=${#studentReferentiel[@]}



			#je repere le noeud des competences de la formation dans la copie de travail :
			id_node_del_competence=$(xmllint --xpath "string(//asmStructure[metadata/@semantictag='Section-CompetencesDeLaFormation']/@id)" ./tmp/portfolio2.xml)

			pattern_start_competence='<asmStructure delete="Y" id="'$id_node_del_competence
			debug "-> pattern_start_competence=$pattern_start_competence"
			line_start_competence=$(sed -n "/$pattern_start_competence/=" ./tmp/portfolio2.xml)
			let "line_start_competence-=1"
			debug "-> line_start_competence=$line_start_competence"

			#rm ./tmp/multi_competences.xml
			touch ./tmp/multi_competences.xml

			for (( i=0; i<${lenReferentiel}; i++ ));
			do
  			debug "-> je traite le referentiel : ${studentReferentiel[$i]}"


				rm ./tmp/node_competences*
				id_node_del_other_competence[$i]=0

				#recherche de l'id de ma composante competences
				url_encode="$API_PATH/portfolios/portfolio/code/"$TEMPLATE_PORTFOLIO_PROJECT"."$PREFIX_CODE_COMPETENCES" "${studentReferentiel[$i]}
				url_encode="${url_encode// /\%20}"
				curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $url_encode>./tmp/response3.xml
				id_template_competences=$(xmllint --xpath 'string(/portfolio/@id)' ./tmp/response3.xml)

  			if test -z $id_template_competences
				then
					debug "-> Pas trouvé l'id pour la composante $TEMPLATE_PORTFOLIO_PROJECT.$PREFIX_CODE_COMPETENCES ${studentReferentiel[$i]} !"
				else
					debug "-> OK : trouvé l'id pour la composante $TEMPLATE_PORTFOLIO_PROJECT.$PREFIX_CODE_COMPETENCES ${studentReferentiel[$i]} !"
					debug "-> id_template_competences=$id_template_competences"

					#-Creation de la copie de travail à partir de la composante competence
					copy_competence_targetcode="$TEMPLATE_PORTFOLIO_PROJECT.COPIE TRAVAIL $PREFIX_CODE_COMPETENCES ${studentReferentiel[$i]}"
					copy_competence_targetcode_encode="${copy_competence_targetcode// /\%20}"
					debug "-> copy_competence_targetcode_encode=$copy_competence_targetcode_encode"
					id_copy_competences=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/portfolios/copy/$id_template_competences?targetcode=$copy_competence_targetcode_encode&owner=true")
					debug "-> id id_copy_competences=$id_copy_competences"
					debug "-> en retour=$?"

					#je recupere toute la composante
					curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/portfolios/portfolio/$id_copy_competences">./tmp/composante_competences.xml

					#je recherche le noeud qui m'interesse
					id_node_competence=$(xmllint --xpath "string(//asmResource[label='$PREFIX_LABEL_COMPETENCES ${studentReferentiel[$i]}']/../@id)" ./tmp/composante_competences.xml)

					if test -z $id_node_competence
					then
						debug "-> Pas trouvé de compétences '$PREFIX_LABEL_COMPETENCES ${studentReferentiel[$i]}' !"
					else
						#je repere le noeud des competences de la formation (pour supp. et insertion) :
						curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k $API_PATH/nodes/node/$id_node_competence > ./tmp/node_competences.xml

						#je repere le noeud des autres competences (pour supp.) :
						id_node_del_other_competence[$i]=$(xmllint --xpath "string(//asmStructure[metadata/@semantictag='Ajout-AutresCompetencesEtudiant']/@id)" ./tmp/node_competences.xml)

						#saut de ligne dans le fichier :
						xml ed ./tmp/node_competences.xml>./tmp/node_competences1.xml
						#suppression de la dernière ligne
						head -n -1 ./tmp/node_competences1.xml>./tmp/node_competences2.xml
						#suppression des xx premieres lignes
						#recherche du N° ligne de ma première occurence qui match avec le pattern asmStructure :
						line_start_structure=`grep -n -m 1 "asmStructure" ./tmp/node_competences2.xml|cut -d":" -f 1`
						debug "-> line_start_structure=$line_start_structure"
						let "line_start_structure-=1"
						sedCommand="1,"$line_start_structure"d"
						sed "$sedCommand" ./tmp/node_competences2.xml>>./tmp/multi_competences.xml
					fi

					#je supprime la copie de travail competences :
					curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X DELETE -k $API_PATH/portfolios/portfolio/$id_copy_competences
				fi
			done

			fichier=./tmp/multi_competences.xml
			if test -s $fichier
      then
				#insertion du referentiel dans le portfolio :
				debug "-> insertion du referentiel dans le portfolio"
				sed "$line_start_competence""r ./tmp/multi_competences.xml" ./tmp/portfolio2.xml>./tmp/portfolio4.xml
			else
				debug "-> pas de referentiel pour ce portfolio"
				cp ./tmp/portfolio2.xml ./tmp/portfolio4.xml
			fi
			#-----------------
			#- FIN COMPETENCES
			#-----------------

			#-je change quelques infos dans ma copie de travail :

			#initialisation de zones : nom, prenom, date naissance, ... de l'etudiant
			debug "-> customisation instance"
			xml ed -u "portfolio/asmRoot/asmStructure/asmUnit/asmContext[metadata/@semantictag='NomUsage-Etudiant']/asmResource[@xsi_type='Field']/text" -v "$lastname" ./tmp/portfolio4.xml>./tmp/portfolio5.xml
			xml ed -u "portfolio/asmRoot/asmStructure/asmUnit/asmContext[metadata/@semantictag='Prenom-Etudiant']/asmResource[@xsi_type='Field']/text" -v "$firstname" ./tmp/portfolio5.xml>./tmp/portfolio6.xml
			xml ed -u "portfolio/asmRoot/asmStructure/asmUnit/asmContext[metadata/@semantictag='DateDeNaissance-etudiant']/asmResource[@xsi_type='Calendar']/text" -v "$birthdate" ./tmp/portfolio6.xml>./tmp/portfolio7.xml

			#-je recharge ma copie de travail
      debug "-> je recharge ma copie de travail : $id_copie_travail"
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k -H $CONTENT_TYPE $API_PATH/portfolios/portfolio/$id_copie_travail --data @./tmp/portfolio7.xml>./tmp/response.xml

			#suppression des anciens noeud compétences de la formation et autres compétences :
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X DELETE -k $API_PATH/nodes/node/$id_node_del_competence

			for (( i=0; i<${lenReferentiel}; i++ ));
			do
				debug "-> Suppression du noeud $i autres competences : ${id_node_del_other_competence[$i]}"
				curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X DELETE -k $API_PATH/nodes/node/${id_node_del_other_competence[$i]}
			done

			#j'instancie ma copie de travail :
      debug "-> instanciation du portfolio $diplome.$TEMPLATE_CODE_PORTFOLIO pour $username"
			id_portfolio_instance=$(curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k "$API_PATH/portfolios/instanciate/$id_copie_travail?targetcode=$code_portfolio_encode&owner=true")
			debug "-> id_portfolio_instance= $id_portfolio_instance"

			#je supprime la copie de travail :
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X DELETE -k $API_PATH/portfolios/portfolio/$id_copie_travail

			# ajout au groupe de portfolio
			#-----------------------------
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X PUT -k "$API_PATH/portfoliogroups?group=$id_portfolio_group&uuid=$id_portfolio_instance">./tmp/response.xml
		else
			#l'instance du portfolio existe deja, je ne fais rien
  		id_portfolio_instance=$id_portfolio
			debug "-> instance du portfolio deja existante !"
		fi

		debug "-> partage des droits sur le portfolio $targetcode"
		#- Recherche des roles etudiant et enseignant :
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/rolerightsgroups?portfolio=$id_portfolio_instance">./tmp/response.xml
		id_role_stud=$(xmllint --xpath "string(//rolerightsgroup[label='$ROLE_STUDENT']/@id)" ./tmp/response.xml)
		id_role_teach=$(xmllint --xpath "string(//rolerightsgroup[label='$ROLE_TEACHER']/@id)" ./tmp/response.xml)
		debug "-> role etudiant =$id_role_stud"
		debug "-> role enseignant =$id_role_teach"

		#- Ajout du role étudiant pour le propriétaire du portfolio :
		echo "<users><user id='$id_user'></user></users>" > ./tmp/rrg.xml
		curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/rolerightsgroups/rolerightsgroup/$id_role_stud/users --data @./tmp/rrg.xml>./tmp/response.xml

		#- Ajout du role enseignant pour les intervenants du portfolio :
  	if test -z $domaine
		then
			debug "-> Pas d'intervenant pour ce domaine : $domaine"
		else
      curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/usersgroups">./tmp/droit_liste_usersgroups.xml
      id_rrg=`xmllint --xpath "string(//groups/group[label='intervenant $domaine']/@id)" ./tmp/droit_liste_usersgroups.xml`
      debug "-> id_rrg=$id_rrg"

      curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/usersgroups?group=$id_rrg">./tmp/rrg.xml
      xml ed ./tmp/rrg.xml>./tmp/rrg1.xml
      #suppression des deux premieres lignes et de la derniere ligne :
      head -n -1 ./tmp/rrg1.xml>./tmp/rrg2.xml
      sed '1,2d' ./tmp/rrg2.xml >./tmp/rrg3.xml

			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/rolerightsgroups/rolerightsgroup/$id_role_teach/users --data @./tmp/rrg3.xml>./tmp/response.xml
			debug "-> chargement des intervenants du groupe $id_user_group"

		fi

		#je partage également ces utilisateurs sur le projet si nécessaire :
		if ($exist_project)
		then
			debug "-> je partage mes intervenants sur le projet $id_portfolio_project ..."
			curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X GET -k "$API_PATH/rolerightsgroups?portfolio=$id_portfolio_project">./tmp/response.xml
			id_role_all=$(xmllint --xpath "string(//rolerightsgroup[label='$ROLE_ALL']/@id)" ./tmp/response.xml)
			#- Ajout du role enseignant pour les intervenants du portfolio :
  		if test -z $domaine
			then
				debug "-> Pas d'intervenant pour ce domaine : $domaine"
			else
				curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k -H $CONTENT_TYPE $API_PATH/rolerightsgroups/rolerightsgroup/$id_role_all/users --data @./tmp/rrg3.xml>./tmp/response.xml
				debug "-> chargement des intervenants du groupe $id_user_group pour le projet"
			fi
		fi
	fi

done < $IMPORT_FILENAME


#deconnexion :
#-------------
curl --noproxy $DOMAIN_NAME -b $COOKIE_FILEPATH -X POST -k $API_PATH/credential/logout

rm $COOKIE_FILEPATH

#rm ./tmp/users.xml

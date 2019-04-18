# ARP - La Rochelle
Scripts web services RESTful utilisés à La Rochelle Université pour la création des utilisateurs, des intervenants, des référentiels de compétences et l'instanciation des portfolios :

* import_competences.sh
* import_intervenants.sh
* import_utilisateurs.sh

Ces scripts utilisent les fichiers de ressources placés dans /xml :

* login.xml (à configurer avec le login/mdp root)
* template_mail_new_user.eml
* template_users.xml

## Pré-requis
il est nécessaire d'installer les logiciels suivants :

* xmlstarlet
* xz
* dos2unix
* xmllint
* curl

(nb : xmllint et curl sont a priori déjà présents dans les distributions)

En l'état, les scripts ne fonctionnent que s'ils sont lancés sur le serveur hébergeant la BDD, mais cela peut s'arranger en ajoutant "--host=" à la commande mysqldump

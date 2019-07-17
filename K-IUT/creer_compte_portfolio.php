<?php

if(isset($_SERVER["argv"][1])) $login = trim($_SERVER["argv"][1]); else $login = "";
if(isset($_SERVER["argv"][2])) $nom = trim($_SERVER["argv"][2]); else $nom = "";
if(isset($_SERVER["argv"][3])) $prenom = trim($_SERVER["argv"][3]); else $prenom = "";
if(isset($_SERVER["argv"][4])) $email = trim($_SERVER["argv"][4]); else $email = "";
if(isset($_SERVER["argv"][5])) $annee_debut = trim($_SERVER["argv"][5]); else $annee_debut = "";
if(isset($_SERVER["argv"][6])) $type = trim($_SERVER["argv"][6]); else $type = "E";

if(!$login || !$nom || !$prenom || !$email || !$annee_debut)
{
  echo "\nErreur ! Parametres manquants !! \n\nUsage : /usr/bin/php -f /usr/local/bin/httpful/creer_compte_portfolio.php <login> <nom> <prenom> <email>  <annee_debut> \n\n";
  exit(500);
}



/*
/usr/bin/php -f /usr/local/bin/httpful/creer_compte_portfolio2.php nemo "Nemo" "Le poisson" "nemo@bulles.ca" "2019" E 

$login = "iuttestt2";
$nom = "TEST22";
$prenom = "PrenomTest2";
$email = "prenomtest2.test22@iut2.univ-grenoble-alpes.fr";
$annee_debut = "2016";
*/

$url_base = "http://127.0.0.1:8080/karuta-backend-iut/rest/api/";
$login_root = "root";
$password_root = "adminmati";

$default_user_password = "";

include('/usr/local/bin/httpful/httpful.phar');

// ==========================================================================================
// =========================== AUTHENTIFICATION =============================================
// ==========================================================================================

	$response = \Httpful\Request::post($url_base."credential/login")
	->body("<credential><login>$login_root</login><password>$password_root</password></credential>")
	->sendsXml()
	->send();
	verifier_reponse($response);
	$auth_cookie = $response->headers->toArray()['set-cookie'];

// ==========================================================================================
// =============================== VERIFICATION =============================================
// ==========================================================================================

  	//// ON VERIFIE D'ABORD L'EXISTENCE DE L'UTILISATEUR. S'IL EXISTE ON NE POURSUIT PAS LA CREATION

	$response = \Httpful\Request::get($url_base."users/user/username/".$login)
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	if($response->code!=404) 
	{
	verifier_reponse($response); 
	echo "L'utilisateur $login existe deja : On arrete le traitement. ";
	exit();
	}


// ==========================================================================================
// =========================== CRÉATION DU PROJET COHORTE ===================================
// ==========================================================================================
  
    $portfolio_project_folder = "cohorte-".$annee_debut;
    echo "type=$type";
	if($type!='E')
    {
      $portfolio_project_folder = "GENERIQUE"."enseignant";
    }
	echo "Dossier Projet Cohorte : ".$portfolio_project_folder."\n";

	//On vérifie l'existence
    $response = \Httpful\Request::get($url_base."portfolios/portfolio/code/".$portfolio_project_folder)
      ->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
      ->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
      ->send();
    if($response->code==404) 
    {
		echo "On créée le portfolio $portfolio_project_folder ... ";
		$response = \Httpful\Request::post($url_base."portfolios/instanciate/null?sourcecode=karuta.project&targetcode=".$portfolio_project_folder."&owner=true")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->send();
		verifier_reponse($response);
		$portfolio_project_folder_uuid = $response->body;
		echo "Créé ! uuid=$portfolio_project_folder\n";

		// ----------------- On met à jour le libellé du portfolio
		$response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_project_folder."&semtag=root")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();
		verifier_reponse($response);
		$portfolio_project_folder_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour le libelle du portfolio $portfolio_project_folder sur le noeud root uuid=".$portfolio_project_folder_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."nodes/node/".$portfolio_project_folder_root_node_uuid."/noderesource")
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="nodeRes">
			<code>'.$portfolio_project_folder.'</code>
			<label lang="fr">'.$portfolio_project_folder.'</label>
			<label lang="en">'.$portfolio_project_folder.'</label>
			</asmResource>'))
		->send();
		verifier_reponse($response);
     }
      
	
// ==========================================================================================
// =========================== CREATION DE L'UTILISATEUR ====================================
// ==========================================================================================
	
	$response = \Httpful\Request::post($url_base."users")
	->sendsXml()
	->expectsXml()
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->body(utf8_encode('<users>
		<user>
		<username>'.$login.'</username>
		<lastname>'.$nom.'</lastname>
		<firstname>'.$prenom.'</firstname>
		<email>'.$email.'</email>
		<password>'.$default_user_password.'</password>
		<active>1</active>
		<admin>0</admin>
		<designer>0</designer>
		<substitute>0</substitute>
		</user>
		</users>'))
	->send();
	verifier_reponse($response);
	$user_id = $response->body->user->attributes()->id->__toString();
	echo "Cree ! uuid=$user_id\n";

 
// ==========================================================================================
// =========================== CRÉATION PORTFOLIO  ==========================================
// ==========================================================================================
  
	$portfolio_portfolio = $portfolio_project_folder.".".$login."-portfolio";
	
	//-----------------On vérifie l'existence
	$response = \Httpful\Request::get($url_base."portfolios/portfolio/code/".$portfolio_portfolio)
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	if($response->code==404) 
	{
		echo "On crée le portfolio $portfolio_portfolio ... ";
		$response = \Httpful\Request::post($url_base."portfolios/instanciate/null?sourcecode=IUT2portfolios.IUT2-portfolio&targetcode=".$portfolio_portfolio."&owner=true")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->send();
		verifier_reponse($response);
		$portfolio_portfolio_uuid = $response->body;
		echo "Cree ! uuid=$portfolio_portfolio_uuid\n";
		
			// ----------------- On met à jour le libellé du portfolio
		$response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_portfolio."&semtag=root")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();
		verifier_reponse($response);
		$portfolio_portfolio_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour le libelle du portfolio $portfolio_portfolio sur le noeud root uuid=".$portfolio_portfolio_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."nodes/node/".$portfolio_portfolio_root_node_uuid."/noderesource")
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="nodeRes">
			<code>'.$portfolio_portfolio.'</code>
			<label lang="fr">'.$nom.'-Portfolio IUT2</label>
			<label lang="en">'.$nom.'-Portfolio IUT2</label>
			</asmResource>'))
		->send();
		verifier_reponse($response);
		echo "Fait !\n";
	}

// ==========================================================================================
// =========================== CRÉATION PORTFOLIO CV ========================================
// ==========================================================================================
  
	$portfolio_cv = $portfolio_project_folder.".".$login."-cv";
	
	// ----------------- On vérifie l'existence
	$response = \Httpful\Request::get($url_base."portfolios/portfolio/code/".$portfolio_cv)
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	if($response->code==404) 
	{
		echo "On crée le portfolio $portfolio_cv ... ";
		$response = \Httpful\Request::post($url_base."portfolios/instanciate/null?sourcecode=IUT2portfolios.IUT2-cv&targetcode=".$portfolio_cv."&owner=true")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->send();
		verifier_reponse($response);
		$portfolio_cv_uuid = $response->body;
		echo "Cree ! uuid=$portfolio_cv_uuid\n";

		// ----------------- On met à jour le libellé du portfolio
		$response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_cv."&semtag=root")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();
		verifier_reponse($response);
		$portfolio_cv_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour le libelle du portfolio $portfolio_cv sur le noeud root uuid=".$portfolio_cv_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."nodes/node/".$portfolio_cv_root_node_uuid."/noderesource")
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="nodeRes">
			<code>'.$portfolio_cv.'</code>
			<label lang="fr">'.$nom.'-CVs</label>
			<label lang="en">'.$nom.'-CVs</label>
			</asmResource>'))
		->send();
		verifier_reponse($response);
		echo "Fait !\n";
	}
       


// ==========================================================================================
// =========================== CRÉATION PORTFOLIO PROFILE ===================================
// ==========================================================================================
  
	$portfolio_profile = $portfolio_project_folder.".".$login."-profile";
	
	//On vérifie l'existence
    $response = \Httpful\Request::get($url_base."portfolios/portfolio/code/".$portfolio_profile)
      ->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
      ->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
      ->send();
    if($response->code==404) 
    {
		echo "On créée le portfolio $portfolio_profile ... ";
		$response = \Httpful\Request::post($url_base."portfolios/instanciate/null?sourcecode=IUT2portfolios.IUT2-profile&targetcode=".$portfolio_profile."&owner=true")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->send();
		verifier_reponse($response);
		$portfolio_profile_uuid = $response->body;
		echo "Créé ! uuid=$portfolio_profile_uuid\n";

		// ----------------- On met à jour le libellé du portfolio
		$response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_profile."&semtag=root")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();
		verifier_reponse($response);
		$portfolio_profile_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour le libelle du portfolio $portfolio_profile sur le noeud root uuid=".$portfolio_profile_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."nodes/node/".$portfolio_profile_root_node_uuid."/noderesource")
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="nodeRes">
			<code>'.$portfolio_profile.'</code>
			<label lang="fr">'.$nom.'-Profile</label>
			<label lang="en">'.$nom.'-Profile</label>
			</asmResource>'))
		->send();
		verifier_reponse($response);
		echo "Fait !\n";

		// ----------------- On met à jour le lastname sur profile
		$response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_profile."&semtag=lastname")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();
		verifier_reponse($response);
		$portfolio_profile_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour l'attribut lastname du portfolio $portfolio_profile sur le noeud root uuid=".$portfolio_profile_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."resources/resource/".$portfolio_profile_root_node_uuid)
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="Field">
			<text lang="fr">'.$nom.'</text>
			<text lang="en">'.$nom.'</text>
			</asmResource>'))
		->send();
		verifier_reponse($response);
		echo "Fait !\n"; 
 
		// ----------------- On met à jour le firstname sur profile
		 $response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_profile."&semtag=firstname")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();	
		$portfolio_profile_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour l'attribut firstname du portfolio $portfolio_profile sur le noeud root uuid=".$portfolio_profile_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."resources/resource/".$portfolio_profile_root_node_uuid)
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="Field">
		<text lang="fr">'.$prenom.'</text>
		<text lang="en">'.$prenom.'</text>
		</asmResource>'))
		->send();	
		verifier_reponse($response);
		echo "Fait !\n"; 
     }
      

      
// ==========================================================================================
// =========================== CRÉATION PORTFOLIO PROJET ===================================
// ==========================================================================================
  
	$portfolio_projet = $portfolio_project_folder.".".$login."-projet";
	
	//-----------------On vérifie l'existence
	$response = \Httpful\Request::get($url_base."portfolios/portfolio/code/".$portfolio_projet)
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();


    if($response->code==404) 
    {
		echo "On crée le portfolio $portfolio_projet ... ";
		$response = \Httpful\Request::post($url_base."portfolios/instanciate/null?sourcecode=IUT2portfolios.IUT2-projet&targetcode=".$portfolio_projet."&owner=true")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->send();
		verifier_reponse($response);
		$portfolio_projet_uuid = $response->body;
		echo "Cree ! uuid=$portfolio_projet_uuid\n";

		// ----------------- On met à jour le libellé du portfolio

		$response = \Httpful\Request::get($url_base."nodes?portfoliocode=".$portfolio_projet."&semtag=root")
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->expectsXml() // car s'il n'existe pas, cela retourne une page web, pas du XML
		->send();
		verifier_reponse($response);	
		$portfolio_projet_root_node_uuid = $response->body->node->attributes()->id->__toString();
	
		echo "On met a jour le libelle du portfolio $portfolio_projet sur le noeud root uuid=".$portfolio_projet_root_node_uuid." ... ";
		$response = \Httpful\Request::put($url_base."nodes/node/".$portfolio_projet_root_node_uuid."/noderesource")
		->sendsXml()
		->expectsXhtml()
		->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
		->body(utf8_encode('<asmResource xsi_type="nodeRes">
			<code>'.$portfolio_projet.'</code>
			<label lang="fr">'.$nom.'-Projet</label>
			<label lang="en">'.$nom.'-Projet</label>
			</asmResource>'))
		->send();	
		verifier_reponse($response);
		echo "Fait !\n";
     }
      
      
// ==========================================================================================
// =========================== PARTAGE DES PORTFOLIOS =======================================
// ==========================================================================================
      
	// ----------------- profile	
	$response = \Httpful\Request::get($url_base."rolerightsgroups?portfolio=".$portfolio_profile_uuid."&role=etudiant")
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();	
	verifier_reponse($response);
	$role_etudiant_id = $response->body;
	
	echo "On met a jour les droits de $login dans profile ($portfolio_profile_uuid), role=etudiant, role_id=$role_etudiant_id ... ";
	$response = \Httpful\Request::post($url_base."rolerightsgroups/rolerightsgroup/".$role_etudiant_id."/users")
	->sendsXml()
	->expectsXhtml()
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->body(utf8_encode('<users><user id="'.$user_id.'"></user></users>'))
	->send();	
	verifier_reponse($response);
	echo "Fait !\n";
	
	 // ----------------- portfolio 
	$response = \Httpful\Request::get($url_base."rolerightsgroups?portfolio=".$portfolio_portfolio_uuid."&role=etudiant")
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	verifier_reponse($response);
	$role_etudiant_id = $response->body;
	
	echo "On met a jour les droits de $login dans portfolio ($portfolio_portfolio_uuid), role=etudiant, role_id=$role_etudiant_id ... ";	
	$response = \Httpful\Request::post($url_base."rolerightsgroups/rolerightsgroup/".$role_etudiant_id."/users")
	->sendsXml()
	->expectsXhtml()
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->body(utf8_encode('<users><user id="'.$user_id.'"></user></users>'))
	->send();
	verifier_reponse($response);
	echo "Fait !\n";
      
	// -----------------  cv
	$response = \Httpful\Request::get($url_base."rolerightsgroups?portfolio=".$portfolio_cv_uuid."&role=etudiant")
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	verifier_reponse($response);
	$role_etudiant_id = $response->body;
	
	echo "On met a jour les droits de $login dans cv ($portfolio_cv_uuid), role=etudiant, role_id=$role_etudiant_id ... ";
	$response = \Httpful\Request::post($url_base."rolerightsgroups/rolerightsgroup/".$role_etudiant_id."/users")
	->sendsXml()
	->expectsXhtml()
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->body(utf8_encode('<users><user id="'.$user_id.'"></user></users>'))
	->send();
	verifier_reponse($response);
	echo "Fait !\n"; 
	
	// -----------------  projet
	$response = \Httpful\Request::get($url_base."rolerightsgroups?portfolio=".$portfolio_projet_uuid."&role=etudiant")
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	verifier_reponse($response);
	$role_etudiant_id = $response->body;
	
	echo "On met a jour les droits de $login dans projet ($portfolio_projet_uuid), role=etudiant, role_id=$role_etudiant_id ... ";
	$response = \Httpful\Request::post($url_base."rolerightsgroups/rolerightsgroup/".$role_etudiant_id."/users")
	->sendsXml()
	->expectsXhtml()
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->body(utf8_encode('<users><user id="'.$user_id.'"></user></users>'))
	->send();
	verifier_reponse($response);
	echo "Fait !\n"; 

	// ----------------- on recupere l'id de l'utilisateur public
	$response = \Httpful\Request::get($url_base."users/user/username/public")
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	verifier_reponse($response);
	$user_public_id = $response->body;
	if(intval($user_public_id)<=0) 
	{
	  echo "L'id de l'utilisateur public est null";
	  exit(500);
	}
	
	// ----------------- partage projet avec public pour la carte interactive   
	$response = \Httpful\Request::get($url_base."rolerightsgroups?portfolio=".$portfolio_projet_uuid."&role=all")
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->expectsXhtml() // car s'il n'existe pas, cela retourne une page web, pas du XML
	->send();
	verifier_reponse($response);
	$role_all_id = $response->body;
	
	echo "On met a jour les droits de $login dans projet ($portfolio_projet_uuid), role=all, role_id=$role_all_id ... ";
	$response = \Httpful\Request::post($url_base."rolerightsgroups/rolerightsgroup/".$role_all_id."/users")
	->sendsXml()
	->expectsXhtml()
	->addOnCurlOption(CURLOPT_COOKIE, $auth_cookie)
	->body(utf8_encode('<users><user id="'.$user_public_id.'"></user></users>'))
	->send();
	verifier_reponse($response);
	echo "Fait !\n"; 
	
      
     
/////////////////////////////////////////////////////////////////////////////////////////////

function  verifier_reponse($response)
{
  if($response->code!=200)
  {
    echo "HTTP Erreur ".$response->code." : ".print_r($response,true);
    exit(500);
  }
}

?>

import subprocess
from samba.samdb import SamDB
from samba import credentials
from samba.param import LoadParm

# --- Connexion au domaine Samba AD ---
def detect_domain_settings(admin_user, admin_password):
    """
    Connexion au domaine Samba AD avec authentification.
    Renvoie un dictionnaire contenant :
      - samdb : l'instance SamDB
      - domain_dn : le DN du domaine
      - domain_name : le nom du domaine (extrait du DC)
      - user : le nom d'utilisateur administrateur
    """
    lp = LoadParm()
    creds = credentials.Credentials()
    try:
        creds.set_username(admin_user)
        creds.set_password(admin_password)
        creds.guess(lp)
        samdb = SamDB(url="ldap://localhost", credentials=creds, lp=lp)
        # Récupération du contexte par défaut
        result = samdb.search(base="", scope=0, attrs=["defaultNamingContext"])
        domain_dn = result[0]["defaultNamingContext"][0]
        # Récupération du nom de domaine via l'attribut "dc"
        result = samdb.search(base=domain_dn, expression="(objectClass=domain)", attrs=["dc"])
        domain_name = result[0]["dc"][0]
        # Décodage si nécessaire
        if isinstance(domain_dn, bytes):
            domain_dn = domain_dn.decode("utf-8", errors="replace")
        if isinstance(domain_name, bytes):
            domain_name = domain_name.decode("utf-8", errors="replace")
        return {"samdb": samdb, "domain_dn": domain_dn, "domain_name": domain_name, "user": admin_user}
    except Exception as e:
        return f"[ERROR] Connexion échouée : {e}"

# --- Fonctions de gestion des Organizational Units (OUs) ---
def list_ous(samdb, domain_dn):
    ous = samdb.search(base=domain_dn, expression="(objectClass=organizationalUnit)", attrs=["ou", "dn"])
    result = []
    if ous:
        for ou in ous:
            name = ou["ou"][0]
            if isinstance(name, bytes):
                name = name.decode("utf-8", errors="replace")
            result.append({"name": name, "dn": ou.get("dn")})
    return result

def create_ou(samdb, domain_dn, ou_name):
    try:
        ou_dn = f"OU={ou_name},{domain_dn}"
        samdb.add({"dn": ou_dn, "objectClass": ["top", "organizationalUnit"]})
        return f"[OK] OU '{ou_name}' créée."
    except Exception as e:
        return f"[ERROR] Impossible de créer l'OU : {e}"

def delete_ou(samdb, domain_dn, ou_name):
    try:
        ou_dn = f"OU={ou_name},{domain_dn}"
        samdb.delete(ou_dn)
        return f"[OK] OU '{ou_name}' supprimée."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer l'OU : {e}"

# --- Fonctions de gestion des Groupes ---
def list_groups(samdb, domain_dn):
    base = f"CN=Users,{domain_dn}"
    groups = samdb.search(base=base, expression="(objectClass=group)", attrs=["cn", "description", "dn"])
    result = []
    if groups:
        for group in groups:
            name = group["cn"][0]
            if isinstance(name, bytes):
                name = name.decode("utf-8", errors="replace")
            description = ""
            if "description" in group and group["description"]:
                description = group["description"][0]
                if isinstance(description, bytes):
                    description = description.decode("utf-8", errors="replace")
            result.append({"name": name, "description": description, "dn": group.get("dn")})
    return result

def create_group(samdb, domain_dn, group_name):
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        samdb.add({"dn": group_dn, "objectClass": ["top", "group"], "sAMAccountName": group_name})
        return f"[OK] Groupe '{group_name}' créé."
    except Exception as e:
        return f"[ERROR] Impossible de créer le groupe : {e}"

def delete_group(samdb, domain_dn, group_name):
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        samdb.delete(group_dn)
        return f"[OK] Groupe '{group_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer le groupe : {e}"

# --- Fonctions de gestion des GPOs ---
def list_gpos(samdb, domain_dn):
    gpo_base = f"CN=Policies,CN=System,{domain_dn}"
    gpos = samdb.search(base=gpo_base, expression="(objectClass=groupPolicyContainer)", attrs=["displayName", "dn"])
    result = []
    if gpos:
        for gpo in gpos:
            name = gpo["displayName"][0]
            if isinstance(name, bytes):
                name = name.decode("utf-8", errors="replace")
            result.append({"name": name, "dn": gpo.get("dn")})
    return result

def create_full_gpo(gpo_name):
    try:
        result = subprocess.run(
            ["samba-tool", "gpo", "create", gpo_name],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        return f"[OK] GPO '{gpo_name}' créé.\n{result.stdout}"
    except subprocess.CalledProcessError as e:
        return f"[ERROR] La création du GPO a échoué : {e.stderr}"

def delete_gpo(samdb, domain_dn, gpo_name):
    try:
        gpo_base = f"CN=Policies,CN=System,{domain_dn}"
        gpo_dn = f"CN={gpo_name},{gpo_base}"
        samdb.delete(gpo_dn)
        return f"[OK] GPO '{gpo_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer le GPO : {e}"

# --- Fonctions de gestion des Utilisateurs ---
def list_users(samdb, domain_dn):
    users = samdb.search(base=domain_dn, expression="(&(objectClass=user)(!(sAMAccountName=krbtgt)))", 
                         attrs=["cn", "sAMAccountName", "description", "dn"])
    result = []
    if users:
        for user in users:
            cn = user.get("cn", [b""])[0]
            if isinstance(cn, bytes):
                cn = cn.decode("utf-8", errors="replace")
            sam = user.get("sAMAccountName", [b""])[0]
            if isinstance(sam, bytes):
                sam = sam.decode("utf-8", errors="replace")
            desc = ""
            if "description" in user and user["description"]:
                desc = user["description"][0]
                if isinstance(desc, bytes):
                    desc = desc.decode("utf-8", errors="replace")
            result.append({"cn": cn, "sAMAccountName": sam, "description": desc, "dn": user.get("dn")})
    return result

def create_user(samdb, domain_dn, user_name, password):
    try:
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        user_attrs = {
            "dn": user_dn,
            "objectClass": ["top", "person", "organizationalPerson", "user"],
            "sAMAccountName": user_name,
            "userPassword": password
        }
        samdb.add(user_attrs)
        return f"[OK] Utilisateur '{user_name}' créé."
    except Exception as e:
        return f"[ERROR] Impossible de créer l'utilisateur : {e}"

def delete_user(samdb, domain_dn, user_name):
    try:
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        samdb.delete(user_dn)
        return f"[OK] Utilisateur '{user_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer l'utilisateur : {e}"

# --- Fonction de réinitialisation de mot de passe ---
def reset_password(samdb, domain_dn, username, new_password):
    """
    Réinitialise le mot de passe d’un utilisateur Samba AD en utilisant l'API native.
    """
    try:
        expression = f"(sAMAccountName={username})"
        samdb.setpassword(
            expression,
            new_password,
            force_change_at_next_login=False,
            username=None  # L'utilisateur exécutant l'opération est déjà authentifié via `samdb`
        )
        return f"[OK] Mot de passe réinitialisé pour '{username}'."
    except Exception as e:
        return f"[ERROR] Impossible de réinitialiser le mot de passe pour '{username}' : {e}"


# --- Fonctions de gestion des Ordinateurs ---
def list_computers(samdb, domain_dn):
    computers = samdb.search(base=domain_dn, expression="(objectClass=computer)", attrs=["cn", "sAMAccountName", "dn"])
    result = []
    if computers:
        for comp in computers:
            cn = comp.get("cn", [b""])[0]
            if isinstance(cn, bytes):
                cn = cn.decode("utf-8", errors="replace")
            sam = comp.get("sAMAccountName", [b""])[0]
            if isinstance(sam, bytes):
                sam = sam.decode("utf-8", errors="replace")
            result.append({"name": cn, "sAMAccountName": sam, "dn": comp.get("dn")})
    return result

def create_computer(samdb, domain_dn, computer_name):
    try:
        computer_dn = f"CN={computer_name},CN=Computers,{domain_dn}"
        attrs = {
            "dn": computer_dn,
            "objectClass": ["top", "computer"],
            "sAMAccountName": f"{computer_name}$"
        }
        samdb.add(attrs)
        return f"[OK] Ordinateur '{computer_name}' créé."
    except Exception as e:
        return f"[ERROR] Impossible de créer l'ordinateur : {e}"

def delete_computer(samdb, domain_dn, computer_name):
    try:
        computer_dn = f"CN={computer_name},CN=Computers,{domain_dn}"
        samdb.delete(computer_dn)
        return f"[OK] Ordinateur '{computer_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer l'ordinateur : {e}"

def move_computer(samdb, domain_dn, computer_name, target_ou):
    try:
        old_dn = f"CN={computer_name},CN=Computers,{domain_dn}"
        new_dn = f"CN={computer_name},OU={target_ou},{domain_dn}"
        samdb.rename(old_dn, new_dn)
        return f"[OK] Ordinateur '{computer_name}' déplacé vers l'OU '{target_ou}'."
    except Exception as e:
        return f"[ERROR] Impossible de déplacer l'ordinateur : {e}"

# --- Fonctions avancées génériques ---
def modify_object(samdb, dn, modifications):
    """
    Modifie un objet en remplaçant ses attributs.
    'modifications' est un dictionnaire où chaque clé est le nom d'un attribut et
    chaque valeur est une liste des nouvelles valeurs.
    Exemple : {"description": ["Nouvelle description"]}
    """
    try:
        samdb.modify(dn, modifications)
        return f"[OK] Objet {dn} modifié."
    except Exception as e:
        return f"[ERROR] Modification de l'objet {dn} a échoué : {e}"

def get_object_attributes(samdb, dn, all_attrs=False):
    """
    Récupère les attributs de l'objet identifié par 'dn'.
    - all_attrs=False : on récupère un ensemble limité d'attributs (plus rapide et stable)
    - all_attrs=True  : on récupère tous les attributs (attrs=["*"]), ce qui est complet mais peut être lourd
    """
    try:
        if all_attrs:
            result = samdb.search(base=dn, scope=0, attrs=["*"])
        else:
            default_attrs = ["cn", "description", "member", "objectClass", "distinguishedName"]
            result = samdb.search(base=dn, scope=0, attrs=default_attrs)
        return result[0] if result else None
    except Exception as e:
        return f"[ERROR] Impossible d'obtenir les attributs de l'objet {dn} : {e}"

def search_objects(samdb, base, filter_expr, attrs=None):
    """
    Effectue une recherche dans l'annuaire à partir d'une base DN, d'une expression filtre,
    et d'une liste d'attributs à récupérer (ou tous si None).
    """
    try:
        results = samdb.search(base=base, expression=filter_expr, attrs=attrs)
        return results
    except Exception as e:
        return f"[ERROR] Recherche échouée : {e}"

def move_object(samdb, current_dn, new_dn):
    """
    Déplace (ou renomme) un objet de 'current_dn' vers 'new_dn'.
    """
    try:
        samdb.rename(current_dn, new_dn)
        return f"[OK] Objet déplacé de {current_dn} vers {new_dn}."
    except Exception as e:
        return f"[ERROR] Échec du déplacement de l'objet : {e}"

def rename_object(samdb, old_dn, new_rdn):
    """
    Renomme un objet en changeant son RDN.
    Par exemple, pour renommer un utilisateur, 'new_rdn' pourra être "CN=nouveau_nom".
    """
    try:
        samdb.rename(old_dn, new_rdn)
        return f"[OK] Objet renommé en {new_rdn}."
    except Exception as e:
        return f"[ERROR] Échec du renommage de l'objet : {e}"

def refresh_data(domain_info):
    """
    Rafraîchit et retourne les données pour chaque onglet (OUs, Groupes, GPOs, Utilisateurs, Ordinateurs).
    """
    data = {}
    data['ous'] = list_ous(domain_info["samdb"], domain_info["domain_dn"])
    data['groupes'] = list_groups(domain_info["samdb"], domain_info["domain_dn"])
    data['gpos'] = list_gpos(domain_info["samdb"], domain_info["domain_dn"])
    data['users'] = list_users(domain_info["samdb"], domain_info["domain_dn"])
    data['computers'] = list_computers(domain_info["samdb"], domain_info["domain_dn"])
    data['dashboard'] = {
         "OUs": len(data['ous']),
         "Groupes": len(data['groupes']),
         "GPOs": len(data['gpos']),
         "Utilisateurs": len(data['users']),
         "Ordinateurs": len(data['computers'])
    }
    return data

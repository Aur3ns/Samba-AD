import subprocess
from samba.samdb import SamDB
from samba import credentials
from samba.param import LoadParm

def detect_domain_settings(admin_user, admin_password):
    """Connexion au domaine Samba AD avec authentification."""
    lp = LoadParm()
    creds = credentials.Credentials()
    try:
        creds.set_username(admin_user)
        creds.set_password(admin_password)
        creds.guess(lp)
        samdb = SamDB(url="ldap://localhost", credentials=creds, lp=lp)
        domain_dn = samdb.search(base="", scope=0, attrs=["defaultNamingContext"])[0]["defaultNamingContext"][0]
        domain_name = samdb.search(base=domain_dn, expression="(objectClass=domain)", attrs=["dc"])[0]["dc"][0]
        return {"samdb": samdb, "domain_dn": domain_dn, "domain_name": domain_name, "user": admin_user}
    except Exception as e:
        return f"[ERROR] Connexion échouée : {e}"

def list_ous(samdb, domain_dn):
    ous = samdb.search(base=domain_dn, expression="(objectClass=organizationalUnit)", attrs=["ou", "dn"])
    return [ou["ou"][0].decode('utf-8') if isinstance(ou["ou"][0], bytes) else ou["ou"][0] for ou in ous] if ous else []

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

def list_groups(samdb, domain_dn):
    try:
        base = f"CN=Users,{domain_dn}"
        groups = samdb.search(base=base, expression="(objectClass=group)", attrs=["cn"])
        return [group["cn"][0] for group in groups] if groups else []
    except Exception as e:
        return f"[ERROR] {e}"

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

def list_gpos(samdb, domain_dn):
    gpo_base = f"CN=Policies,CN=System,{domain_dn}"
    gpos = samdb.search(base=gpo_base, expression="(objectClass=groupPolicyContainer)", attrs=["displayName"])
    return [gpo["displayName"][0].decode('utf-8') if isinstance(gpo["displayName"][0], bytes) else gpo["displayName"][0] for gpo in gpos] if gpos else []

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

def list_users(samdb, domain_dn):
    users = samdb.search(base=domain_dn, expression="(objectClass=user)", attrs=["sAMAccountName"])
    return [user["sAMAccountName"][0].decode('utf-8') if isinstance(user["sAMAccountName"][0], bytes) else user["sAMAccountName"][0] 
            for user in users if user["sAMAccountName"][0].lower() != b"krbtgt"] if users else []

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

def list_computers(samdb, domain_dn):
    try:
        computers = samdb.search(base=domain_dn, expression="(objectClass=computer)", attrs=["cn"])
        return [comp["cn"][0].decode('utf-8') if isinstance(comp["cn"][0], bytes) else comp["cn"][0] for comp in computers] if computers else []
    except Exception as e:
        return f"[ERROR] {e}"

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

def refresh_data(domain_info):
    """Rafraîchit et retourne les données pour chaque onglet."""
    data = {}
    data['ous'] = list_ous(domain_info["samdb"], domain_info["domain_dn"])
    data['groupes'] = list_groups(domain_info["samdb"], domain_info["domain_dn"])
    data['gpos'] = list_gpos(domain_info["samdb"], domain_info["domain_dn"])
    data['users'] = list_users(domain_info["samdb"], domain_info["domain_dn"])
    data['computers'] = list_computers(domain_info["samdb"], domain_info["domain_dn"])
    data['dashboard'] = {
         "OUs": len(data['ous']),
         "Groupes": len(data['groupes']) if isinstance(data['groupes'], list) else 0,
         "GPOs": len(data['gpos']),
         "Utilisateurs": len(data['users']),
         "Ordinateurs": len(data['computers'])
    }
    return data

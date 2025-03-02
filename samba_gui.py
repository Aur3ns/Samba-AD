import curses
import getpass
from samba.samdb import SamDB
from samba import credentials
from samba.param import LoadParm

# --- CONNEXION AU DOMAINE ---
def detect_domain_settings(admin_user, admin_password):
    """
    Se connecte au domaine Samba AD avec les identifiants fournis.
    Renvoie un dictionnaire contenant :
      - samdb : l'objet de connexion LDAP
      - domain_dn : le DN racine du domaine (ex: DC=example,DC=com)
      - domain_name : le nom du domaine
    """
    lp = LoadParm()
    creds = credentials.Credentials()
    try:
        creds.set_username(admin_user)
        creds.set_password(admin_password)
        creds.guess(lp)
        samdb = SamDB(url="ldap://localhost", credentials=creds, lp=lp)
        # Récupérer le DN racine du domaine
        domain_dn = samdb.search(base="", scope=0, attrs=["defaultNamingContext"])[0]["defaultNamingContext"][0]
        # Extraire le nom du domaine
        domain_name = samdb.search(base=domain_dn, expression="(objectClass=domain)", attrs=["dc"])[0]["dc"][0]
        return {"samdb": samdb, "domain_dn": domain_dn, "domain_name": domain_name}
    except Exception as e:
        return f"[ERROR] Connexion échouée : {e}"

# --- FONCTIONS DE GESTION DES OUs ---

def create_ou_under(samdb, parent_dn, ou_name):
    """Crée une OU enfant sous le DN fourni."""
    try:
        ou_dn = f"OU={ou_name},{parent_dn}"
        samdb.add({"dn": ou_dn, "objectClass": ["top", "organizationalUnit"]})
        return f"[OK] OU '{ou_name}' créée sous '{parent_dn}'."
    except Exception as e:
        return f"[ERROR] Création de l'OU impossible : {e}"

def delete_ou_dn(samdb, ou_dn):
    """Supprime l'OU dont le DN est fourni."""
    try:
        samdb.delete(ou_dn)
        return f"[OK] OU supprimée."
    except Exception as e:
        return f"[ERROR] Suppression de l'OU impossible : {e}"

def rename_ou_dn(samdb, old_dn, new_name):
    """Renomme l'OU dont le DN est fourni en remplaçant son premier RDN."""
    try:
        parts = old_dn.split(",", 1)
        if len(parts) != 2:
            return "[ERROR] DN invalide."
        new_dn = f"OU={new_name},{parts[1]}"
        samdb.rename(old_dn, new_dn)
        return f"[OK] OU renommée en '{new_name}'."
    except Exception as e:
        return f"[ERROR] Renommage de l'OU impossible : {e}"

def list_child_ous(samdb, parent_dn):
    """
    Liste les OU immédiatement enfants du DN fourni.
    Le paramètre scope=1 permet de limiter la recherche aux enfants directs.
    """
    try:
        children = samdb.search(base=parent_dn, scope=1, expression="(objectClass=organizationalUnit)", attrs=["ou"])
        # On s'assure que chaque entrée possède son DN (généralement fourni automatiquement)
        return children if children else []
    except Exception as e:
        return f"[ERROR] {e}"

def build_ou_tree(samdb, domain_dn):
    """
    Construit l'arborescence complète des OUs à partir du domaine.
    Retourne un dictionnaire de nœuds sous la forme :
      { "name": <nom de l'OU>, "dn": <DN complet>, "children": [ ... ] }
    """
    try:
        # Recherche récursive (scope par défaut supposé SUBTREE)
        ous = samdb.search(base=domain_dn, expression="(objectClass=organizationalUnit)", attrs=["ou"])
    except Exception as e:
        return []
    
    nodes = {}
    for entry in ous:
        # On suppose que le résultat contient le DN complet dans entry["dn"]
        dn = entry.get("dn")
        if not dn:
            continue
        name = entry["ou"][0] if "ou" in entry and entry["ou"] else "Inconnu"
        nodes[dn] = {"name": name, "dn": dn, "children": []}
    
    tree = []
    for dn, node in nodes.items():
        # Déterminer le DN parent en retirant le premier RDN
        parts = dn.split(",", 1)
        parent_dn = parts[1].strip() if len(parts) == 2 else None
        if parent_dn == domain_dn or parent_dn not in nodes:
            tree.append(node)
        else:
            nodes[parent_dn]["children"].append(node)
    return tree

def flatten_ou_tree(tree, level=0):
    """
    Aplati l'arborescence des OUs en une liste de tuples (node, niveau)
    pour affichage dans un menu interactif.
    """
    flat = []
    for node in tree:
        flat.append((node, level))
        if node["children"]:
            flat.extend(flatten_ou_tree(node["children"], level+1))
    return flat

# --- FONCTIONS DE GESTION DES GROUPES ---

def list_groups(samdb, domain_dn):
    """Liste les groupes présents dans CN=Users."""
    try:
        groups = samdb.search(base=domain_dn, expression="(objectClass=group)", attrs=["cn"])
        return [group["cn"][0] for group in groups] if groups else []
    except Exception as e:
        return f"[ERROR] {e}"

def create_group(samdb, domain_dn, group_name):
    """Crée un groupe dans le conteneur CN=Users."""
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        samdb.add({"dn": group_dn, "objectClass": ["top", "group"], "sAMAccountName": group_name})
        return f"[OK] Groupe '{group_name}' créé."
    except Exception as e:
        return f"[ERROR] Création du groupe impossible : {e}"

def delete_group(samdb, domain_dn, group_name):
    """Supprime un groupe."""
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        samdb.delete(group_dn)
        return f"[OK] Groupe '{group_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Suppression du groupe impossible : {e}"

def add_user_to_group(samdb, domain_dn, group_name, user_name):
    """Ajoute un utilisateur à un groupe."""
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        modifications = [("add", "member", user_dn)]
        samdb.modify(group_dn, modifications)
        return f"[OK] L'utilisateur '{user_name}' ajouté au groupe '{group_name}'."
    except Exception as e:
        return f"[ERROR] Ajout de l'utilisateur au groupe impossible : {e}"

def remove_user_from_group(samdb, domain_dn, group_name, user_name):
    """Retire un utilisateur d'un groupe."""
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        modifications = [("delete", "member", user_dn)]
        samdb.modify(group_dn, modifications)
        return f"[OK] L'utilisateur '{user_name}' retiré du groupe '{group_name}'."
    except Exception as e:
        return f"[ERROR] Retrait de l'utilisateur du groupe impossible : {e}"

# --- FONCTIONS DE GESTION DES UTILISATEURS ---

def list_users(samdb, domain_dn):
    """Liste les utilisateurs (excluant 'krbtgt')."""
    try:
        users = samdb.search(base=domain_dn, expression="(objectClass=user)", attrs=["sAMAccountName"])
        return [user["sAMAccountName"][0] for user in users if user["sAMAccountName"][0].lower() != "krbtgt"] if users else []
    except Exception as e:
        return f"[ERROR] {e}"

def create_user(samdb, domain_dn, user_name, password):
    """Crée un nouvel utilisateur dans CN=Users."""
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
        return f"[ERROR] Création de l'utilisateur impossible : {e}"

def delete_user(samdb, domain_dn, user_name):
    """Supprime un utilisateur."""
    try:
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        samdb.delete(user_dn)
        return f"[OK] Utilisateur '{user_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Suppression de l'utilisateur impossible : {e}"

def reset_password(samdb, domain_dn, user_name, new_password):
    """Réinitialise le mot de passe d'un utilisateur."""
    try:
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        modifications = [("replace", "userPassword", new_password)]
        samdb.modify(user_dn, modifications)
        return f"[OK] Mot de passe réinitialisé pour '{user_name}'."
    except Exception as e:
        return f"[ERROR] Réinitialisation du mot de passe impossible : {e}"

def modify_user_attribute(samdb, domain_dn, user_name, attribute, value):
    """Modifie un attribut d'un utilisateur."""
    try:
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        modifications = [("replace", attribute, value)]
        samdb.modify(user_dn, modifications)
        return f"[OK] Attribut '{attribute}' mis à jour pour '{user_name}'."
    except Exception as e:
        return f"[ERROR] Modification de l'attribut impossible : {e}"

# --- FONCTIONS DE GESTION DES GPOs ---

def list_gpos(samdb, domain_dn):
    """Liste les GPOs dans CN=Policies,CN=System."""
    try:
        gpo_base = f"CN=Policies,CN=System,{domain_dn}"
        gpos = samdb.search(base=gpo_base, expression="(objectClass=groupPolicyContainer)", attrs=["displayName"])
        return [gpo["displayName"][0] for gpo in gpos] if gpos else []
    except Exception as e:
        return f"[ERROR] {e}"

def create_gpo(samdb, domain_dn, gpo_name):
    """Crée un GPO dans CN=Policies,CN=System."""
    try:
        gpo_base = f"CN=Policies,CN=System,{domain_dn}"
        gpo_dn = f"CN={gpo_name},{gpo_base}"
        samdb.add({"dn": gpo_dn, "objectClass": ["top", "groupPolicyContainer"], "displayName": gpo_name})
        return f"[OK] GPO '{gpo_name}' créé."
    except Exception as e:
        return f"[ERROR] Création du GPO impossible : {e}"

def delete_gpo(samdb, domain_dn, gpo_name):
    """Supprime un GPO."""
    try:
        gpo_base = f"CN=Policies,CN=System,{domain_dn}"
        gpo_dn = f"CN={gpo_name},{gpo_base}"
        samdb.delete(gpo_dn)
        return f"[OK] GPO '{gpo_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Suppression du GPO impossible : {e}"

# --- FONCTIONS D'AFFICHAGE AVEC CURSES ---
def display_menu(stdscr, title, options):
    """
    Affiche un menu interactif et retourne l'indice de l'option sélectionnée.
    """
    current_row = 0
    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, f"[ {title} ]", curses.A_BOLD)
        stdscr.addstr(1, 0, "=" * 50)
        for idx, option in enumerate(options):
            if idx == current_row:
                stdscr.addstr(idx + 3, 0, f"> {option}", curses.A_REVERSE)
            else:
                stdscr.addstr(idx + 3, 0, f"  {option}")
        stdscr.refresh()
        key = stdscr.getch()
        if key == curses.KEY_UP and current_row > 0:
            current_row -= 1
        elif key == curses.KEY_DOWN and current_row < len(options) - 1:
            current_row += 1
        elif key in [10, 13]:
            return current_row

def prompt_input(stdscr, prompt, y=2, x=0, echo=True, max_len=40):
    """
    Affiche une invite et récupère la saisie de l'utilisateur.
    """
    stdscr.clear()
    stdscr.addstr(y, x, prompt)
    stdscr.refresh()
    if echo:
        curses.echo()
    else:
        curses.noecho()
    input_str = stdscr.getstr(y, x + len(prompt) + 1, max_len).decode('utf-8')
    curses.noecho()
    return input_str

def display_message(stdscr, message):
    """Affiche un message et attend une touche."""
    stdscr.clear()
    stdscr.addstr(2, 0, message)
    stdscr.addstr(4, 0, "[Appuyez sur une touche pour continuer...]")
    stdscr.refresh()
    stdscr.getch()

# --- MENU DE NAVIGATION DE L'ARBORESCENCE DES OUs ---
def ou_tree_navigation_menu(stdscr, domain_info):
    """
    Construit et affiche l'arborescence des OUs.
    L'utilisateur sélectionne une OU dans la liste aplatie pour ensuite exécuter des opérations.
    """
    samdb = domain_info["samdb"]
    domain_dn = domain_info["domain_dn"]
    tree = build_ou_tree(samdb, domain_dn)
    flat_tree = flatten_ou_tree(tree)
    
    if not flat_tree:
        display_message(stdscr, "[INFO] Aucune OU trouvée dans le domaine.")
        return

    # Préparer les options affichées avec indentation
    options = []
    for node, level in flat_tree:
        indent = "  " * level
        options.append(f"{indent}{node['name']}")

    idx = display_menu(stdscr, "Arborescence des OUs", options)
    selected_node, _ = flat_tree[idx]
    selected_ou_menu(stdscr, domain_info, selected_node)

def selected_ou_menu(stdscr, domain_info, node):
    """
    Menu dédié aux opérations sur une OU sélectionnée (dont le DN est node["dn"]).
    """
    samdb = domain_info["samdb"]
    ou_dn = node["dn"]
    while True:
        options = ["Lister les OU enfants", "Créer une OU enfant", "Supprimer cette OU", "Renommer cette OU", "Retour"]
        choice = display_menu(stdscr, f"OU sélectionnée: {node['name']}", options)
        if choice == 0:
            # Lister les enfants directs
            children = list_child_ous(samdb, ou_dn)
            if isinstance(children, str):
                msg = children
            else:
                if children:
                    lst = []
                    for child in children:
                        child_dn = child.get("dn", "DN inconnu")
                        child_name = child["ou"][0] if "ou" in child and child["ou"] else "Inconnu"
                        lst.append(f"{child_name} ({child_dn})")
                    msg = "\n".join(lst)
                else:
                    msg = "[INFO] Aucun enfant trouvé."
            display_message(stdscr, msg)
        elif choice == 1:
            new_ou = prompt_input(stdscr, "Nom de la nouvelle OU enfant:")
            result = create_ou_under(samdb, ou_dn, new_ou)
            display_message(stdscr, result)
        elif choice == 2:
            confirm = prompt_input(stdscr, "Confirmez la suppression (O/N):")
            if confirm.lower() == "o":
                result = delete_ou_dn(samdb, ou_dn)
                display_message(stdscr, result)
                break  # On sort après suppression
        elif choice == 3:
            new_name = prompt_input(stdscr, "Nouveau nom pour cette OU:")
            result = rename_ou_dn(samdb, ou_dn, new_name)
            display_message(stdscr, result)
            # Mise à jour du node après renommage
            node["name"] = new_name
        elif choice == 4:
            break

# --- SOUS-MENUS CLASSIQUES ---
def group_menu(stdscr, domain_info):
    """Menu de gestion des groupes."""
    domain_dn = domain_info["domain_dn"]
    samdb = domain_info["samdb"]
    while True:
        options = ["Lister les groupes", "Créer un groupe", "Supprimer un groupe",
                   "Ajouter un utilisateur à un groupe", "Retirer un utilisateur d'un groupe", "Retour"]
        choice = display_menu(stdscr, "Gestion des groupes", options)
        if choice == 0:
            result = list_groups(samdb, domain_dn)
        elif choice == 1:
            group_name = prompt_input(stdscr, "Nom du groupe à créer:")
            result = create_group(samdb, domain_dn, group_name)
        elif choice == 2:
            group_name = prompt_input(stdscr, "Nom du groupe à supprimer:")
            result = delete_group(samdb, domain_dn, group_name)
        elif choice == 3:
            group_name = prompt_input(stdscr, "Nom du groupe:")
            user_name = prompt_input(stdscr, "Nom de l'utilisateur à ajouter:")
            result = add_user_to_group(samdb, domain_dn, group_name, user_name)
        elif choice == 4:
            group_name = prompt_input(stdscr, "Nom du groupe:")
            user_name = prompt_input(stdscr, "Nom de l'utilisateur à retirer:")
            result = remove_user_from_group(samdb, domain_dn, group_name, user_name)
        elif choice == 5:
            break
        display_message(stdscr, result if isinstance(result, str) else "\n".join(result))

def user_menu(stdscr, domain_info):
    """Menu de gestion des utilisateurs."""
    domain_dn = domain_info["domain_dn"]
    samdb = domain_info["samdb"]
    while True:
        options = ["Lister les utilisateurs", "Créer un utilisateur", "Supprimer un utilisateur",
                   "Réinitialiser le mot de passe", "Modifier un attribut utilisateur", "Retour"]
        choice = display_menu(stdscr, "Gestion des utilisateurs", options)
        if choice == 0:
            result = list_users(samdb, domain_dn)
        elif choice == 1:
            user_name = prompt_input(stdscr, "Nom du nouvel utilisateur:")
            password = prompt_input(stdscr, "Mot de passe:", echo=False)
            result = create_user(samdb, domain_dn, user_name, password)
        elif choice == 2:
            user_name = prompt_input(stdscr, "Nom de l'utilisateur à supprimer:")
            result = delete_user(samdb, domain_dn, user_name)
        elif choice == 3:
            user_name = prompt_input(stdscr, "Nom de l'utilisateur:")
            new_password = prompt_input(stdscr, "Nouveau mot de passe:", echo=False)
            result = reset_password(samdb, domain_dn, user_name, new_password)
        elif choice == 4:
            user_name = prompt_input(stdscr, "Nom de l'utilisateur:")
            attribute = prompt_input(stdscr, "Attribut à modifier (ex: displayName):")
            value = prompt_input(stdscr, f"Nouvelle valeur pour {attribute}:")
            result = modify_user_attribute(samdb, domain_dn, user_name, attribute, value)
        elif choice == 5:
            break
        display_message(stdscr, result if isinstance(result, str) else "\n".join(result))

def gpo_menu(stdscr, domain_info):
    """Menu de gestion des GPOs."""
    domain_dn = domain_info["domain_dn"]
    samdb = domain_info["samdb"]
    while True:
        options = ["Lister les GPOs", "Créer un GPO", "Supprimer un GPO", "Retour"]
        choice = display_menu(stdscr, "Gestion des GPOs", options)
        if choice == 0:
            result = list_gpos(samdb, domain_dn)
        elif choice == 1:
            gpo_name = prompt_input(stdscr, "Nom du GPO à créer:")
            result = create_gpo(samdb, domain_dn, gpo_name)
        elif choice == 2:
            gpo_name = prompt_input(stdscr, "Nom du GPO à supprimer:")
            result = delete_gpo(samdb, domain_dn, gpo_name)
        elif choice == 3:
            break
        display_message(stdscr, result if isinstance(result, str) else "\n".join(result))

# --- MENU PRINCIPAL ---
def main_menu(stdscr, domain_info):
    """Menu principal de l'interface de gestion AD."""
    options = ["Navigation de l'arborescence des OUs", "Gestion des groupes",
               "Gestion des utilisateurs", "Gestion des GPOs", "Quitter"]
    while True:
        choice = display_menu(stdscr, f"Interface Samba AD - {domain_info['domain_name']}", options)
        if choice == 0:
            ou_tree_navigation_menu(stdscr, domain_info)
        elif choice == 1:
            group_menu(stdscr, domain_info)
        elif choice == 2:
            user_menu(stdscr, domain_info)
        elif choice == 3:
            gpo_menu(stdscr, domain_info)
        elif choice == 4:
            break

# --- LANCEMENT DE L'APPLICATION ---
if __name__ == "__main__":
    admin_user = input("[LOGIN] Entrez le nom d'utilisateur Samba AD : ")
    admin_password = getpass.getpass("[LOGIN] Entrez le mot de passe Samba AD : ")
    domain_info = detect_domain_settings(admin_user, admin_password)
    if isinstance(domain_info, str):
        print(domain_info)
    else:
        curses.wrapper(main_menu, domain_info)

import curses
import getpass
import subprocess
import textwrap
from samba.samdb import SamDB
from samba import credentials
from samba.param import LoadParm

# --- CONNEXION AU DOMAINE Samba AD ---
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
        return {"samdb": samdb, "domain_dn": domain_dn, "domain_name": domain_name}
    except Exception as e:
        return f"[ERROR] Connexion échouée : {e}"

# --- Fonction d'affichage sécurisée pour les listes ---
def safe_display(result):
    if isinstance(result, list):
        return "\n".join(x.decode('utf-8') if isinstance(x, bytes) else str(x) for x in result)
    else:
        return result

# --- Gestion des OUs ---
def list_ous(samdb, domain_dn):
    """Liste les Unités Organisationnelles (OUs) du domaine."""
    ous = samdb.search(base=domain_dn, expression="(objectClass=organizationalUnit)", attrs=["ou", "dn"])
    return [ou["ou"][0].decode('utf-8') if isinstance(ou["ou"][0], bytes) else ou["ou"][0] for ou in ous] if ous else []

def create_ou(samdb, domain_dn, ou_name):
    """Crée une nouvelle OU."""
    try:
        ou_dn = f"OU={ou_name},{domain_dn}"
        samdb.add({"dn": ou_dn, "objectClass": ["top", "organizationalUnit"]})
        return f"[OK] OU '{ou_name}' créée."
    except Exception as e:
        return f"[ERROR] Impossible de créer l'OU : {e}"

def delete_ou(samdb, domain_dn, ou_name):
    """Supprime une OU."""
    try:
        ou_dn = f"OU={ou_name},{domain_dn}"
        samdb.delete(ou_dn)
        return f"[OK] OU '{ou_name}' supprimée."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer l'OU : {e}"

# --- Gestion des groupes ---
def list_groups(samdb, domain_dn):
    """Liste les groupes présents dans CN=Users."""
    try:
        base = f"CN=Users,{domain_dn}"
        groups = samdb.search(base=base, expression="(objectClass=group)", attrs=["cn"])
        return [group["cn"][0] for group in groups] if groups else []
    except Exception as e:
        return f"[ERROR] {e}"

def create_group(samdb, domain_dn, group_name):
    """Crée un groupe."""
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        samdb.add({"dn": group_dn, "objectClass": ["top", "group"], "sAMAccountName": group_name})
        return f"[OK] Groupe '{group_name}' créé."
    except Exception as e:
        return f"[ERROR] Impossible de créer le groupe : {e}"

def delete_group(samdb, domain_dn, group_name):
    """Supprime un groupe."""
    try:
        group_dn = f"CN={group_name},CN=Users,{domain_dn}"
        samdb.delete(group_dn)
        return f"[OK] Groupe '{group_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer le groupe : {e}"

# --- Gestion des GPOs ---
def list_gpos(samdb, domain_dn):
    """Liste les GPOs du domaine."""
    gpo_base = f"CN=Policies,CN=System,{domain_dn}"
    gpos = samdb.search(base=gpo_base, expression="(objectClass=groupPolicyContainer)", attrs=["displayName"])
    return [gpo["displayName"][0].decode('utf-8') if isinstance(gpo["displayName"][0], bytes) else gpo["displayName"][0] for gpo in gpos] if gpos else []

def create_full_gpo(gpo_name):
    """
    Crée un GPO complet dans Samba AD en appelant:
       samba-tool gpo create <NomGPO>
    Cette commande crée l'objet GPO dans l'annuaire et met en place la structure SYSVOL associée.
    """
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
    """Supprime un GPO."""
    try:
        gpo_base = f"CN=Policies,CN=System,{domain_dn}"
        gpo_dn = f"CN={gpo_name},{gpo_base}"
        samdb.delete(gpo_dn)
        return f"[OK] GPO '{gpo_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer le GPO : {e}"

# --- Gestion des utilisateurs ---
def list_users(samdb, domain_dn):
    """Liste les utilisateurs du domaine."""
    users = samdb.search(base=domain_dn, expression="(objectClass=user)", attrs=["sAMAccountName"])
    return [user["sAMAccountName"][0].decode('utf-8') if isinstance(user["sAMAccountName"][0], bytes) else user["sAMAccountName"][0] 
            for user in users if user["sAMAccountName"][0].lower() != b"krbtgt"] if users else []

def create_user(samdb, domain_dn, user_name, password):
    """Crée un nouvel utilisateur."""
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
    """Supprime un utilisateur."""
    try:
        user_dn = f"CN={user_name},CN=Users,{domain_dn}"
        samdb.delete(user_dn)
        return f"[OK] Utilisateur '{user_name}' supprimé."
    except Exception as e:
        return f"[ERROR] Impossible de supprimer l'utilisateur : {e}"

# --- Construction de l'arbre des OUs ---
def build_ou_tree(samdb, domain_dn):
    """
    Construit un arbre hiérarchique des OUs.
    Chaque nœud est un dictionnaire avec les clés : 'name', 'dn', et 'children'.
    """
    ous = samdb.search(base=domain_dn, expression="(objectClass=organizationalUnit)", attrs=["ou", "dn"])
    nodes = {}
    for entry in ous:
        dn = entry.get("dn")
        if dn is None:
            continue
        dn_str = str(dn)
        name = entry.get("ou", ["(sans nom)"])[0]
        if isinstance(name, bytes):
            name = name.decode('utf-8')
        nodes[dn_str] = {"name": name, "dn": dn_str, "children": []}
    tree = []
    for dn_str, node in nodes.items():
        if "," in dn_str:
            parent_dn_str = dn_str.split(",", 1)[1]
            if parent_dn_str in nodes:
                nodes[parent_dn_str]["children"].append(node)
            else:
                tree.append(node)
        else:
            tree.append(node)
    return tree

def display_ou_tree(stdscr, tree, level=0, y=0):
    """
    Affiche l'arbre des OUs sur l'écran curses.
    """
    for node in tree:
        stdscr.addstr(y, level * 4, f"- {node['name']}")
        y += 1
        if node["children"]:
            y = display_ou_tree(stdscr, node["children"], level + 1, y)
    return y

def ou_tree_navigation_menu(stdscr, domain_info):
    """
    Affiche un menu de navigation pour l'arbre des OUs.
    """
    samdb = domain_info["samdb"]
    domain_dn = domain_info["domain_dn"]
    tree = build_ou_tree(samdb, domain_dn)
    stdscr.clear()
    stdscr.addstr(0, 0, "Arbre des Unités Organisationnelles", curses.A_BOLD)
    stdscr.addstr(1, 0, "=" * 50)
    display_ou_tree(stdscr, tree, level=0, y=3)
    stdscr.addstr(20, 0, "[Appuyez sur une touche pour revenir au menu...]")
    stdscr.refresh()
    stdscr.getch()

# --- Interface Curses ---
def display_menu(stdscr, title, options):
    """Affiche un menu et retourne l'option sélectionnée."""
    current_row = 0
    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, f"[ {title} ]", curses.A_BOLD)
        stdscr.addstr(1, 0, "=" * 50)
        for idx, option in enumerate(options):
            if idx == current_row:
                stdscr.addstr(idx + 3, 0, f"> {option}", curses.A_REVERSE)
            else:
                stdscr.addstr(idx + 3, 0, f"- {option}")
        stdscr.refresh()
        key = stdscr.getch()
        if key == curses.KEY_UP and current_row > 0:
            current_row -= 1
        elif key == curses.KEY_DOWN and current_row < len(options) - 1:
            current_row += 1
        elif key in [10, 13]:  # Entrée
            return current_row

def prompt_input(stdscr, prompt, y=2, x=0, echo=True, max_len=40):
    """Affiche une invite et récupère la saisie de l'utilisateur."""
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

# --- Sous-menus ---
def ou_menu(stdscr, domain_info):
    """Menu pour gérer les OUs."""
    options = ["Lister les OUs", "Créer une OU", "Supprimer une OU", "Navigation arbre OU", "Retour"]
    while True:
        choice = display_menu(stdscr, "Gestion des OUs", options)
        if choice == 0:
            result = list_ous(domain_info["samdb"], domain_info["domain_dn"])
        elif choice == 1:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom de la nouvelle OU: ")
            curses.echo()
            ou_name = stdscr.getstr(2, 40, 20).decode('utf-8')
            curses.noecho()
            result = create_ou(domain_info["samdb"], domain_info["domain_dn"], ou_name)
        elif choice == 2:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom de l'OU à supprimer: ")
            curses.echo()
            ou_name = stdscr.getstr(2, 40, 20).decode('utf-8')
            curses.noecho()
            result = delete_ou(domain_info["samdb"], domain_info["domain_dn"], ou_name)
        elif choice == 3:
            ou_tree_navigation_menu(stdscr, domain_info)
            continue
        elif choice == 4:
            break
        stdscr.clear()
        stdscr.addstr(2, 0, safe_display(result))
        stdscr.addstr(4, 0, "[Appuyez sur une touche pour continuer...]")
        stdscr.refresh()
        stdscr.getch()

def group_menu(stdscr, domain_info):
    """Menu pour gérer les groupes."""
    options = ["Lister les groupes", "Créer un groupe", "Supprimer un groupe", "Retour"]
    while True:
        choice = display_menu(stdscr, "Gestion des groupes", options)
        if choice == 0:
            result = list_groups(domain_info["samdb"], domain_info["domain_dn"])
        elif choice == 1:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom du groupe à créer: ")
            curses.echo()
            group_name = stdscr.getstr(2, 40, 20).decode('utf-8')
            curses.noecho()
            result = create_group(domain_info["samdb"], domain_info["domain_dn"], group_name)
        elif choice == 2:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom du groupe à supprimer: ")
            curses.echo()
            group_name = stdscr.getstr(2, 40, 20).decode('utf-8')
            curses.noecho()
            result = delete_group(domain_info["samdb"], domain_info["domain_dn"], group_name)
        elif choice == 3:
            break
        stdscr.clear()
        stdscr.addstr(2, 0, safe_display(result))
        stdscr.addstr(4, 0, "[Appuyez sur une touche pour continuer...]")
        stdscr.refresh()
        stdscr.getch()

def gpo_menu(stdscr, domain_info):
    """Menu pour gérer les GPOs."""
    options = ["Lister les GPOs", "Créer un GPO complet", "Supprimer un GPO", "Retour"]
    while True:
        choice = display_menu(stdscr, "Gestion des GPOs", options)
        if choice == 0:
            result = list_gpos(domain_info["samdb"], domain_info["domain_dn"])
        elif choice == 1:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom du GPO à créer: ")
            curses.echo()
            gpo_name = stdscr.getstr(2, 35, 20).decode('utf-8')
            curses.noecho()
            result = create_full_gpo(gpo_name)
        elif choice == 2:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom du GPO à supprimer: ")
            curses.echo()
            gpo_name = stdscr.getstr(2, 35, 20).decode('utf-8')
            curses.noecho()
            result = delete_gpo(domain_info["samdb"], domain_info["domain_dn"], gpo_name)
        elif choice == 3:
            break
        display_message(stdscr, safe_display(result))


def user_menu(stdscr, domain_info):
    """Menu pour gérer les utilisateurs."""
    options = ["Lister les utilisateurs", "Créer un utilisateur", "Supprimer un utilisateur", "Retour"]
    while True:
        choice = display_menu(stdscr, "Gestion des utilisateurs", options)
        if choice == 0:
            result = list_users(domain_info["samdb"], domain_info["domain_dn"])
        elif choice == 1:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom de l'utilisateur à créer: ")
            curses.echo()
            user_name = stdscr.getstr(2, 45, 20).decode('utf-8')
            stdscr.addstr(3, 0, "Entrez le mot de passe: ")
            user_password = stdscr.getstr(3, 25, 20).decode('utf-8')
            curses.noecho()
            result = create_user(domain_info["samdb"], domain_info["domain_dn"], user_name, user_password)
        elif choice == 2:
            stdscr.clear()
            stdscr.addstr(2, 0, "Entrez le nom de l'utilisateur à supprimer: ")
            curses.echo()
            user_name = stdscr.getstr(2, 45, 20).decode('utf-8')
            curses.noecho()
            result = delete_user(domain_info["samdb"], domain_info["domain_dn"], user_name)
        elif choice == 3:
            break
        stdscr.clear()
        stdscr.addstr(2, 0, safe_display(result))
        stdscr.addstr(4, 0, "[Appuyez sur une touche pour continuer...]")
        stdscr.refresh()
        stdscr.getch()

# --- Menu principal ---
def main_menu(stdscr, domain_info):
    """Affiche le menu principal et dirige vers les sous-menus."""
    options = [
        "Gestion des OUs",
        "Gestion des GPOs",
        "Gestion des groupes",
        "Gestion des utilisateurs",
        "Quitter"
    ]
    while True:
        choice = display_menu(stdscr, f"Interface Samba AD - {domain_info['domain_name']}", options)
        if choice == 0:
            ou_menu(stdscr, domain_info)
        elif choice == 1:
            gpo_menu(stdscr, domain_info)
        elif choice == 2:
            group_menu(stdscr, domain_info)
        elif choice == 3:
            user_menu(stdscr, domain_info)
        elif choice == 4:
            break

# --- Lancer l'application ---
if __name__ == "__main__":
    admin_user = input("[LOGIN] Entrez le nom d'utilisateur Samba AD : ")
    admin_password = getpass.getpass("[LOGIN] Entrez le mot de passe Samba AD : ")
    domain_info = detect_domain_settings(admin_user, admin_password)
    if isinstance(domain_info, str):
        print(domain_info)
    else:
        curses.wrapper(main_menu, domain_info)

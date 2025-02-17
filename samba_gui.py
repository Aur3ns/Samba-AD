import curses
import os
from samba.samdb import SamDB
from samba import credentials
from samba.param import LoadParm


def detect_domain_settings():
    """Détection automatique des paramètres de domaine."""
    lp = LoadParm()
    creds = credentials.Credentials()
    
    try:
        samdb = SamDB(url="ldap://localhost", session_info=creds.get_session_info(), lp=lp)
        domain_dn = samdb.search(base="", scope=0, attrs=["defaultNamingContext"])[0]["defaultNamingContext"][0]
        return {
            "samdb": samdb,
            "domain_dn": domain_dn,
            "domain_name": samdb.search(base=domain_dn, expression="(objectClass=domain)", attrs=["dc"])[0]["dc"][0]
        }
    except Exception as e:
        return f"Erreur lors de la détection du domaine : {e}"


def list_ous(samdb):
    """Liste les Unités Organisationnelles (OUs) du domaine."""
    ous = samdb.search(base="DC=example,DC=com", expression="(objectClass=organizationalUnit)", attrs=["ou"])
    return [ou["ou"][0] for ou in ous]


def export_list_to_file(filename, data):
    """Export la liste dans un fichier texte."""
    with open(filename, "w") as file:
        file.write("\n".join(data))
    return f"Liste exportée avec succès dans le fichier {filename}."


def list_acls(samdb, object_dn):
    """Liste les permissions ACL sur un objet donné."""
    try:
        acls = samdb.search(base=object_dn, attrs=["ntSecurityDescriptor"])
        if not acls:
            return "Aucune ACL trouvée."
        
        # Affichage des ACLs brutes pour le moment (simplifiable)
        acl_info = acls[0]["ntSecurityDescriptor"][0]
        return f"ACLs sur {object_dn} :\n{acl_info}"
    except Exception as e:
        return f"Erreur lors de la récupération des ACLs : {e}"


def input_dialog(stdscr, prompt):
    """Affiche un champ de saisie."""
    curses.echo()
    stdscr.addstr(0, 0, prompt)
    stdscr.refresh()
    user_input = stdscr.getstr(1, 0, 50).decode("utf-8")
    curses.noecho()
    return user_input


def main(stdscr):
    """Interface principale en mode curses."""
    curses.curs_set(0)
    stdscr.clear()
    curses.start_color()
    curses.init_pair(1, curses.COLOR_YELLOW, curses.COLOR_BLUE)
    curses.init_pair(2, curses.COLOR_GREEN, curses.COLOR_BLACK)
    curses.init_pair(3, curses.COLOR_RED, curses.COLOR_BLACK)

    domain_info = detect_domain_settings()
    if isinstance(domain_info, str):
        stdscr.addstr(0, 0, domain_info, curses.color_pair(3))
        stdscr.refresh()
        stdscr.getch()
        return

    samdb = domain_info["samdb"]

    menu = [
        "Lister les OUs", 
        "Exporter la liste des OUs", 
        "Lister les ACLs d'une OU", 
        "Exporter la liste des GPOs", 
        "Quitter"
    ]
    current_row = 0

    while True:
        stdscr.clear()
        stdscr.addstr(0, 0, f"Interface Samba AD - Domaine : {domain_info['domain_name']} (Mode CLI Rétro)", curses.A_BOLD | curses.color_pair(1))
        stdscr.addstr(1, 0, "=" * 60, curses.color_pair(1))
        
        for idx, row in enumerate(menu):
            if idx == current_row:
                stdscr.addstr(idx + 3, 0, f"> {row}", curses.A_REVERSE | curses.color_pair(2))
            else:
                stdscr.addstr(idx + 3, 0, row, curses.color_pair(1))

        stdscr.refresh()
        key = stdscr.getch()

        if key == curses.KEY_UP and current_row > 0:
            current_row -= 1
        elif key == curses.KEY_DOWN and current_row < len(menu) - 1:
            current_row += 1
        elif key == curses.KEY_ENTER or key in [10, 13]:
            if current_row == len(menu) - 1:  # Quitter
                break
            elif current_row == 0:  # Lister les OUs
                stdscr.clear()
                stdscr.addstr(0, 0, "Liste des Unités Organisationnelles (OUs) :", curses.A_BOLD)
                ous = list_ous(samdb)
                for idx, ou in enumerate(ous):
                    stdscr.addstr(idx + 2, 0, f"- {ou}")
                stdscr.addstr(len(ous) + 3, 0, "Appuyez sur une touche pour revenir au menu.")
                stdscr.refresh()
                stdscr.getch()
            elif current_row == 1:  # Exporter la liste des OUs
                stdscr.clear()
                ous = list_ous(samdb)
                result = export_list_to_file("rapport_OUs.txt", ous)
                stdscr.addstr(3, 0, result)
                stdscr.addstr(5, 0, "Appuyez sur une touche pour revenir au menu.")
                stdscr.refresh()
                stdscr.getch()
            elif current_row == 2:  # Lister les ACLs d'une OU
                stdscr.clear()
                ou_name = input_dialog(stdscr, "Nom de l'OU : ")
                ous = samdb.search(base="DC=example,DC=com", expression=f"(ou={ou_name})", attrs=["dn"])
                if not ous:
                    result = f"OU '{ou_name}' introuvable."
                else:
                    result = list_acls(samdb, ous[0]["dn"])
                stdscr.addstr(3, 0, result[:1000])  # Limite d'affichage pour curses
                stdscr.addstr(7, 0, "Appuyez sur une touche pour revenir au menu.")
                stdscr.refresh()
                stdscr.getch()
            elif current_row == 3:  # Exporter la liste des GPOs
                stdscr.clear()
                gpos = samdb.search(base="CN=Policies,CN=System,DC=example,DC=com", expression="(objectClass=groupPolicyContainer)", attrs=["displayName"])
                gpo_list = [gpo["displayName"][0] for gpo in gpos]
                result = export_list_to_file("rapport_GPOs.txt", gpo_list)
                stdscr.addstr(3, 0, result)
                stdscr.addstr(5, 0, "Appuyez sur une touche pour revenir au menu.")
                stdscr.refresh()
                stdscr.getch()


if __name__ == "__main__":
    curses.wrapper(main)

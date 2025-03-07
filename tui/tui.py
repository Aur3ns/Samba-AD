import curses
import getpass
import time
from samba_ad import (
    detect_domain_settings,
    create_ou, delete_ou,
    list_ous, list_groups, create_group, delete_group,
    list_gpos, create_full_gpo, delete_gpo,
    list_users, create_user, delete_user,
    list_computers, create_computer, delete_computer, move_computer,
    refresh_data,
    modify_object, get_object_attributes, search_objects, move_object, rename_object
)

# --- Initialisation des couleurs ---
def init_colors():
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        # Définition de quelques paires de couleurs
        curses.init_pair(1, curses.COLOR_CYAN, -1)      # Pour le header et spinner
        curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Pour l'onglet actif
        curses.init_pair(3, curses.COLOR_WHITE, curses.COLOR_BLUE)   # Pour la sidebar (élément sélectionné)
        curses.init_pair(4, curses.COLOR_YELLOW, -1)     # Pour la barre de statut
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)    # Pour les séparateurs

# --- Spinner animé dans le header ---
def get_spinner():
    spinner_frames = ["|", "/", "-", "\\"]
    return spinner_frames[int(time.time() * 4) % len(spinner_frames)]

# --- Animation d'introduction ---
def animate_intro(stdscr):
    frames = [
        r"""
  ____                   _             
 / ___| _ __   __ _  ___| | ____ _  
 \___ \| '_ \ / _` |/ __| |/ / _` | 
  ___) | |_) | (_| | (__|   < (_| | 
 |____/| .__/ \__,_|\___|_|\_\__,_| 
       |_|                         
        """,
        r"""
  ____                   _             
 / ___| _ __   __ _  ___| | ____ _  
 \___ \| '_ \ / _` |/ __| |/ / _` | 
  ___) | |_) | (_| | (__|   < (_| | 
 |____/| .__/ \__,_|\___|_|\_\__,_| 
       |_|         ~~~            
        """,
        r"""
  ____                   _             
 / ___| _ __   __ _  ___| | ____ _  
 \___ \| '_ \ / _` |/ __| |/ / _` | 
  ___) | |_) | (_| | (__|   < (_| | 
 |____/| .__/ \__,_|\___|_|\_\__,_| 
       |_|   * Bienvenue *        
        """
    ]
    max_y, max_x = stdscr.getmaxyx()
    for frame in frames:
        stdscr.erase()
        lines = frame.strip("\n").splitlines()
        start_y = max((max_y - len(lines)) // 2, 0)
        for i, line in enumerate(lines):
            stdscr.addstr(start_y + i, max((max_x - len(line)) // 2, 0), line, curses.A_BOLD)
        stdscr.refresh()
        curses.napms(700)
    stdscr.erase()
    stdscr.refresh()

# --- Header avec ASCII art, informations et spinner ---
def draw_ascii_header(win, domain_info):
    win.clear()
    ascii_art = [
        "  ____                   _             _     _    ",
        " / ___| _ __   __ _  ___| | ____ _  __| | __| |   ",
        " \\___ \\| '_ \\ / _` |/ __| |/ / _` |/ _` |/ _` |   ",
        "  ___) | |_) | (_| | (__|   < (_| | (_| | (_| |   ",
        " |____/| .__/ \\__,_|\\___|_|\\_\\__,_|\\__,_|\\__,_|   "
    ]
    max_y, max_x = win.getmaxyx()
    start_y = 1
    for i, line in enumerate(ascii_art):
        win.addstr(start_y + i, max((max_x - len(line)) // 2, 0),
                   line, curses.color_pair(1) | curses.A_BOLD)
    info_str = f"Domaine : {domain_info['domain_name']}    Utilisateur : {domain_info['user']}"
    win.addstr(start_y + len(ascii_art) + 1,
               max((max_x - len(info_str)) // 2, 0),
               info_str, curses.A_BOLD)
    spinner = get_spinner()
    win.addstr(0, max_x - 3, spinner, curses.color_pair(1) | curses.A_BOLD)
    win.hline(start_y + len(ascii_art) + 2, 0, curses.ACS_HLINE, max_x)
    win.refresh()

# --- Barre d'onglets améliorée ---
def draw_tab_bar(win, current_tab, tabs):
    win.clear()
    max_y, max_x = win.getmaxyx()
    x = 2
    for idx, tab in enumerate(tabs):
        if idx == current_tab:
            win.addstr(0, x, f" {tab} ", curses.color_pair(2) | curses.A_BOLD)
        else:
            win.addstr(0, x, f" {tab} ")
        x += len(tab) + 3
    win.hline(1, 0, curses.ACS_HLINE, max_x)
    win.refresh()

# --- Barre de statut mise à jour ---
def draw_status_bar(win, message):
    win.clear()
    max_y, max_x = win.getmaxyx()
    status = message if message else (
        "F1: Aide | F5: Actualiser | /: Filtrer | c: Créer | d: Supprimer | "
        "a: Attributs | m: Modifier | r: Renommer | v: Déplacer | S: Recherche | "
        "←/→: Onglets | ↑/↓: Navigation | ESC: Quitter"
    )
    win.addstr(0, 0, status[:max_x-1], curses.color_pair(4))
    win.refresh()

# --- Gestion des éléments par onglet ---
def get_items_for_tab(current_tab, data):
    if current_tab == 0:  # Dashboard
        return list(data['dashboard'].items())
    elif current_tab == 1:
        return data['ous']
    elif current_tab == 2:
        return data['groupes'] if isinstance(data['groupes'], list) else []
    elif current_tab == 3:
        return data['gpos']
    elif current_tab == 4:
        return data['users']
    elif current_tab == 5:
        return data['computers']
    elif current_tab == 6:
        # Onglet Recherche avancée
        return data.get('recherche', [])
    return []

# --- Sidebar avec bordure et sélection colorée ---
def draw_sidebar(win, current_tab, data, selected_index, filter_str):
    win.clear()
    items = get_items_for_tab(current_tab, data)
    if filter_str:
        items = [item for item in items if filter_str.lower() in str(item).lower()]
    for idx, item in enumerate(items):
        # Pour l'onglet Recherche, afficher le DN de l'objet
        if current_tab == 6 and isinstance(item, dict) and "dn" in item:
            display_text = item["dn"]
        else:
            display_text = f"{item}" if current_tab != 0 else f"{item[0]}: {item[1]}"
        if idx == selected_index:
            win.addstr(idx+1, 1, display_text, curses.color_pair(3))
        else:
            win.addstr(idx+1, 1, display_text)
    win.box()
    win.refresh()

# --- Panneau de contenu amélioré ---
def draw_content(win, current_tab, data, selected_index, filter_str):
    win.clear()
    items = get_items_for_tab(current_tab, data)
    if filter_str:
        items = [item for item in items if filter_str.lower() in str(item).lower()]
    if items:
        selected_item = items[selected_index]
        if current_tab == 0:
            details = f"{selected_item[0]} : {selected_item[1]}"
        elif current_tab == 6 and isinstance(selected_item, dict):
            # Affichage formaté pour un résultat de recherche
            details = "\n".join(f"{k}: {v}" for k, v in selected_item.items())
        else:
            details = f"Nom : {selected_item}"
        win.addstr(1, 2, details)
    else:
        win.addstr(1, 2, "Aucun élément")
    win.box()
    win.refresh()

# --- Affichage d'une fenêtre modale texte (lecture seule) ---
def display_modal_text(stdscr, title, text):
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    lines = text.splitlines()
    height = len(lines) + 4
    width = max(max((len(line) for line in lines), default=0), len(title)) + 4
    win = curses.newwin(height, width, max((max_y-height)//2, 0), max((max_x-width)//2, 0))
    win.box()
    win.addstr(0, 2, title, curses.A_BOLD)
    for i, line in enumerate(lines):
        win.addstr(i+2, 2, line)
    win.refresh()
    win.getch()
    curses.noecho()

# --- Fonctions modales pour saisie ---
def modal_input(stdscr, title, prompt):
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = max(len(prompt) + 20, 40)
    win = curses.newwin(5, width, max_y//2 - 2, (max_x - width)//2)
    win.box()
    win.addstr(0, 2, title, curses.A_BOLD)
    win.addstr(2, 2, prompt)
    win.refresh()
    input_val = win.getstr(2, len(prompt) + 3, 50).decode('utf-8')
    curses.noecho()
    return input_val

def modal_input_multiple(stdscr, title, prompts):
    responses = {}
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = max(max((len(p) for p in prompts)) + 20, 50)
    height = len(prompts) + 4
    win = curses.newwin(height, width, max_y//2 - height//2, (max_x - width)//2)
    win.box()
    win.addstr(0, 2, title, curses.A_BOLD)
    for idx, prompt in enumerate(prompts):
        win.addstr(idx+2, 2, prompt)
        win.refresh()
        resp = win.getstr(idx+2, len(prompt) + 3, 50).decode('utf-8')
        responses[prompt] = resp
    curses.noecho()
    return responses

def modal_confirm(stdscr, prompt):
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = len(prompt) + 10
    win = curses.newwin(3, width, max_y//2 - 1, (max_x - width)//2)
    win.box()
    win.addstr(1, 2, prompt)
    win.refresh()
    ch = win.getch()
    curses.noecho()
    return (chr(ch).lower() == 'y')

# --- Fonction utilitaire pour déduire le DN de l'objet sélectionné ---
def get_dn_for_selected(current_tab, selected_item, domain_info):
    dn = None
    if current_tab == 1:
        dn = f"OU={selected_item},{domain_info['domain_dn']}"
    elif current_tab == 2:
        dn = f"CN={selected_item},CN=Users,{domain_info['domain_dn']}"
    elif current_tab == 3:
        dn = f"CN={selected_item},CN=Policies,CN=System,{domain_info['domain_dn']}"
    elif current_tab == 4:
        dn = f"CN={selected_item},CN=Users,{domain_info['domain_dn']}"
    elif current_tab == 5:
        dn = f"CN={selected_item},CN=Computers,{domain_info['domain_dn']}"
    elif current_tab == 6 and isinstance(selected_item, dict):
        dn = selected_item.get("dn", str(selected_item))
    return dn

# --- Gestion des actions avancées ---
def handle_create_action(stdscr, current_tab, domain_info):
    if current_tab == 1:
        name = modal_input(stdscr, "Création d'OU", "Nom de la nouvelle OU: ")
        if name:
            return create_ou(domain_info["samdb"], domain_info["domain_dn"], name)
    elif current_tab == 2:
        name = modal_input(stdscr, "Création de Groupe", "Nom du nouveau groupe: ")
        if name:
            return create_group(domain_info["samdb"], domain_info["domain_dn"], name)
    elif current_tab == 3:
        name = modal_input(stdscr, "Création de GPO", "Nom du nouveau GPO: ")
        if name:
            return create_full_gpo(name)
    elif current_tab == 4:
        resp = modal_input_multiple(stdscr, "Création d'Utilisateur", ["Nom d'utilisateur: ", "Mot de passe: "])
        if resp:
            username = resp.get("Nom d'utilisateur: ")
            password = resp.get("Mot de passe: ")
            if username and password:
                return create_user(domain_info["samdb"], domain_info["domain_dn"], username, password)
    elif current_tab == 5:
        name = modal_input(stdscr, "Création d'Ordinateur", "Nom de l'ordinateur: ")
        if name:
            return create_computer(domain_info["samdb"], domain_info["domain_dn"], name)
    return "Opération annulée."

def handle_delete_action(stdscr, current_tab, data, selected_index, domain_info):
    items = get_items_for_tab(current_tab, data)
    if not items:
        return "Aucun élément à supprimer."
    selected_item = items[selected_index]
    confirm = modal_confirm(stdscr, f"Supprimer {selected_item}? (y/n): ")
    if confirm:
        if current_tab == 1:
            return delete_ou(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 2:
            return delete_group(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 3:
            return delete_gpo(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 4:
            return delete_user(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 5:
            return delete_computer(domain_info["samdb"], domain_info["domain_dn"], selected_item)
    return "Opération annulée."

# --- Boucle principale du TUI ---
def main_tui(stdscr, domain_info):
    init_colors()
    animate_intro(stdscr)
    curses.curs_set(0)
    stdscr.nodelay(False)
    stdscr.timeout(100)
    # Onglets : ajout de l'onglet Recherche (index 6)
    tabs = ["Dashboard", "OUs", "Groupes", "GPOs", "Utilisateurs", "Ordinateurs", "Recherche"]
    current_tab = 0
    selected_index = 0
    filter_str = ""
    notification = ""
    data = refresh_data(domain_info)
    # Initialisation pour l'onglet Recherche
    data['recherche'] = []

    max_y, max_x = stdscr.getmaxyx()

    header_height = 9    # pour l'ASCII art + info
    tab_height = 3
    status_height = 1
    content_height = max_y - header_height - tab_height - status_height
    sidebar_width = max_x // 3
    content_width = max_x - sidebar_width

    header_win = stdscr.subwin(header_height, max_x, 0, 0)
    tab_win = stdscr.subwin(tab_height, max_x, header_height, 0)
    main_win = stdscr.subwin(content_height, max_x, header_height + tab_height, 0)
    status_win = stdscr.subwin(status_height, max_x, max_y - status_height, 0)

    sidebar_win = main_win.derwin(content_height, sidebar_width, 0, 0)
    content_win = main_win.derwin(content_height, content_width, 0, sidebar_width)

    while True:
        stdscr.erase()

        draw_ascii_header(header_win, domain_info)
        draw_tab_bar(tab_win, current_tab, tabs)
        draw_sidebar(sidebar_win, current_tab, data, selected_index, filter_str)
        draw_content(content_win, current_tab, data, selected_index, filter_str)
        draw_status_bar(status_win, notification)

        stdscr.refresh()
        key = stdscr.getch()

        if key == curses.KEY_LEFT:
            current_tab = (current_tab - 1) % len(tabs)
            selected_index = 0
            filter_str = ""
        elif key == curses.KEY_RIGHT:
            current_tab = (current_tab + 1) % len(tabs)
            selected_index = 0
            filter_str = ""
        elif key == curses.KEY_UP:
            selected_index = max(selected_index - 1, 0)
        elif key == curses.KEY_DOWN:
            items = get_items_for_tab(current_tab, data)
            if filter_str:
                items = [item for item in items if filter_str.lower() in str(item).lower()]
            selected_index = min(selected_index + 1, len(items) - 1) if items else 0
        elif key == ord('/'):
            filter_str = prompt_filter(stdscr)
            selected_index = 0
        elif key == ord('c'):
            notification = handle_create_action(stdscr, current_tab, domain_info)
            data = refresh_data(domain_info)
            selected_index = 0
        elif key == ord('d'):
            notification = handle_delete_action(stdscr, current_tab, data, selected_index, domain_info)
            data = refresh_data(domain_info)
            selected_index = 0
        elif key == curses.KEY_F5:
            data = refresh_data(domain_info)
            notification = "Données actualisées."
        elif key == curses.KEY_F1:
            show_help(stdscr)
        # Actions avancées :
        elif key == ord('a'):
            # Afficher les attributs de l'objet sélectionné
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                attrs = get_object_attributes(domain_info["samdb"], dn)
                if isinstance(attrs, dict):
                    text = "\n".join(f"{k}: {v}" for k, v in attrs.items())
                else:
                    text = str(attrs)
                display_modal_text(stdscr, "Attributs de l'objet", text)
        elif key == ord('m'):
            # Modifier l'objet sélectionné
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                mod_str = modal_input(stdscr, "Modification", "Entrez modifications (attr=val;...): ")
                modifications = {}
                for pair in mod_str.split(';'):
                    if '=' in pair:
                        attr, val = pair.split('=', 1)
                        modifications[attr.strip()] = [val.strip()]
                notification = modify_object(domain_info["samdb"], dn, modifications)
        elif key == ord('r'):
            # Renommer l'objet sélectionné
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                new_rdn = modal_input(stdscr, "Renommer", "Entrez le nouveau RDN (ex: CN=nouveau_nom): ")
                notification = rename_object(domain_info["samdb"], dn, new_rdn)
        elif key == ord('v'):
            # Déplacer l'objet sélectionné
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                new_dn = modal_input(stdscr, "Déplacer", "Entrez le nouveau DN: ")
                notification = move_object(domain_info["samdb"], dn, new_dn)
        elif key == ord('S'):
            # Recherche avancée
            base_dn = modal_input(stdscr, "Recherche avancée", "Entrez la base DN (laisser vide = domaine par défaut): ")
            if not base_dn:
                base_dn = domain_info["domain_dn"]
            filter_expr = modal_input(stdscr, "Recherche avancée", "Entrez le filtre LDAP: ")
            attrs_str = modal_input(stdscr, "Recherche avancée", "Attributs (séparés par des virgules, laisser vide = tous): ")
            if attrs_str.strip():
                attrs = [a.strip() for a in attrs_str.split(',')]
            else:
                attrs = None
            results = search_objects(domain_info["samdb"], base_dn, filter_expr, attrs)
            data['recherche'] = results if isinstance(results, list) else []
            current_tab = 6
            selected_index = 0
            notification = f"{len(data['recherche'])} résultats trouvés."
        elif key == 27:  # ESC
            break

    stdscr.erase()
    stdscr.refresh()

if __name__ == "__main__":
    admin_user = input("[LOGIN] Entrez le nom d'utilisateur Samba AD : ")
    admin_password = getpass.getpass("[LOGIN] Entrez le mot de passe Samba AD : ")
    domain_info = detect_domain_settings(admin_user, admin_password)
    if isinstance(domain_info, str):
        print(domain_info)
    else:
        curses.wrapper(main_tui, domain_info)

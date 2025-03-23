import curses
import getpass
import time
import textwrap

# Import des fonctions Samba AD depuis samba_ad.py
from samba_ad import (
    detect_domain_settings,
    create_ou, delete_ou,
    list_ous, list_groups, create_group, delete_group,
    list_gpos, create_full_gpo, delete_gpo,
    list_users, create_user, delete_user,
    list_computers, create_computer, delete_computer, move_computer,
    refresh_data,
    modify_object, get_object_attributes, search_objects, move_object, rename_object,
    reset_password
)

# --- Fonctions utilitaires pour éviter les erreurs "addstr() returned ERR" ---
def safe_addstr(win, y, x, text, style=0):
    """
    Écrit la chaîne 'text' à la position (y, x) de la fenêtre 'win',
    en vérifiant qu’on ne dépasse pas les bornes.
    Tronque le texte si nécessaire.
    """
    max_y, max_x = win.getmaxyx()
    if 0 <= y < max_y and 0 <= x < max_x:
        if x + len(text) > max_x:
            text = text[:max_x - x]
        try:
            win.addstr(y, x, text, style)
        except curses.error:
            pass

def safe_hline(win, y, x, ch, n, style=0):
    """
    Dessine une ligne horizontale à la position (y, x),
    de longueur n, en vérifiant les bornes.
    """
    max_y, max_x = win.getmaxyx()
    if 0 <= y < max_y and 0 <= x < max_x:
        if x + n > max_x:
            n = max_x - x
        try:
            win.hline(y, x, ch, n, style)
        except curses.error:
            pass

# --- Couleurs et initialisation ---
def init_colors():
    if curses.has_colors():
        curses.start_color()
        curses.use_default_colors()
        curses.init_pair(1, curses.COLOR_CYAN, -1)       # Header/spinner
        curses.init_pair(2, curses.COLOR_BLACK, curses.COLOR_WHITE)  # Onglet actif
        curses.init_pair(3, curses.COLOR_WHITE, curses.COLOR_BLUE)   # Sidebar (élément sélectionné)
        curses.init_pair(4, curses.COLOR_YELLOW, -1)    # Barre de statut
        curses.init_pair(5, curses.COLOR_MAGENTA, -1)   # Optionnel

def get_spinner():
    """Renvoie un caractère de spinner en fonction du temps."""
    spinner_frames = ["|", "/", "-", "\\"]
    return spinner_frames[int(time.time() * 4) % len(spinner_frames)]

def animate_intro(stdscr):
    """Affiche une animation de chargement style 'System Booting'."""
    curses.curs_set(0)
    stdscr.clear()
    stdscr.refresh()
    loading_frames = [
        "[░░░░░░░░░░░░░░░░░░░░░░░░]   0%",
        "[▓░░░░░░░░░░░░░░░░░░░░░░░]   5%",
        "[▓▓░░░░░░░░░░░░░░░░░░░░░░]  10%",
        "[▓▓▓░░░░░░░░░░░░░░░░░░░░░]  15%",
        "[▓▓▓▓░░░░░░░░░░░░░░░░░░░░]  20%",
        "[▓▓▓▓▓░░░░░░░░░░░░░░░░░░░]  25%",
        "[▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░]  30%",
        "[▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░]  35%",
        "[▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░]  40%",
        "[▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░]  45%",
        "[▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░]  50%",
        "[▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░]  55%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░]  60%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░]  65%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░]  70%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░]  75%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░]  80%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░]  85%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░]  90%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░]  95%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░]  98%",
        "[▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓] 100%",
    ]
    max_y, max_x = stdscr.getmaxyx()
    for frame in loading_frames:
        stdscr.erase()
        center_y = max_y // 2
        safe_addstr(stdscr, center_y - 1, (max_x - len("SYSTEM BOOTING...")) // 2, "SYSTEM BOOTING...", curses.A_BOLD)
        safe_addstr(stdscr, center_y, (max_x - len(frame)) // 2, frame, curses.A_BOLD)
        safe_addstr(stdscr, center_y + 1, (max_x - len("PLEASE WAIT...")) // 2, "PLEASE WAIT...", curses.A_DIM)
        stdscr.refresh()
        time.sleep(0.2)
    stdscr.erase()
    stdscr.refresh()

def draw_ascii_header(win, domain_info):
    """Affiche l'ASCII art, le spinner et les infos de domaine/utilisateur en haut."""
    win.clear()
    ascii_art = [
        "	__  ______     ______ _   __       ",
        "  	/| )/  )/__)/  )__/(   /  /_| /__) ", 
        "  / |/(__// ( (  /  /__) (  (  |/ (   ",
        "                                      "
    ]
    max_y, max_x = win.getmaxyx()
    start_y = 1
    for i, line in enumerate(ascii_art):
        row = start_y + i
        col = max((max_x - len(line)) // 2, 0)
        safe_addstr(win, row, col, line, curses.color_pair(1) | curses.A_BOLD)
    info_str = f"Domaine : {domain_info['domain_name']}    Utilisateur : {domain_info['user']}"
    row = start_y + len(ascii_art) + 1
    col = max((max_x - len(info_str)) // 2, 0)
    safe_addstr(win, row, col, info_str, curses.A_BOLD)
    spinner = get_spinner()
    safe_addstr(win, 0, max_x - 3, spinner, curses.color_pair(1) | curses.A_BOLD)
    safe_hline(win, start_y + len(ascii_art) + 2, 0, curses.ACS_HLINE, max_x)
    win.refresh()

def draw_tab_bar(win, current_tab, tabs):
    """Affiche la barre d'onglets."""
    win.clear()
    max_y, max_x = win.getmaxyx()
    x = 2
    for idx, tab in enumerate(tabs):
        text = f" {tab} "
        if idx == current_tab:
            safe_addstr(win, 0, x, text, curses.color_pair(2) | curses.A_BOLD)
        else:
            safe_addstr(win, 0, x, text)
        x += len(text) + 1
    safe_hline(win, 1, 0, curses.ACS_HLINE, max_x)
    win.refresh()

def draw_status_bar(win, message):
    """
    Affiche la barre de statut en bas.
    Par défaut, on affiche "h = Aide | ESC = Quitter".
    """
    win.clear()
    max_y, max_x = win.getmaxyx()
    status = message if message else "h = Aide | ESC = Quitter"
    safe_addstr(win, 0, 0, status[:max_x-1], curses.color_pair(4))
    win.refresh()

def get_items_for_tab(current_tab, data):
    """Retourne la liste d'éléments correspondant à l'onglet courant."""
    if current_tab == 0:
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
        return data.get('recherche', [])
    return []

def draw_sidebar(win, current_tab, data, selected_index, filter_str):
    """Affiche la sidebar avec surbrillance sur l'élément sélectionné."""
    win.clear()
    items = get_items_for_tab(current_tab, data)
    if filter_str:
        items = [item for item in items if filter_str.lower() in str(item).lower()]
    height, width = win.getmaxyx()
    max_len = width - 3
    if current_tab == 0:
        key_width = 20
        for idx, (key, value) in enumerate(items):
            line = f"{str(key).ljust(key_width)} : {value}"
            if len(line) > max_len:
                line = line[:max_len]
            style = curses.color_pair(3) if idx == selected_index else 0
            safe_addstr(win, idx + 1, 1, line, style)
    else:
        for idx, item in enumerate(items):
            if isinstance(item, dict):
                if current_tab == 1:
                    display_text = f"OU : {item.get('name', '')}"
                elif current_tab == 2:
                    display_text = f"Groupe : {item.get('name', '')}"
                elif current_tab == 3:
                    display_text = f"GPO : {item.get('name', '')}"
                elif current_tab == 4:
                    sam = item.get("sAMAccountName", "")
                    cn  = item.get("cn", "")
                    display_text = f"User : {sam} ({cn})"
                elif current_tab == 5:
                    display_text = f"PC : {item.get('name', '')}"
                elif current_tab == 6:
                    display_text = item.get("dn", str(item))
                else:
                    display_text = str(item)
            else:
                if current_tab == 1:
                    display_text = f"OU : {item}"
                elif current_tab == 2:
                    display_text = f"Groupe : {item}"
                elif current_tab == 3:
                    display_text = f"GPO : {item}"
                elif current_tab == 4:
                    display_text = f"Utilisateur : {item}"
                elif current_tab == 5:
                    display_text = f"Ordinateur : {item}"
                else:
                    display_text = str(item)
            if len(display_text) > max_len:
                display_text = display_text[:max_len]
            style = curses.color_pair(3) if idx == selected_index else 0
            safe_addstr(win, idx + 1, 1, display_text, style)
    win.box()
    win.refresh()

def draw_content(win, current_tab, data, selected_index, filter_str):
    """Affiche le contenu détaillé de l'élément sélectionné."""
    win.clear()
    height, width = win.getmaxyx()
    items = get_items_for_tab(current_tab, data)
    if filter_str:
        items = [item for item in items if filter_str.lower() in str(item).lower()]
    if items:
        selected_item = items[selected_index]
        if current_tab == 0:
            details = f"{selected_item[0]} : {selected_item[1]}"
        elif current_tab == 6 and isinstance(selected_item, dict):
            lines = [f"{k}: {v}" for k, v in selected_item.items()]
            details = "\n".join(lines)
        elif isinstance(selected_item, dict):
            lines = [f"{k}: {v}" for k, v in selected_item.items()]
            details = "\n".join(lines)
        else:
            details = f"Nom : {selected_item}"
    else:
        details = "Aucun élément"
    wrapped_lines = []
    for line in details.splitlines():
        sub_lines = textwrap.wrap(line, width=width - 4)
        if not sub_lines:
            wrapped_lines.append("")
        else:
            wrapped_lines.extend(sub_lines)
    max_width = width - 4
    row = 1
    for wline in wrapped_lines:
        if len(wline) > max_width:
            wline = wline[:max_width]
        if row >= height - 1:
            break
        safe_addstr(win, row, 2, wline)
        row += 1
    win.box()
    win.refresh()

def parse_samba_attrs(attrs):
    """
    Parse et formate clairement les attributs LDAP (Samba AD).
    Chaque attribut est affiché sur une ligne séparée.
    """
    lines = []
    for attr_name in sorted(attrs.keys()):
        values = attrs[attr_name]
        formatted_values = []
        for val in values:
            if hasattr(val, "get_value"):
                raw_val = val.get_value()
                if isinstance(raw_val, bytes):
                    try:
                        str_val = raw_val.decode("utf-8", errors="replace")
                    except:
                        str_val = repr(raw_val)
                else:
                    str_val = str(raw_val)
            elif isinstance(val, bytes):
                try:
                    str_val = val.decode("utf-8", errors="replace")
                except:
                    str_val = repr(val)
            else:
                str_val = str(val)
            str_val = str_val.replace("\r", "\\r").replace("\n", "\\n")
            formatted_values.append(str_val)
        if len(formatted_values) > 1:
            lines.append(f"{attr_name}:")
            for single_val in formatted_values:
                lines.append(f"  - {single_val}")
        else:
            lines.append(f"{attr_name}: {formatted_values[0]}")
    return "\n".join(lines)

def display_modal_text(stdscr, title, text):
    """Affiche une fenêtre modale scrollable (80% de l'écran)."""
    curses.noecho()
    max_y, max_x = stdscr.getmaxyx()
    height = max_y * 7 // 10
    width = max_x * 7 // 10
    start_y = (max_y - height) // 2
    start_x = (max_x - width) // 2
    wrapped_lines = []
    for line in text.splitlines():
        sub_lines = textwrap.wrap(line, width=width - 4)
        if not sub_lines:
            wrapped_lines.append("")
        else:
            wrapped_lines.extend(sub_lines)
    win = curses.newwin(height, width, start_y, start_x)
    win.box()
    truncated_title = title[:width - 4]
    safe_addstr(win, 0, 2, truncated_title, curses.A_BOLD)
    top_line = 0
    visible_height = height - 2
    while True:
        for r in range(1, height - 1):
            safe_addstr(win, r, 1, " " * (width - 2))
        row = 1
        for i in range(top_line, min(top_line + visible_height, len(wrapped_lines))):
            wline = wrapped_lines[i]
            if len(wline) > width - 4:
                wline = wline[:width - 4]
            safe_addstr(win, row, 2, wline)
            row += 1
        win.box()
        win.refresh()
        ch = stdscr.getch()
        if ch == curses.KEY_UP:
            top_line = max(top_line - 1, 0)
        elif ch == curses.KEY_DOWN:
            if top_line + visible_height < len(wrapped_lines):
                top_line += 1
        elif ch in (27, ord('q'), curses.KEY_EXIT):
            break

def modal_input(stdscr, title, prompt):
    """Fenêtre modale pour saisir une entrée."""
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = max(len(prompt) + 20, 50)
    height = 5
    start_y = max_y // 2 - 2
    start_x = (max_x - width) // 2
    win = curses.newwin(height, width, start_y, start_x)
    win.box()
    safe_addstr(win, 0, 2, title, curses.A_BOLD)
    safe_addstr(win, 2, 2, prompt)
    win.refresh()
    input_val = win.getstr(2, len(prompt) + 3, 100).decode('utf-8')
    curses.noecho()
    return input_val

def modal_input_multiple(stdscr, title, prompts):
    """Fenêtre modale pour saisir plusieurs entrées."""
    responses = {}
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = max(max((len(p) for p in prompts)) + 20, 60)
    height = len(prompts) + 4
    start_y = max_y // 2 - height // 2
    start_x = (max_x - width) // 2
    win = curses.newwin(height, width, start_y, start_x)
    win.box()
    safe_addstr(win, 0, 2, title, curses.A_BOLD)
    for idx, prompt in enumerate(prompts):
        safe_addstr(win, idx + 2, 2, prompt)
        win.refresh()
        resp = win.getstr(idx + 2, len(prompt) + 3, 100).decode('utf-8')
        responses[prompt] = resp
    curses.noecho()
    return responses

def modal_confirm(stdscr, prompt):
    """Fenêtre modale de confirmation (oui/non)."""
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = len(prompt) + 10
    height = 3
    start_y = max_y // 2 - 1
    start_x = (max_x - width) // 2
    win = curses.newwin(height, width, start_y, start_x)
    win.box()
    safe_addstr(win, 1, 2, prompt)
    win.refresh()
    ch = win.getch()
    curses.noecho()
    return (chr(ch).lower() == 'y')

def get_dn_for_selected(current_tab, selected_item, domain_info):
    """Construit le DN en fonction de l'onglet et de l'élément sélectionné."""
    dn = None
    if isinstance(selected_item, dict) and "dn" in selected_item:
        dn = selected_item["dn"]
    else:
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
        elif current_tab == 6:
            dn = str(selected_item)
    return dn

def handle_create_action(stdscr, current_tab, domain_info):
    """Création d'un objet selon l'onglet."""
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
    """Suppression d'un objet selon l'onglet."""
    items = get_items_for_tab(current_tab, data)
    if not items:
        return "Aucun élément à supprimer."
    selected_item = items[selected_index]
    confirm = modal_confirm(stdscr, f"Supprimer {selected_item}? (y/n): ")
    if confirm:
        if current_tab in (1, 2, 3, 4, 5):
            if current_tab == 1:
                return delete_ou(domain_info["samdb"], domain_info["domain_dn"], selected_item.get("name", selected_item))
            elif current_tab == 2:
                return delete_group(domain_info["samdb"], domain_info["domain_dn"], selected_item.get("name", selected_item))
            elif current_tab == 3:
                return delete_gpo(domain_info["samdb"], domain_info["domain_dn"], selected_item.get("name", selected_item))
            elif current_tab == 4:
                return delete_user(domain_info["samdb"], domain_info["domain_dn"], selected_item.get("sAMAccountName", selected_item))
            elif current_tab == 5:
                return delete_computer(domain_info["samdb"], domain_info["domain_dn"], selected_item.get("name", selected_item))
        elif current_tab == 6:
            dn = get_dn_for_selected(current_tab, selected_item, domain_info)
            if dn:
                try:
                    domain_info["samdb"].delete(dn)
                    return f"[OK] Objet '{dn}' supprimé."
                except Exception as e:
                    return f"[ERROR] Impossible de supprimer '{dn}': {e}"
    return "Opération annulée."

def main_tui(stdscr, domain_info):
    init_colors()
    animate_intro(stdscr)
    curses.curs_set(0)
    stdscr.nodelay(False)
    stdscr.timeout(100)

    header_height = 6
    tab_height = 3
    status_height = 1

    tabs = ["Dashboard", "OUs", "Groupes", "GPOs", "Utilisateurs", "Ordinateurs", "Recherche"]
    current_tab = 0
    selected_index = 0
    filter_str = ""
    notification = ""

    data = refresh_data(domain_info)
    data['recherche'] = []

    max_y, max_x = stdscr.getmaxyx()
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
            filter_str = modal_input(stdscr, "Filtrer", "Entrez une chaîne à filtrer: ")
            selected_index = 0
        elif key == ord('c'):
            notification = handle_create_action(stdscr, current_tab, domain_info)
            data = refresh_data(domain_info)
            data['recherche'] = []
            selected_index = 0
        elif key == ord('d'):
            notification = handle_delete_action(stdscr, current_tab, data, selected_index, domain_info)
            data = refresh_data(domain_info)
            data['recherche'] = []
            selected_index = 0
        elif key == ord('p'):
            if current_tab == 4:
                items = get_items_for_tab(current_tab, data)
                if items:
                    selected_item = items[selected_index]
                    username = selected_item.get("sAMAccountName", "")
                    if username:
                        new_pwd = modal_input(stdscr, "Réinitialiser mot de passe", f"Nouveau mot de passe pour {username}: ")
                        if new_pwd:
                            notification = reset_password(domain_info["samdb"], domain_info["domain_dn"], username, new_pwd)
        elif key == curses.KEY_F5:
            data = refresh_data(domain_info)
            data['recherche'] = []
            notification = "Données actualisées."
        elif key == ord('h'):
            show_help(stdscr)
        elif key == ord('a'):
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                if dn:
                    attrs = get_object_attributes(domain_info["samdb"], dn, all_attrs=False)
                    if isinstance(attrs, dict):
                        text = parse_samba_attrs(attrs)
                    else:
                        text = str(attrs)
                    display_modal_text(stdscr, "Attributs de l'objet", text)
        elif key == ord('t'):
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                if dn:
                    attrs = get_object_attributes(domain_info["samdb"], dn, all_attrs=True)
                    if isinstance(attrs, dict):
                        text = parse_samba_attrs(attrs)
                    else:
                        text = str(attrs)
                    display_modal_text(stdscr, "Attributs COMPLETS de l'objet", text)
        elif key == ord('m'):
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                if dn:
                    mod_str = modal_input(stdscr, "Modification", "Entrez modifications (attr=val;...): ")
                    modifications = {}
                    for pair in mod_str.split(';'):
                        if '=' in pair:
                            attr, val = pair.split('=', 1)
                            modifications[attr.strip()] = [val.strip()]
                    notification = modify_object(domain_info["samdb"], dn, modifications)
        elif key == ord('r'):
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                if dn:
                    new_rdn = modal_input(stdscr, "Renommer", "Entrez le nouveau RDN (ex: CN=nouveau_nom): ")
                    notification = rename_object(domain_info["samdb"], dn, new_rdn)
        elif key == ord('v'):
            items = get_items_for_tab(current_tab, data)
            if items:
                selected_item = items[selected_index]
                dn = get_dn_for_selected(current_tab, selected_item, domain_info)
                if dn:
                    new_dn = modal_input(stdscr, "Déplacer", "Entrez le nouveau DN: ")
                    notification = move_object(domain_info["samdb"], dn, new_dn)
        elif key == ord('S'):
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
        elif key == 27:
            break

    stdscr.erase()
    stdscr.refresh()

def show_help(stdscr):
    """Affiche une fenêtre d'aide avec les raccourcis clavier."""
    max_y, max_x = stdscr.getmaxyx()
    help_text = [
        "Aide - Raccourcis clavier:",
        "h  : Afficher cette aide",
        "F5 : Actualiser les données",
        "/  : Filtrer la liste",
        "c  : Créer un nouvel objet (selon l'onglet)",
        "d  : Supprimer l'objet sélectionné",
        "p  : Réinitialiser le mot de passe d’un utilisateur (onglet Utilisateurs)",
        "a  : Afficher un sous-ensemble d'attributs de l'objet",
        "t  : Afficher TOUS les attributs (risque de déconnexion si trop volumineux)",
        "m  : Modifier les attributs (attr=val;...)",
        "r  : Renommer l'objet (nouveau RDN)",
        "v  : Déplacer l'objet (nouveau DN)",
        "S  : Recherche avancée (base DN, filtre LDAP, attributs)",
        "←/→ : Changer d'onglet",
        "↑/↓ : Navigation dans la liste",
        "ESC : Quitter l'application",
        "",
        "Dans l'onglet 'Recherche', vous pouvez sélectionner un objet, puis",
        "utiliser les mêmes raccourcis (a, t, m, r, v, d, p) s'il possède un DN."
    ]
    height = len(help_text) + 4
    width = max(len(line) for line in help_text) + 4
    start_y = max((max_y - height) // 2, 0)
    start_x = max((max_x - width) // 2, 0)
    win = curses.newwin(height, width, start_y, start_x)
    win.box()
    for idx, line in enumerate(help_text):
        safe_addstr(win, idx + 1, 2, line)
    win.refresh()
    win.getch()

if __name__ == "__main__":
    admin_user = input("[LOGIN] Entrez le nom d'utilisateur Samba AD : ")
    admin_password = getpass.getpass("[LOGIN] Entrez le mot de passe Samba AD : ")
    domain_info = detect_domain_settings(admin_user, admin_password)
    if isinstance(domain_info, str):
        print(domain_info)
    else:
        curses.wrapper(main_tui, domain_info)

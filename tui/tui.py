import curses
import getpass
from samba_ad import (
    detect_domain_settings,
    create_ou, delete_ou,
    list_ous, list_groups, create_group, delete_group,
    list_gpos, create_full_gpo, delete_gpo,
    list_users, create_user, delete_user,
    list_computers, create_computer, delete_computer, move_computer,
    refresh_data
)

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
    return []

def draw_header(win, domain_info):
    win.clear()
    title = "Samba AD Management"
    domain_str = f"Domaine : {domain_info['domain_name']}"
    user_str = f"Utilisateur : {domain_info['user']}"
    win.addstr(0, 2, title, curses.A_BOLD)
    win.addstr(1, 2, domain_str)
    win.addstr(1, max(40, len(domain_str)+5), user_str)
    win.hline(2, 0, curses.ACS_HLINE, win.getmaxyx()[1])
    win.refresh()

def draw_tab_bar(win, current_tab, tabs):
    win.clear()
    x = 2
    for idx, tab in enumerate(tabs):
        if idx == current_tab:
            win.addstr(0, x, f"[{tab}]", curses.A_REVERSE)
        else:
            win.addstr(0, x, f" {tab} ")
        x += len(tab) + 3
    win.hline(1, 0, curses.ACS_HLINE, win.getmaxyx()[1])
    win.refresh()

def draw_status_bar(win, message):
    win.clear()
    max_y, max_x = win.getmaxyx()
    status = message if message else "F1: Aide | F5: Actualiser | /: Filtrer | c: Créer | d: Supprimer | ESC: Quitter"
    win.addstr(0, 0, status[:max_x-1])
    win.refresh()

def draw_sidebar(win, current_tab, data, selected_index, filter_str):
    win.clear()
    items = get_items_for_tab(current_tab, data)
    if filter_str:
        items = [item for item in items if filter_str.lower() in str(item).lower()]
    for idx, item in enumerate(items):
        display_text = f"{item}" if current_tab != 0 else f"{item[0]}: {item[1]}"
        if idx == selected_index:
            win.addstr(idx+1, 1, display_text, curses.A_REVERSE)
        else:
            win.addstr(idx+1, 1, display_text)
    win.box()
    win.refresh()

def draw_content(win, current_tab, data, selected_index, filter_str):
    win.clear()
    items = get_items_for_tab(current_tab, data)
    if filter_str:
        items = [item for item in items if filter_str.lower() in str(item).lower()]
    if items:
        selected_item = items[selected_index]
        if current_tab == 0:
            details = f"{selected_item[0]} : {selected_item[1]}"
        else:
            details = f"Nom : {selected_item}"
        win.addstr(1, 2, details)
    else:
        win.addstr(1, 2, "Aucun élément")
    win.box()
    win.refresh()

def prompt_filter(stdscr):
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    win = curses.newwin(3, max_x//2, max_y//2 - 1, max_x//4)
    win.box()
    win.addstr(1, 2, "Filtrer : ")
    win.refresh()
    filter_str = win.getstr(1, 12, 20).decode('utf-8')
    curses.noecho()
    return filter_str

def show_help(stdscr):
    max_y, max_x = stdscr.getmaxyx()
    help_text = [
        "Aide - Raccourcis clavier:",
        "F1 : Afficher cette aide",
        "F5 : Actualiser les données",
        "/  : Filtrer la liste",
        "c  : Créer un nouvel objet",
        "d  : Supprimer l'objet sélectionné",
        "Flèches : Navigation",
        "ESC : Quitter l'application",
        "",
        "Appuyez sur une touche pour revenir."
    ]
    win = curses.newwin(len(help_text)+2, max_x//2, max_y//2 - len(help_text)//2, max_x//4)
    win.box()
    for idx, line in enumerate(help_text):
        win.addstr(idx+1, 2, line)
    win.refresh()
    win.getch()

def modal_input(stdscr, title, prompt):
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = max(len(prompt) + 20, 40)
    win = curses.newwin(5, width, max_y//2 - 2, (max_x - width)//2)
    win.box()
    win.addstr(0, 2, title, curses.A_BOLD)
    win.addstr(2, 2, prompt)
    win.refresh()
    input_val = win.getstr(2, len(prompt) + 3, 20).decode('utf-8')
    curses.noecho()
    return input_val

def modal_input_multiple(stdscr, title, prompts):
    responses = {}
    curses.echo()
    max_y, max_x = stdscr.getmaxyx()
    width = max(max(len(p) for p in prompts) + 20, 50)
    height = len(prompts) + 4
    win = curses.newwin(height, width, max_y//2 - height//2, (max_x - width)//2)
    win.box()
    win.addstr(0, 2, title, curses.A_BOLD)
    for idx, prompt in enumerate(prompts):
        win.addstr(idx+2, 2, prompt)
        win.refresh()
        resp = win.getstr(idx+2, len(prompt) + 3, 20).decode('utf-8')
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

def handle_create_action(stdscr, current_tab, domain_info):
    if current_tab == 1:  # OUs
        name = modal_input(stdscr, "Création d'OU", "Nom de la nouvelle OU: ")
        if name:
            return create_ou(domain_info["samdb"], domain_info["domain_dn"], name)
    elif current_tab == 2:  # Groupes
        name = modal_input(stdscr, "Création de Groupe", "Nom du nouveau groupe: ")
        if name:
            return create_group(domain_info["samdb"], domain_info["domain_dn"], name)
    elif current_tab == 3:  # GPOs
        name = modal_input(stdscr, "Création de GPO", "Nom du nouveau GPO: ")
        if name:
            return create_full_gpo(name)
    elif current_tab == 4:  # Utilisateurs
        resp = modal_input_multiple(stdscr, "Création d'Utilisateur", ["Nom d'utilisateur: ", "Mot de passe: "])
        if resp:
            username = resp.get("Nom d'utilisateur: ")
            password = resp.get("Mot de passe: ")
            if username and password:
                return create_user(domain_info["samdb"], domain_info["domain_dn"], username, password)
    elif current_tab == 5:  # Ordinateurs
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
        if current_tab == 1:  # OUs
            return delete_ou(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 2:  # Groupes
            return delete_group(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 3:  # GPOs
            return delete_gpo(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 4:  # Utilisateurs
            return delete_user(domain_info["samdb"], domain_info["domain_dn"], selected_item)
        elif current_tab == 5:  # Ordinateurs
            return delete_computer(domain_info["samdb"], domain_info["domain_dn"], selected_item)
    return "Opération annulée."

def main_tui(stdscr, domain_info):
    curses.curs_set(0)
    stdscr.nodelay(False)
    stdscr.timeout(100)
    tabs = ["Dashboard", "OUs", "Groupes", "GPOs", "Utilisateurs", "Ordinateurs"]
    current_tab = 0
    selected_index = 0
    filter_str = ""
    notification = ""
    data = refresh_data(domain_info)

    while True:
        stdscr.clear()
        max_y, max_x = stdscr.getmaxyx()

        # Définition des zones
        header_win = stdscr.subwin(3, max_x, 0, 0)
        tab_win = stdscr.subwin(2, max_x, 3, 0)
        content_height = max_y - 6 - 1
        content_win = stdscr.subwin(content_height, max_x, 5, 0)
        status_win = stdscr.subwin(1, max_x, max_y - 1, 0)

        # Délimitation de la zone du contenu (split screen)
        left_width = max_x // 3
        right_width = max_x - left_width
        sidebar_win = content_win.derwin(content_height, left_width, 0, 0)
        content_panel_win = content_win.derwin(content_height, right_width, 0, left_width)

        # Dessin des différentes zones
        draw_header(header_win, domain_info)
        draw_tab_bar(tab_win, current_tab, tabs)
        draw_sidebar(sidebar_win, current_tab, data, selected_index, filter_str)
        draw_content(content_panel_win, current_tab, data, selected_index, filter_str)
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
        elif key == 27:  # ESC
            break

    stdscr.clear()
    stdscr.refresh()

if __name__ == "__main__":
    admin_user = input("[LOGIN] Entrez le nom d'utilisateur Samba AD : ")
    admin_password = getpass.getpass("[LOGIN] Entrez le mot de passe Samba AD : ")
    domain_info = detect_domain_settings(admin_user, admin_password)
    if isinstance(domain_info, str):
        print(domain_info)
    else:
        curses.wrapper(main_tui, domain_info)

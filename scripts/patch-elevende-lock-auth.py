#!/usr/bin/env python3
"""Patch only the Lindows build copy of ElevenDE's lock screen.

The setuid-root helper must authenticate the real session user.  LightDM can
preserve a stale USER environment variable during an autologin/session restart;
TTY authentication then succeeds while the graphical gate checks another
account.  Resolve the account from the real UID instead.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit(f"usage: {sys.argv[0]} /path/to/shell/lock.c")

path = Path(sys.argv[1])
text = path.read_text()
old_include = '#include <crypt.h>\n'
new_include = old_include + '#include <security/pam_appl.h>\n'
if old_include not in text:
    raise SystemExit("lock.c crypt include marker not found")
if '#include <security/pam_appl.h>' not in text:
    text = text.replace(old_include, new_include, 1)

old_check = '''static int check_pw(const char *u, const char *p) {
    struct passwd *pe = getpwnam(u);
    if (!pe) return -1;
    const char *hash = pe->pw_passwd;
    if (!hash || !*hash) return 1;                   /* no password set */
    if (!strcmp(hash, "x") || !strcmp(hash, "*")) {
        /* Debian keeps the authoritative value in shadow.  An empty
           `sp_pwdp` is a valid no-password account and must remain empty;
           the previous conditional left `hash` as literal "x" and rejected
           an otherwise valid empty login. */
        struct spwd *sp = getspnam(u);
        if (!sp || !sp->sp_pwdp) return -1;
        hash = sp->sp_pwdp;
    }
    if (!hash || !*hash) return 1;
    if (hash[0] == '!' || hash[0] == '*') return 0;  /* locked account */
    char *c = crypt(p, hash);
    return (c && !strcmp(c, hash)) ? 1 : 0;
}
'''
new_check = '''static const char *lindows_pam_password;

static int lindows_pam_conversation(int n, const struct pam_message **msg,
                                     struct pam_response **resp, void *data) {
    (void)data;
    if (n <= 0 || n > 32 || !msg || !resp) return PAM_CONV_ERR;
    struct pam_response *answers = calloc((size_t)n, sizeof(*answers));
    if (!answers) return PAM_CONV_ERR;
    for (int i = 0; i < n; i++) {
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF) {
            answers[i].resp = strdup(lindows_pam_password ? lindows_pam_password : "");
            if (!answers[i].resp) {
                for (int j = 0; j <= i; j++) free(answers[j].resp);
                free(answers);
                return PAM_CONV_ERR;
            }
        } else if (msg[i]->msg_style == PAM_PROMPT_ECHO_ON) {
            answers[i].resp = strdup(login_user[0] ? login_user : "user");
            if (!answers[i].resp) {
                for (int j = 0; j <= i; j++) free(answers[j].resp);
                free(answers);
                return PAM_CONV_ERR;
            }
        } else if (msg[i]->msg_style != PAM_TEXT_INFO &&
                   msg[i]->msg_style != PAM_ERROR_MSG) {
            for (int j = 0; j <= i; j++) free(answers[j].resp);
            free(answers);
            return PAM_CONV_ERR;
        }
    }
    *resp = answers;
    return PAM_SUCCESS;
}

static int check_pw(const char *u, const char *p) {
    pam_handle_t *pamh = NULL;
    struct pam_conv conv = { lindows_pam_conversation, NULL };
    lindows_pam_password = p;
    int rc = pam_start("lightdm", u, &conv, &pamh);
    if (rc == PAM_SUCCESS)
        rc = pam_authenticate(pamh, PAM_SILENT);
    if (pamh) pam_end(pamh, rc);
    lindows_pam_password = NULL;
    return rc == PAM_SUCCESS ? 1 : 0;
}
'''
if old_check not in text:
    raise SystemExit("lock.c password check marker not found")
text = text.replace(old_check, new_check, 1)

old_user = '''    user = getenv("USER");
    if (!user || !*user) user = "kali";
'''
new_user = '''    /* LightDM may leave USER set to a previous/autologin account.  The
     * real UID is authoritative for the graphical session, including when
     * this helper is installed setuid-root. */
    struct passwd *session_pw = getpwuid(getuid());
    user = session_pw ? session_pw->pw_name : getenv("USER");
    if (!user || !*user) user = "kali";
'''
if old_user in text:
    text = text.replace(old_user, new_user, 1)
elif 'resolve_user_identity();' not in text:
    raise SystemExit("lock.c user-resolution marker not found")

# The lock screen must follow RandR changes while it is open.  It owns a
# full-screen override-redirect window plus screen-sized wallpaper/frame
# pixmaps, so a simple repaint on the old geometry leaves stale black/grey
# borders after Settings changes resolution.
include_marker = '#include <X11/cursorfont.h>\n'
if include_marker not in text:
    raise SystemExit("lock.c cursorfont include marker not found")
if '#include <X11/extensions/Xrandr.h>' not in text:
    text = text.replace(include_marker, include_marker + '#include <X11/extensions/Xrandr.h>\n', 1)

globals_marker = 'static int      scr_w, scr_h;\n'
if globals_marker not in text:
    raise SystemExit("lock.c geometry globals marker not found")
if 'static int      rr_event_base = -1;' not in text:
    text = text.replace(globals_marker, globals_marker + 'static int      rr_event_base = -1;\n', 1)

main_marker = 'int main(int argc, char **argv) {\n'
resize_helper = '''static void rebuild_screen_geometry(void) {
    int new_w = XWidthOfScreen(ScreenOfDisplay(dpy, scr));
    int new_h = XHeightOfScreen(ScreenOfDisplay(dpy, scr));
    if (new_w < 1 || new_h < 1 || (new_w == scr_w && new_h == scr_h)) return;
    scr_w = new_w;
    scr_h = new_h;
    XResizeWindow(dpy, win, (unsigned)scr_w, (unsigned)scr_h);
    if (wall_pm) { XFreePixmap(dpy, wall_pm); wall_pm = None; }
    if (frame_pm) { XFreePixmap(dpy, frame_pm); frame_pm = None; }
    frame_pm = XCreatePixmap(dpy, win, (unsigned)scr_w, (unsigned)scr_h,
                             DefaultDepth(dpy, scr));
    load_wallpaper();
    caret_visible = 1;
    paint();
    XFlush(dpy);
}

'''
if 'static void rebuild_screen_geometry(void)' not in text:
    if main_marker not in text:
        raise SystemExit("lock.c main marker not found")
    text = text.replace(main_marker, resize_helper + main_marker, 1)

root_select = '    bgc    = XCreateGC(dpy, root, 0, NULL);\n'
root_select_new = '''    bgc    = XCreateGC(dpy, root, 0, NULL);
    XSelectInput(dpy, root, StructureNotifyMask);
    int rr_error_base = 0;
    if (XRRQueryExtension(dpy, &rr_event_base, &rr_error_base))
        XRRSelectInput(dpy, root, RRScreenChangeNotifyMask);
'''
if root_select_new not in text:
    if root_select not in text:
        raise SystemExit("lock.c root event-selection marker not found")
    text = text.replace(root_select, root_select_new, 1)

event_marker = '            XNextEvent(dpy, &ev);\n'
event_new = '''            XNextEvent(dpy, &ev);
            if ((ev.type == ConfigureNotify && ev.xconfigure.window == root) ||
                (rr_event_base >= 0 && ev.type == rr_event_base + RRScreenChangeNotify)) {
                if (rr_event_base >= 0 && ev.type == rr_event_base + RRScreenChangeNotify)
                    XRRUpdateConfiguration(&ev);
                rebuild_screen_geometry();
                continue;
            }
'''
if event_new not in text:
    if event_marker not in text:
        raise SystemExit("lock.c event-loop marker not found")
    text = text.replace(event_marker, event_new, 1)

path.write_text(text)
print(f"patched {path}")

#!/usr/bin/env python3
"""Apply deterministic Lindows-only fixes to disposable locked source copies."""
from pathlib import Path
import sys


def need_replace(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"{label}: expected marker not found in {path}")
    path.write_text(text.replace(old, new, 1))


def patch_store(root: Path) -> None:
    path = root / "native" / "linux_store.py"
    need_replace(
        path,
        "GdkPixbuf.Pixbuf.new_from_file_at_scale(source, width, height, False)",
        "GdkPixbuf.Pixbuf.new_from_file_at_scale(source, width, height, True)",
        "store aspect-ratio patch",
    )
    need_replace(
        path,
        '''        frame = Gtk.EventBox()
        add_class(frame, css_name)
        frame.add(overlay)
''',
        '''        frame = Gtk.EventBox()
        card_height = 330 if is_hero else 172
        # Gtk.Overlay otherwise inherits only a transient text requisition on
        # some X11 themes and collapses the image to a thin strip.  Pin the
        # intended card height while still letting width follow the viewport.
        image.set_size_request(-1, card_height)
        image.set_hexpand(True)
        image.set_vexpand(False)
        overlay.set_size_request(-1, card_height)
        frame.set_size_request(-1, card_height)
        add_class(frame, css_name)
        frame.add(overlay)
''',
        "store card minimum-height patch",
    )


def patch_widgets(root: Path) -> None:
    path = root / "widget_panel" / "main.py"
    need_replace(
        path,
        "        self.settings = load_settings()\n\n        screen = self.app.primaryScreen().geometry()",
        "        self.settings = load_settings()\n        # Lindows starts Widgets with ElevenDE; materialize the per-user\n"
        "        # autostart policy on first run instead of waiting for Settings.\n"
        "        self._handle_autostart(self.settings.get(\"auto_start\", True))\n\n"
        "        screen = self.app.primaryScreen().geometry()",
        "widgets first-run autostart patch",
    )


def patch_task_scheduler(root: Path) -> None:
    path = root / "ltask" / "qt.py"
    text = path.read_text()
    # Task Scheduler uses Qt6-only enums (AlignmentFlag, ItemDataRole,
    # DialogCode and StandardButton). Debian provides PyQt6; preserve the
    # upstream fallback instead of applying a lossy PyQt5 rewrite.
    if "from PyQt6 import QtCore, QtGui, QtWidgets" not in text:
        raise SystemExit("task scheduler requires its upstream PyQt6 fallback")


def patch_control(root: Path) -> None:
    config = root / "src" / "config.rs"
    need_replace(
        config,
        'cmd_template: "gnome-control-center {panel}".to_string(),',
        'cmd_template: "elevende-settings --page {panel}".to_string(),',
        "control default settings route",
    )
    app = root / "src" / "app.rs"
    need_replace(
        app,
        'let config_path = PathBuf::from("config.json");',
        'let config_path = std::env::var_os("XDG_CONFIG_HOME")\n'
        '            .map(PathBuf::from)\n'
        '            .unwrap_or_else(|| PathBuf::from(std::env::var("HOME").unwrap_or_else(|_| ".".to_string())).join(".config"))\n'
        '            .join("lindows-control").join("config.json");\n'
        '        if let Some(parent) = config_path.parent() { let _ = std::fs::create_dir_all(parent); }',
        "control writable config path",
    )
    need_replace(
        app,
        'self.dark_mode = config.dark_mode;',
        'self.dark_mode = false; // Lindows is intentionally light-only.',
        "control force light state",
    )
    need_replace(
        app,
        '''                    let icon1 = if self.show_icons { "🖥️ " } else { "" };
                    let icon2 = if self.show_icons { "🌐 " } else { "" };
                    let icon3 = if self.show_icons { "📦 " } else { "" };
                    let icon4 = if self.show_icons { "👤 " } else { "" };
                    let icon5 = if self.show_icons { "⚙️ " } else { "" };
''',
        '''                    // egui has no bundled color-emoji font in the Debian
                    // build. Keep these controls text-stable; their official
                    // Windows icons are supplied at shell/menu/titlebar level.
                    let icon1 = "";
                    let icon2 = "";
                    let icon3 = "";
                    let icon4 = "";
                    let icon5 = "";
''',
        "control unsupported emoji button icons",
    )
    need_replace(
        app,
        'let label = if self.show_icons { "🔹 " } else { "" };',
        'let label = "";',
        "control unsupported custom-button emoji",
    )
    need_replace(
        app,
        'let settings_label = if self.show_icons { "⚙️ " } else { "" };',
        'let settings_label = "";',
        "control unsupported settings emoji",
    )
    need_replace(
        app,
        '''        let style = if self.dark_mode {
            egui::Style {
                visuals: egui::Visuals::dark(),
                ..Default::default()
            }
        } else {
            egui::Style {
                visuals: egui::Visuals::light(),
                ..Default::default()
            }
        };
''',
        '''        let style = egui::Style {
            visuals: egui::Visuals::light(),
            ..Default::default()
        };
''',
        "control light visuals",
    )
    need_replace(
        app,
        '''                    // 主题
                    ui.horizontal(|ui| {
                        ui.label(format!("{}:", self.tr("settings_theme")));
                        let label = if self.dark_mode {
                            self.tr("settings_theme_dark")
                        } else {
                            self.tr("settings_theme_light")
                        };
                        if ui.button(label).clicked() {
                            self.dark_mode = !self.dark_mode;
                            self.save_config();
                        }
                    });
''',
        '''                    // Lindows is intentionally light-only.
                    ui.horizontal(|ui| {
                        ui.label(format!("{}:", self.tr("settings_theme")));
                        ui.label(self.tr("settings_theme_light"));
                    });
''',
        "control light-only theme control",
    )
    commands = root / "src" / "commands.rs"
    need_replace(
        commands,
        '''pub fn open_linux_settings(panel_type: &str, template: &str) {
    let is_kde = template.contains("systemsettings") || template.contains("kcmshell");

    let panel_arg = if is_kde {
        match panel_type {
            "system" => "kcm_systeminformation",
            "network" => "kcm_networkmanagement",
            "applications" => "",      // 打开主界面
            "users" => "kcm_users",
            _ => "",
        }
    } else {
        match panel_type {
            "" => "",
            "system" => "",
            "network" => "network",
            "applications" => "applications",
            "users" => "users",
            _ => "",
        }
    };

    let cmd = template.replace("{panel}", panel_arg).trim().to_string();
''',
        '''pub fn open_linux_settings(panel_type: &str, template: &str) {
    // ElevenDE owns the actual configurable pages.  Do not invoke GNOME/KDE
    // control centers that are intentionally absent from Lindows.
    let panel_arg = match panel_type {
        "system" => "about",
        "network" => "network",
        "applications" => "defaults",
        "users" => "users",
        _ => "home",
    };
    let route = if template.trim().is_empty() {
        "elevende-settings --page {panel}"
    } else {
        template
    };
    let cmd = route.replace("{panel}", panel_arg).trim().to_string();
''',
        "control ElevenDE routing",
    )


def patch_activation(root: Path) -> None:
    path = root / "src" / "i18n.c"
    text = path.read_text()
    if '"Lindows"' not in text:
        if '"Linux"' not in text:
            raise SystemExit("activation Lindows label patch: marker not found")
        path.write_text(text.replace('"Linux"', '"Lindows"', 1))


if len(sys.argv) != 3:
    raise SystemExit("usage: patch-lindows-component-sources.py COMPONENT SOURCE_DIR")
component, root_text = sys.argv[1:]
root = Path(root_text)
patchers = {
    "store": patch_store,
    "widgets": patch_widgets,
    "task-scheduler": patch_task_scheduler,
    "control": patch_control,
    "activation": patch_activation,
}
try:
    patchers[component](root)
except KeyError:
    raise SystemExit(f"unknown component: {component}")
print(f"patched Lindows build copy for {component}: {root}")

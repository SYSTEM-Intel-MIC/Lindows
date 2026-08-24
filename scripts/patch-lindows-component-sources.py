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
    need_replace(
        path,
        '''class EdgeStrip(QWidget):
    """贴在屏幕右侧边缘的隐形窗口（XWayland 真实表面），
    光标移上去触发 enterEvent，比轮询全局坐标可靠。"""

    def __init__(self, screen_geo, on_enter):
        super().__init__()
        self._on_enter = on_enter
        self._geo = screen_geo
        self.setWindowFlags(
            Qt.FramelessWindowHint
            | Qt.WindowStaysOnTopHint
            | Qt.Tool
            | Qt.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WA_ShowWithoutActivating, True)
        self.setAttribute(Qt.WA_Hover, True)
        self.reposition(screen_geo)
        self.show()

    def reposition(self, geo):
        self._geo = geo
        w = 6
        self.setGeometry(geo.right() - w + 1, geo.y(), w, geo.height())

    def enterEvent(self, e):
        if self._on_enter:
            self._on_enter(self._geo)
        super().enterEvent(e)
''',
        '''class EdgeStrip(QWidget):
    """A persistent, transparent right-edge trigger bound to one QScreen.

    Repositioning an existing X11 window is important: recreating the strip
    during every RandR geometry event emits a new enterEvent under a stationary
    pointer and repeatedly opens Widgets after a resolution change.
    """

    def __init__(self, screen, on_enter):
        super().__init__()
        self._on_enter = on_enter
        self._screen = screen
        self._geo = screen.geometry()
        self.setWindowFlags(
            Qt.FramelessWindowHint
            | Qt.WindowStaysOnTopHint
            | Qt.Tool
            | Qt.WindowDoesNotAcceptFocus
        )
        self.setAttribute(Qt.WA_TranslucentBackground, True)
        self.setAttribute(Qt.WA_ShowWithoutActivating, True)
        self.setAttribute(Qt.WA_Hover, True)
        self._screen.geometryChanged.connect(self.reposition)
        self.reposition(self._geo)
        self.show()

    def reposition(self, geo):
        self._geo = geo
        width = 6
        self.setGeometry(geo.right() - width + 1, geo.y(), width, geo.height())

    def enterEvent(self, e):
        if self._on_enter:
            self._on_enter(self._geo)
        super().enterEvent(e)
''',
        "widgets persistent edge strip patch",
    )
    need_replace(
        path,
        "        self.app.screenAdded.connect(lambda _s: self._build_edge_strips())\n",
        "        self.app.screenAdded.connect(lambda _s: self._build_edge_strips())\n"
        "        self.app.screenRemoved.connect(lambda _s: self._build_edge_strips())\n",
        "widgets screen add/remove patch",
    )
    need_replace(
        path,
        "                strip = EdgeStrip(sc.geometry(), self._on_edge_enter)\n",
        "                strip = EdgeStrip(sc, self._on_edge_enter)\n",
        "widgets edge strip screen binding patch",
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
    "activation": patch_activation,
}
if component not in patchers:
    raise SystemExit(f"unsupported component patch target: {component}")
patchers[component](root)
print(f"patched Lindows build copy for {component}: {root}")

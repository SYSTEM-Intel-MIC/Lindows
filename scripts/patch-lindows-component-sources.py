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
        "from PyQt5.QtCore import Qt, QObject, QEvent, QTimer, pyqtSignal\n",
        "from PyQt5.QtCore import Qt, QObject, QEvent, QTimer, pyqtSignal\n"
        "from PyQt5.QtGui import QCursor\n",
        "widgets cursor import",
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
    """Persistent right-edge trigger bound to one QScreen.

    A RandR geometry change must never manufacture a fresh enterEvent beneath
    a stationary pointer.  The strip is repositioned in place and is armed
    only after the pointer is outside its new geometry, so Widgets open only
    after the user deliberately leaves and re-enters the screen edge.
    """
    def __init__(self, screen, on_enter):
        super().__init__()
        self._on_enter = on_enter
        self._screen = screen
        self._geo = screen.geometry()
        self._armed = False
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
        # If RandR moves this transparent window under a stationary cursor,
        # consume that synthetic enter.  A later real leave/re-enter re-arms it.
        self._armed = not self.geometry().contains(QCursor.pos())

    def enterEvent(self, e):
        if self._armed and self._on_enter:
            self._armed = False
            self._on_enter(self._geo)
        super().enterEvent(e)

    def leaveEvent(self, e):
        self._armed = True
        super().leaveEvent(e)
''',
        "widgets guarded persistent edge strip patch",
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
    need_replace(
        path,
        '''    def _handle_autostart(self, enable):
        import shutil
        from pathlib import Path
        desktop = Path.home() / ".config" / "autostart"
        desktop.mkdir(parents=True, exist_ok=True)
        f = desktop / "widget-panel.desktop"
        if enable:
            if shutil.which("widget-panel"):
                exec_line = "widget-panel"
            else:
                # 从源码运行：用当前解释器 + 模块，PYTHONPATH 指向包父目录
                pkg_parent = str(Path(__file__).resolve().parent.parent)
                exec_line = (
                    f"env PYTHONPATH={pkg_parent} "
                    f"{sys.executable} -m widget_panel.main"
                )
            f.write_text(
                "[Desktop Entry]\\n"
                "Type=Application\\n"
                "Name=WidgetPanel\\n"
                f"Exec={exec_line}\\n"
                "Hidden=false\\n"
                "NoDisplay=false\\n"
                "X-GNOME-Autostart-enabled=true\\n",
                encoding="utf-8",
            )
        else:
            if f.exists():
                f.unlink()
''',
        '''    def _handle_autostart(self, enable):
        """Lindows owns Widgets autostart through one system XDG entry.

        The upstream per-user writer creates a second process after a settings
        save, producing duplicate edge strips and repeated panel openings on
        later sessions.  Keep the setting harmless but never emit a competing
        ~/.config/autostart/widget-panel.desktop file.
        """
        return
''',
        "widgets single-autostart policy patch",
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

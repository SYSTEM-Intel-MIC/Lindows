#!/usr/bin/env python3
"""Patch only the Lindows build copy of ElevenDE display settings.

The upstream page changes RandR immediately but does not persist the selected
output/mode. Lindows stores the choice in ~/.config/lindows/display.conf and
restores it during the next graphical session.
"""
from pathlib import Path
import sys

if len(sys.argv) != 2:
    raise SystemExit("usage: patch-elevende-settings-display.py PATH_TO_MAIN_CPP")

path = Path(sys.argv[1])
text = path.read_text()
old = '''        if (m_resCombo->count() == 0)
            m_resCombo->addItem(QStringLiteral("（未检测到可切换的模式）"));
    }
    void applyMode()
    {
        const QString mode = m_resCombo->currentData().toString();
        if (mode.isEmpty() || m_output.isEmpty())
            return;
        QProcess::startDetached(QStringLiteral("xrandr"),
                                { QStringLiteral("--output"), m_output,
                                  QStringLiteral("--mode"), mode });
    }
'''
new = '''        if (m_resCombo->count() == 0)
            m_resCombo->addItem(QStringLiteral("（未检测到可切换的模式）"));
        const QString saved = QDir::homePath() + QStringLiteral("/.config/lindows/display.conf");
        QFile savedFile(saved);
        if (savedFile.open(QIODevice::ReadOnly)) {
            const QString savedMode = QString::fromUtf8(savedFile.readAll()).trimmed();
            const int idx = m_resCombo->findData(savedMode);
            if (idx >= 0)
                m_resCombo->setCurrentIndex(idx);
        }
    }
    void applyMode()
    {
        const QString mode = m_resCombo->currentData().toString();
        if (mode.isEmpty() || m_output.isEmpty())
            return;
        QDir().mkpath(QDir::homePath() + QStringLiteral("/.config/lindows"));
        QFile saved(QDir::homePath() + QStringLiteral("/.config/lindows/display.conf"));
        if (saved.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
            saved.write(mode.toUtf8());
            saved.write("\\n");
            saved.close();
        }
        const QStringList args = { QStringLiteral("--output"), m_output,
                                   QStringLiteral("--mode"), mode };
        /* Wait for RandR to commit. ElevenDE's native shell observes root
         * geometry changes and also polls live DisplayWidth/DisplayHeight, so
         * no Lindows-only signal handler is needed (or allowed to drift). */
        QProcess::execute(QStringLiteral("xrandr"), args);
    }
'''
if old not in text:
    raise SystemExit("ElevenDE display functions changed; patch not applied")
path.write_text(text.replace(old, new, 1))
print(f"patched {path}")

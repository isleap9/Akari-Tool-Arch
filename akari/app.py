"""Application bootstrap: Qt app, QML engine, bridge wiring."""
import sys
from pathlib import Path

from PySide6.QtGui import QGuiApplication, QIcon
from PySide6.QtQml import QQmlApplicationEngine

from .bridge import Bridge

UI_DIR = Path(__file__).resolve().parent.parent / "ui"


def main() -> int:
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Akari Tool Linux")
    app.setOrganizationName("Akari")
    app.setDesktopFileName("akari-tool")   # matches future .desktop file
    app.setWindowIcon(QIcon(str(UI_DIR / "resources" / "AkariMark.png")))

    bridge = Bridge()

    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("bridge", bridge)
    engine.addImportPath(str(UI_DIR))          # so `import components` works
    engine.load(UI_DIR / "Main.qml")
    if not engine.rootObjects():
        return 1

    bridge.run("check", "")                    # initial status scan
    bridge.runDiagnose()                       # feeds the Overview summary
    return app.exec()

#!/usr/bin/env python3
"""
Akari Tool Linux — Python glue layer.

This is the ENTIRE host: it opens the QML window, runs the bash backend,
parses `check` output into card statuses, and streams apply/plan output
into the log view. If this is ever ported to Rust, only this file is
rewritten — Main.qml and akari-setup.sh stay identical.
"""
import sys
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Property, Signal, Slot
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

ROOT = Path(__file__).resolve().parent
SCRIPT = ROOT / "backend" / "akari-setup.sh"


class Bridge(QObject):
    statusChanged = Signal()
    runningChanged = Signal()
    logChanged = Signal()

    def __init__(self):
        super().__init__()
        self._status: dict = {}     # key -> {"state": ..., "detail": ...}
        self._running = False
        self._log = ""
        self._proc: QProcess | None = None
        self._mode = "check"

    # ---- properties exposed to QML ----
    @Property("QVariantMap", notify=statusChanged)
    def status(self):
        return self._status

    @Property(bool, notify=runningChanged)
    def running(self):
        return self._running

    @Property(str, notify=logChanged)
    def logText(self):
        return self._log

    # ---- slots callable from QML ----
    @Slot(str, str)
    def run(self, command: str, target: str):
        if self._running:
            return
        self._mode = command
        args = [command] + ([target] if target else [])

        self._proc = QProcess(self)
        self._proc.setProgram("bash")
        self._proc.setArguments([str(SCRIPT), *args])
        self._proc.setProcessChannelMode(QProcess.MergedChannels)
        self._proc.readyReadStandardOutput.connect(self._on_output)
        self._proc.finished.connect(self._on_finished)

        self._set_running(True)
        self._proc.start()

    @Slot()
    def clearLog(self):
        self._log = ""
        self.logChanged.emit()

    # ---- internals ----
    def _on_output(self):
        text = bytes(self._proc.readAllStandardOutput()).decode(errors="replace")
        if self._mode == "check":
            for line in text.splitlines():
                parts = line.split("|", 2)
                if len(parts) == 3:
                    key, state, detail = parts
                    self._status[key] = {"state": state, "detail": detail}
            self.statusChanged.emit()
        else:  # plan/apply -> stream to log view
            self._log += text
            self.logChanged.emit()

    def _on_finished(self, *_):
        self._set_running(False)
        if self._mode != "check":       # refresh cards after any apply
            self.run("check", "")

    def _set_running(self, value: bool):
        self._running = value
        self.runningChanged.emit()


def main():
    app = QGuiApplication(sys.argv)
    app.setApplicationName("Akari Tool Linux")

    bridge = Bridge()
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("bridge", bridge)
    engine.load(ROOT / "ui" / "Main.qml")
    if not engine.rootObjects():
        sys.exit(1)

    bridge.run("check", "")             # initial status scan
    sys.exit(app.exec())


if __name__ == "__main__":
    main()

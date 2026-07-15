"""Bridge between QML and the bash backend.

Owns all backend communication: runs akari-setup.sh via QProcess and
routes its output by mode:
  check    -> status map (Overview cards)
  packages -> package list (Gaming page)
  kernels  -> kernel list (Kernel page)
  plan     -> planText (confirmation dialog)
  log      -> changeLog (Change Log page)
  apply    -> logText (live log view)
No UI code lives here.
"""
from pathlib import Path

from PySide6.QtCore import QObject, QProcess, Property, Signal, Slot

PROJECT_ROOT = Path(__file__).resolve().parent.parent
BACKEND_SCRIPT = PROJECT_ROOT / "backend" / "akari-setup.sh"


class Bridge(QObject):
    statusChanged = Signal()
    runningChanged = Signal()
    applyingChanged = Signal()
    logChanged = Signal()
    packagesChanged = Signal()
    kernelsChanged = Signal()
    planChanged = Signal()
    changeLogChanged = Signal()

    def __init__(self, parent: QObject | None = None):
        super().__init__(parent)
        self._status: dict = {}     # key -> {"state": ..., "detail": ...}
        self._packages: list = []   # [{"group","name","installed"}]
        self._kernels: list = []    # [{"name","source","description","installed","running"}]
        self._running = False
        self._applying = False
        self._log = ""
        self._plan = ""
        self._changelog = ""
        self._proc: QProcess | None = None
        self._mode = "check"
        self._queue: list = []

    # ---- properties exposed to QML -------------------------------------
    @Property("QVariantMap", notify=statusChanged)
    def status(self):
        return self._status

    @Property(bool, notify=runningChanged)
    def running(self):
        return self._running

    @Property(bool, notify=applyingChanged)
    def applying(self):
        """True only while an apply runs — drives the log view."""
        return self._applying

    @Property(str, notify=logChanged)
    def logText(self):
        return self._log

    @Property(str, notify=planChanged)
    def planText(self):
        return self._plan

    @Property(str, notify=changeLogChanged)
    def changeLog(self):
        return self._changelog

    @Property("QVariantList", notify=packagesChanged)
    def packages(self):
        return self._packages

    @Property("QVariantList", notify=kernelsChanged)
    def kernels(self):
        return self._kernels

    # ---- slots callable from QML ----------------------------------------
    @Slot(str, str)
    def run(self, command: str, target: str):
        """Run `akari-setup.sh <command> [target]` (queued if busy)."""
        self._enqueue([command] + ([target] if target else []))

    @Slot(str)
    def requestPlan(self, target: str):
        """Fetch plan text for a target ('gaming', 'kernel linux-zen', ...)."""
        self._plan = ""
        self.planChanged.emit()
        self._enqueue(["plan", *target.split()])

    @Slot(str)
    def applyKernel(self, name: str):
        self._enqueue(["apply", "kernel", name])

    @Slot("QVariantList")
    def installSelected(self, names: list):
        if names:
            self._enqueue(["apply", "selected", *[str(n) for n in names]])

    @Slot()
    def refreshPackages(self):
        self._enqueue(["packages"])

    @Slot()
    def refreshKernels(self):
        self._enqueue(["kernels"])

    @Slot()
    def refreshChangeLog(self):
        self._changelog = ""
        self._enqueue(["log"])

    @Slot()
    def clearLog(self):
        self._log = ""
        self.logChanged.emit()

    # ---- internals -------------------------------------------------------
    def _enqueue(self, args: list):
        if self._running:
            self._queue.append(args)
            return
        self._start(args)

    def _start(self, args: list):
        self._mode = args[0]
        self._proc = QProcess(self)
        self._proc.setProgram("bash")
        self._proc.setArguments([str(BACKEND_SCRIPT), *args])
        self._proc.setProcessChannelMode(QProcess.MergedChannels)
        self._proc.readyReadStandardOutput.connect(self._on_output)
        self._proc.finished.connect(self._on_finished)
        if args[0] == "packages":
            self._packages = []
        elif args[0] == "kernels":
            self._kernels = []
        self._set_running(True, applying=(args[0] == "apply"))
        self._proc.start()

    def _on_output(self):
        text = bytes(self._proc.readAllStandardOutput()).decode(errors="replace")
        if self._mode == "check":
            for line in text.splitlines():
                parts = line.split("|", 2)
                if len(parts) == 3:
                    key, state, detail = parts
                    self._status[key] = {"state": state, "detail": detail}
            self.statusChanged.emit()
        elif self._mode == "packages":
            for line in text.splitlines():
                parts = line.split("|")
                if len(parts) == 4 and parts[0] == "PKG":
                    _, group, name, installed = parts
                    self._packages.append(
                        {"group": group, "name": name,
                         "installed": installed == "1"})
            self.packagesChanged.emit()
        elif self._mode == "kernels":
            for line in text.splitlines():
                parts = line.split("|")
                if len(parts) == 6 and parts[0] == "KRN":
                    _, name, source, desc, installed, running = parts
                    self._kernels.append(
                        {"name": name, "source": source, "description": desc,
                         "installed": installed == "1",
                         "running": running == "1"})
            self.kernelsChanged.emit()
        elif self._mode == "plan":
            self._plan += text
            self.planChanged.emit()
        elif self._mode == "log":
            self._changelog += text
            self.changeLogChanged.emit()
        else:  # apply -> stream to live log view
            self._log += text
            self.logChanged.emit()

    def _on_finished(self, *_):
        was_apply = self._mode == "apply"
        self._set_running(False, applying=False)
        if was_apply:
            # refresh every view after an apply
            self._queue.insert(0, ["log"])
            self._queue.insert(0, ["kernels"])
            self._queue.insert(0, ["packages"])
            self._queue.insert(0, ["check"])
        if self._queue:
            self._start(self._queue.pop(0))

    def _set_running(self, value: bool, applying: bool):
        self._running = value
        self.runningChanged.emit()
        if applying != self._applying:
            self._applying = applying
            self.applyingChanged.emit()

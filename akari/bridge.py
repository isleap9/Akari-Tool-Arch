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
import getpass
import os
import shutil
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
    appsChanged = Signal()
    kernelsChanged = Signal()
    diagnosticsChanged = Signal()
    restoreItemsChanged = Signal()
    planChanged = Signal()
    changeLogChanged = Signal()

    def __init__(self, parent: QObject | None = None):
        super().__init__(parent)
        self._status: dict = {}     # key -> {"state": ..., "detail": ...}
        self._packages: list = []   # [{"group","name","installed"}]
        self._apps: list = []       # [{"source","name","version","size","protected","description"}]
        self._kernels: list = []    # [{"name","source","description","installed","running"}]
        self._diagnostics: list = []  # [{"key","state","title","detail","fix"}]
        self._restore: list = []      # [{"id","backup","original","when"}]
        self._running = False
        self._applying = False
        self._log = ""
        self._plan = ""
        self._changelog = ""
        self._proc: QProcess | None = None
        self._mode = "check"
        self._queue: list = []
        self._linebuf = ""

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

    @Property("QVariantList", notify=appsChanged)
    def apps(self):
        return self._apps

    @Property("QVariantList", notify=kernelsChanged)
    def kernels(self):
        return self._kernels

    @Property("QVariantList", notify=diagnosticsChanged)
    def diagnostics(self):
        return self._diagnostics

    @Property("QVariantList", notify=restoreItemsChanged)
    def restoreItems(self):
        return self._restore

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

    # ---- interactive terminal for AUR operations ------------------------
    # AUR builds prompt for a password mid-way; that needs a real terminal,
    # not the GUI's pkexec session. Opens the user's terminal emulator and
    # runs the backend there (per-command sudo, fully interactive).
    TERMINALS = [
        ("foot", ["-e"]), ("kitty", ["-e"]), ("alacritty", ["-e"]),
        ("wezterm", ["start", "--"]), ("ghostty", ["-e"]),
        ("konsole", ["-e"]), ("gnome-terminal", ["--"]), ("xterm", ["-e"]),
    ]

    @Slot("QVariantList", result=bool)
    def runInTerminal(self, args: list) -> bool:
        term_env = os.environ.get("TERMINAL")
        candidates = ([(term_env, ["-e"])] if term_env else []) + self.TERMINALS
        script = " ".join(
            f"'{a}'" for a in ["bash", str(BACKEND_SCRIPT), *[str(a) for a in args]])
        wrapped = (f"{script}; ec=$?; echo; "
                   f"read -rp \"Finished (exit $ec) — press Enter to close\"")
        for name, flag in candidates:
            if name and shutil.which(name):
                ok = QProcess.startDetached(
                    name, [*flag, "bash", "-c", wrapped])
                if ok:
                    return True
        return False

    @Slot(str)
    def removeKernel(self, name: str):
        self._enqueue(["apply", "remove-kernel", name])

    @Slot("QVariantList")
    def installSelected(self, names: list):
        if names:
            self._enqueue(["apply", "selected", *[str(n) for n in names]])

    @Slot("QVariantList")
    def removeSelected(self, names: list):
        if names:
            self._enqueue(["apply", "remove", *[str(n) for n in names]])

    @Slot()
    def refreshPackages(self):
        self._enqueue(["packages"])

    @Slot()
    def refreshApps(self):
        self._enqueue(["apps"])

    @Slot()
    def refreshKernels(self):
        self._enqueue(["kernels"])

    @Slot()
    def runDiagnose(self):
        self._enqueue(["diagnose"])

    @Slot()
    def refreshRestore(self):
        self._enqueue(["restore-list"])

    @Slot(str)
    def applyRestore(self, backup_id: str):
        self._enqueue(["apply", "restore", backup_id])

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
        if args[0] == "apply" and shutil.which("pkexec"):
            # One polkit prompt for the whole apply; the script runs as
            # root with the real user's identity passed through.
            self._proc.setProgram("pkexec")
            self._proc.setArguments([
                "env",
                f"AKARI_USER={getpass.getuser()}",
                f"AKARI_HOME={Path.home()}",
                "bash", str(BACKEND_SCRIPT), *args,
            ])
        else:
            self._proc.setProgram("bash")
            self._proc.setArguments([str(BACKEND_SCRIPT), *args])
        self._proc.setProcessChannelMode(QProcess.MergedChannels)
        self._proc.readyReadStandardOutput.connect(self._on_output)
        self._proc.finished.connect(self._on_finished)
        self._linebuf = ""
        if args[0] == "packages":
            self._packages = []
        elif args[0] == "apps":
            self._apps = []
        elif args[0] == "kernels":
            self._kernels = []
        elif args[0] == "diagnose":
            self._diagnostics = []
        elif args[0] == "restore-list":
            self._restore = []
        self._set_running(True, applying=(args[0] == "apply"))
        self._proc.start()

    def _on_output(self):
        raw = self._linebuf + bytes(
            self._proc.readAllStandardOutput()).decode(errors="replace")
        # keep any incomplete trailing line for the next chunk
        lines = raw.split("\n")
        self._linebuf = lines.pop()
        text = "\n".join(lines) + ("\n" if lines else "")
        self._parse_text(text)

    def _parse_text(self, text: str):
        if not text:
            return
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
        elif self._mode == "apps":
            for line in text.splitlines():
                parts = line.split("|")
                if len(parts) == 7 and parts[0] == "APP":
                    _, source, name, ver, size, protected, desc = parts
                    self._apps.append(
                        {"source": source, "name": name, "version": ver,
                         "size": size, "protected": protected == "1",
                         "description": desc})
            self.appsChanged.emit()
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
        elif self._mode == "diagnose":
            for line in text.splitlines():
                parts = line.split("|")
                if len(parts) == 6 and parts[0] == "DIA":
                    _, key, state, title, detail, fix = parts
                    self._diagnostics.append(
                        {"key": key, "state": state, "title": title,
                         "detail": detail, "fix": fix})
            self.diagnosticsChanged.emit()
        elif self._mode == "restore-list":
            for line in text.splitlines():
                parts = line.split("|")
                if len(parts) == 5 and parts[0] == "RST":
                    _, bid, backup, original, when = parts
                    self._restore.append(
                        {"id": bid, "backup": backup,
                         "original": original, "when": when})
            self.restoreItemsChanged.emit()
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
        # pkexec exit codes: 126 = dismissed, 127 = no agent/authorization
        if (self._mode == "apply" and self._proc
                and self._proc.program() == "pkexec"
                and self._proc.exitCode() in (126, 127)):
            self._log += ("\n:: Authentication did not complete (pkexec exit "
                          f"{self._proc.exitCode()}).\n"
                          ":: If no password dialog appeared, no polkit agent is "
                          "running.\n:: On Hyprland: install hyprpolkitagent and add\n"
                          "::   exec-once = systemctl --user start hyprpolkitagent\n")
            self.logChanged.emit()
        if self._linebuf:
            self._linebuf += "\n"
            tail, self._linebuf = self._linebuf, ""
            # reuse the parser by injecting the tail as a final chunk
            self._parse_text(tail)
        was_apply = self._mode == "apply"
        self._set_running(False, applying=False)
        if was_apply:
            # refresh every view after an apply
            self._queue.insert(0, ["restore-list"])
            self._queue.insert(0, ["log"])
            self._queue.insert(0, ["kernels"])
            self._queue.insert(0, ["apps"])
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

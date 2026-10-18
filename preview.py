"""QML-only visual preview. No access to user media or file operations."""
import os
import sys
from pathlib import Path
from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication, QFont
from PySide6.QtQml import QQmlApplicationEngine

os.environ.setdefault("QT_QUICK_CONTROLS_STYLE", "Basic")
app = QGuiApplication(sys.argv)
app.setApplicationName("ImageClassifier Preview")
app.setFont(QFont("Microsoft YaHei UI", 10))
engine = QQmlApplicationEngine()
engine.warnings.connect(lambda warnings: print("\n".join(w.toString() for w in warnings), flush=True))
engine.load(QUrl.fromLocalFile(str(Path(__file__).parent / "ui" / "Main.qml")))
if not engine.rootObjects():
    sys.exit(1)
sys.exit(app.exec())

"""Offscreen QML gesture regression tests; no desktop mouse input or user files."""
import os
os.environ["QT_QPA_PLATFORM"] = "offscreen"
from pathlib import Path
from PySide6.QtCore import QPoint, QPointF, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QWheelEvent
from PySide6.QtQuick import QQuickView
from PySide6.QtTest import QTest

app = QGuiApplication([])
view = QQuickView()
view.setSource(QUrl.fromLocalFile(str(Path(__file__).with_name("selection_harness.qml").resolve())))
assert view.status() == QQuickView.Ready, view.errors()
view.show()
QTest.qWait(100)
root = view.rootObject()

def chosen():
    value = root.property("selectedIds")
    return set(value.toVariant() if hasattr(value, "toVariant") else value)

def reset(ids=()):
    root.setProperty("selectedIds", list(ids))
    root.setProperty("scrollY", 0)
    QTest.qWait(30)

def press(x, y):
    QTest.mousePress(view, Qt.LeftButton, Qt.NoModifier, QPoint(x, y))

def move(x, y):
    QTest.mouseMove(view, QPoint(x, y), 25)

def release(x, y):
    QTest.mouseRelease(view, Qt.LeftButton, Qt.NoModifier, QPoint(x, y))
    QTest.qWait(25)

QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(50, 50))
assert chosen() == {"1"}, chosen()
QTest.mouseClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(50, 50))
assert chosen() == set(), chosen()
print("PASS single-click toggle")

reset(["10"])
press(50, 50)
move(350, 250)
assert root.property("dragging")
assert chosen() == {"1", "2", "3", "4", "5", "10"}, chosen()
move(100, 100)
assert chosen() == {"1", "10"}, chosen()
release(100, 100)
assert chosen() == {"1", "10"} and not root.property("dragging")
move(550, 250)
assert chosen() == {"1", "10"}
print("PASS live ordered range, shrink, additive selection, release stops selection")

reset()
press(350, 250)
move(50, 50)
release(50, 50)
assert chosen() == {"1", "2", "3", "4", "5"}, chosen()
print("PASS reverse-direction range")

# The user's five-column example: 02 through 14 includes both partial rows
# and EVERY photo in the middle row, regardless of the rectangle's columns.
root.setProperty("columns", 5)
reset()
press(180, 50)
move(420, 350)
assert chosen() == {str(i) for i in range(2, 15)}, chosen()
release(420, 350)
assert chosen() == {str(i) for i in range(2, 15)}, chosen()
reset(["64"])
press(420, 350)
move(180, 50)
assert chosen() == {str(i) for i in range(2, 15)} | {"64"}, chosen()
move(540, 200)
assert chosen() == {str(i) for i in range(10, 15)} | {"64"}, chosen()
release(540, 200)
print("PASS 02-to-14 cross-row range, reverse drag and shrink with prior selection")

reset()
press(300, 200)  # 08
move(540, 200)  # 10
assert chosen() == {"8", "9", "10"}, chosen()
move(60, 200)   # 06, crossing the anchor
assert chosen() == {"6", "7", "8"}, chosen()
release(60, 200)
print("PASS crossing the anchor switches range direction")

root.setProperty("columns", 3)
reset()
press(195, 50)  # Start in the gap: retain geometric rectangle selection.
move(350, 250)
release(350, 250)
assert chosen() == {"2", "5"}, chosen()
print("PASS blank-space drag retains rectangle selection")

root.setProperty("records", [{"id": s} for s in ["2", "8", "13", "30"]])
reset(["64"])
press(50, 50)
move(550, 250)  # Empty space after the last item clamps to that item.
release(550, 250)
assert chosen() == {"2", "8", "13", "30", "64"}, chosen()
print("PASS range follows filtered display order and clamps incomplete final row")
root.setProperty("records", [{"id": str(i)} for i in range(1, 65)])

reset(["12"])
press(50, 50)
move(350, 250)
QTest.keyClick(view, Qt.Key_Escape)
release(350, 250)
assert chosen() == {"12"}, chosen()
print("PASS Escape restores prior selection")

reset()
press(50, 50)
move(350, 390)
QTest.qWait(400)
assert root.property("scrollY") > 0
assert "10" in chosen(), chosen()
release(350, 390)
last_y = root.property("scrollY")
QTest.qWait(100)
assert root.property("scrollY") == last_y
print("PASS edge scrolling across virtualized rows and stopping on release")

reset()
wheel = QWheelEvent(QPointF(250,200),QPointF(250,200),QPoint(),QPoint(0,-120),
                    Qt.NoButton,Qt.NoModifier,Qt.NoScrollPhase,False)
app.sendEvent(view,wheel)
QTest.qWait(200)
assert root.property("scrollY") > 0
assert chosen() == set()
print("PASS mouse wheel still scrolls without selecting")

reset()
QTest.mouseDClick(view, Qt.LeftButton, Qt.NoModifier, QPoint(50, 50))
assert root.property("openedId") == "1", root.property("openedId")
print("PASS double-click opens image")
view.close()

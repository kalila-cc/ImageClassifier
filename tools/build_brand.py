"""Generate header SVG and Windows ICO from the approved application SVG.

Run with .venv/Scripts/python.exe tools/build_brand.py (PySide6 Essentials).
"""
import os
import struct
import xml.etree.ElementTree as ET
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QBuffer, QIODevice, QSize
from PySide6.QtGui import QGuiApplication, QImageReader

BRAND = Path(__file__).resolve().parents[1] / "ui" / "brand"
SVG = "http://www.w3.org/2000/svg"
ET.register_namespace("", SVG)


def main():
    app = QGuiApplication([])
    source = BRAND / "guitu.svg"
    root = ET.parse(source).getroot()
    background = root.find(f"{{{SVG}}}rect")
    if background is None or background.get("width") != "256":
        raise ValueError("Expected the application icon's background rectangle")
    root.remove(background)
    root.set("width", "192")
    root.set("height", "192")
    root.set("viewBox", "32 32 192 192")
    ET.indent(root, space="  ")
    ET.ElementTree(root).write(BRAND / "guitu-header.svg", encoding="utf-8", xml_declaration=False)

    sizes = (16, 20, 24, 32, 40, 48, 64, 128, 256)
    entries, payloads = [], []
    offset = 6 + 16 * len(sizes)
    for size in sizes:
        reader = QImageReader(str(source))
        reader.setScaledSize(QSize(size, size))
        image = reader.read()
        if image.isNull():
            raise RuntimeError(reader.errorString())
        buffer = QBuffer()
        buffer.open(QIODevice.WriteOnly)
        if not image.save(buffer, "PNG"):
            raise RuntimeError("Could not encode icon image")
        png = bytes(buffer.data())
        entries.append(struct.pack("<BBBBHHII", size % 256, size % 256, 0, 0, 1, 32, len(png), offset))
        payloads.append(png)
        offset += len(png)
    (BRAND / "guitu.ico").write_bytes(struct.pack("<HHH", 0, 1, len(sizes)) + b"".join(entries + payloads))
    print("Generated transparent header SVG and Windows ICO:", ", ".join(map(str, sizes)))


if __name__ == "__main__":
    main()

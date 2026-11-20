"""Find an on-screen element in a uiautomator dump and tap its centre with adb.

Usage: python3 -I tap_by_text.py "Continue"
Needs adb on PATH and one emulator or device attached. Prints the bounds it used.
"""
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

DUMP = "/sdcard/window.xml"


def adb(*args: str) -> str:
    return subprocess.run(["adb", *args], check=True, capture_output=True, text=True).stdout


def main(label: str) -> int:
    adb("shell", "uiautomator", "dump", DUMP)
    xml_text = adb("shell", "cat", DUMP)
    root = ET.fromstring(xml_text)
    for node in root.iter("node"):
        if node.get("text") != label and node.get("content-desc") != label:
            continue
        m = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", node.get("bounds", ""))
        if not m:
            continue
        x1, y1, x2, y2 = map(int, m.groups())
        if x2 <= x1 or y2 <= y1:  # zero size: not on screen, do not tap
            continue
        cx, cy = (x1 + x2) // 2, (y1 + y2) // 2
        print(f"tapping '{label}' at {cx},{cy} bounds {node.get('bounds')}")
        adb("shell", "input", "tap", str(cx), str(cy))
        return 0
    print(f"not on screen: '{label}'", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))

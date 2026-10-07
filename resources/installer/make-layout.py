#!/usr/bin/env python3
"""Regenerate the portable Finder layout; optional ds_store==1.3.1 only.

No usernames, volume aliases, machine paths or Finder history are stored.
Packaging consumes the generated resource, not this Python dependency.
"""
from pathlib import Path
from ds_store import DSStore

target = Path(__file__).with_name("finder-layout.bin")
with DSStore.open(str(target), "w+") as layout:
    layout["."]["bwsp"] = {
        "ShowStatusBar": False, "ShowToolbar": False,
        "ShowPathbar": False, "ShowSidebar": False,
        "WindowBounds": "{{220, 180}, {640, 420}}",
        "ContainerShowSidebar": False,
    }
    layout["."]["icvp"] = {
        "viewOptionsVersion": 1, "backgroundType": 1,
        "backgroundColorRed": 0.969, "backgroundColorGreen": 0.976,
        "backgroundColorBlue": 0.988, "gridOffsetX": 0.0,
        "gridOffsetY": 0.0, "gridSpacing": 100.0,
        "arrangeBy": "none", "showIconPreview": True,
        "showItemInfo": False, "labelOnBottom": True,
        "textSize": 14.0, "iconSize": 96.0,
        "scrollPositionX": 0.0, "scrollPositionY": 0.0,
    }
    layout["."]["vSrn"] = ("long", 1)
    layout["."]["vstl"] = ("type", b"icnv")
    layout["g-calendar.app"]["Iloc"] = (170, 150)
    layout["Applications"]["Iloc"] = (470, 150)
    layout["Как установить.html"]["Iloc"] = (320, 300)

print("Portable Finder layout generated")

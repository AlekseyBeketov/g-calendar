#!/usr/bin/env python3
"""Write/verify Finder metadata on the actual image; never store author paths."""
import argparse
from pathlib import Path
from ds_store import DSStore
from mac_alias import Alias

parser = argparse.ArgumentParser()
parser.add_argument("--image-root", type=Path, required=True)
parser.add_argument("--verify", action="store_true")
parser.add_argument("--alias-output", type=Path)
args = parser.parse_args()
root = args.image_root.resolve(strict=True)
background = root / ".installer" / "background.tiff"
if not background.is_file() or background.is_symlink():
    parser.error("Missing embedded installer background")
target = root / ".DS_Store"
if not args.verify:
    alias = Alias.for_file(str(background))
    # Finder resolves the actual volume/file IDs. Keep only its public /Volumes
    # fallback, never the temporary mountpoint beneath a maintainer's checkout.
    name = alias.volume.name
    if isinstance(name, str):
        name = name.encode("utf-8")
    alias.volume.posix_path = b"/Volumes/" + name
    with DSStore.open(str(target), "w+") as layout:
        layout["."]["bwsp"] = {
            "ShowStatusBar": False, "ShowToolbar": False, "ShowPathbar": False,
            "ShowSidebar": False, "ContainerShowSidebar": False,
            "WindowBounds": "{{220, 180}, {640, 420}}",
        }
        layout["."]["icvp"] = {
            "viewOptionsVersion": 1, "backgroundType": 2,
            "backgroundImageAlias": alias.to_bytes(),
            "gridOffsetX": 0.0, "gridOffsetY": 0.0, "gridSpacing": 100.0,
            "arrangeBy": "none", "showIconPreview": True, "showItemInfo": False,
            "labelOnBottom": True, "textSize": 14.0, "iconSize": 96.0,
            "scrollPositionX": 0.0, "scrollPositionY": 0.0,
        }
        layout["."]["vSrn"] = ("long", 1)
        layout["."]["vstl"] = ("type", b"icnv")
        layout["g-calendar.app"]["Iloc"] = (170, 150)
        layout["Applications"]["Iloc"] = (470, 150)
        layout["Как установить.html"]["Iloc"] = (320, 300)

with DSStore.open(str(target), "r") as layout:
    settings = layout["."]["icvp"]
    if settings["backgroundType"] != 2:
        raise ValueError("Finder layout is missing its background image")
    raw = settings["backgroundImageAlias"]
    alias = Alias.from_bytes(raw)
    if alias.target.posix_path != "/.installer/background.tiff":
        raise ValueError("Background alias does not target the embedded image")
    if not alias.volume.posix_path.startswith("/Volumes/g-calendar "):
        raise ValueError("Background alias contains an unexpected volume fallback")
    raw_layout = target.read_bytes()
    if b"/Users/" in raw_layout or b"/private/" in raw_layout:
        raise ValueError("Finder layout contains a maintainer path")
    expected = {"g-calendar.app": (170, 150), "Applications": (470, 150),
                "Как установить.html": (320, 300)}
    for name, position in expected.items():
        if tuple(layout[name]["Iloc"]) != position:
            raise ValueError(f"Unexpected Finder position for {name}")
    if args.alias_output:
        args.alias_output.write_bytes(raw)
print("PASS approved Finder layout and portable embedded-background reference")

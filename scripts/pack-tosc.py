#!/usr/bin/env python3
"""Pack TouchOSC layouts: new betas (incrementing) or stable release from latest beta."""

from __future__ import annotations

import argparse
import copy
import re
import uuid
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "VAS control Design.tosc"
LUA = ROOT / "lua" / "vas-control.lua"
STABLE = ROOT / "VAS CONTROL 1.0.tosc"

BETA_RE = re.compile(r"^VAS CONTROL beta 0\.(\d+)\.tosc$")

SCRIPT_RE = re.compile(
    r"<property type=['\"]s['\"]>\s*<key><!\[CDATA\[script\]\]></key>"
    r"\s*<value><!\[CDATA\[.*?\]\]></value>\s*</property>",
    re.S,
)


def inject_script(xml: str, lua: str) -> str:
    xml = SCRIPT_RE.sub("", xml, count=1)
    prop = (
        "<property type='s'><key><![CDATA[script]]></key>"
        f"<value><![CDATA[{lua}]]></value></property>"
    )
    idx = xml.find("</properties>")
    if idx < 0:
        raise SystemExit("root </properties> not found")
    return xml[:idx] + prop + xml[idx:]


def disable_control_send_messages(xml: str) -> str:
    return xml.replace("<enabled>1</enabled>", "<enabled>0</enabled>")


def fix_zone4_label(xml: str) -> str:
    old = "<default><![CDATA[\n\nZone 3\nRight\n\n\n]]></default>"
    new = "<default><![CDATA[\n\nZone 4\nAudience\n\n\n]]></default>"
    first = xml.find(old)
    if first < 0:
        return xml
    last = xml.rfind(old)
    if last == first:
        return xml
    return xml[:last] + new + xml[last + len(old) :]


def _prop_text(node: ET.Element, key: str) -> str | None:
    for prop in node.findall("./properties/property"):
        k = "".join(prop.find("key").itertext())
        if k != key:
            continue
        val = prop.find("value")
        if val is None:
            return None
        return "".join(val.itertext())
    return None


def _set_prop_text(node: ET.Element, key: str, text: str) -> None:
    for prop in node.findall("./properties/property"):
        k = "".join(prop.find("key").itertext())
        if k != key:
            continue
        val = prop.find("value")
        if val is not None:
            val.text = text
        return


def _set_frame_x(node: ET.Element, x: str) -> None:
    for prop in node.findall("./properties/property"):
        k = "".join(prop.find("key").itertext())
        if k != "frame" or prop.get("type") != "r":
            continue
        for child in prop.find("value"):
            if child.tag == "x":
                child.text = x
        return


def ensure_input_buttons(xml: str) -> str:
    root = ET.fromstring(xml)
    doc = root.find("node")
    children = doc.find("children")
    if children is None:
        return xml

    names: set[str] = set()
    dec_node: ET.Element | None = None
    for node in children.findall("node"):
        name = _prop_text(node, "name")
        if name:
            names.add(name)
        if name in ("button2", "inputDec") and node.get("type") == "BUTTON":
            dec_node = node

    if dec_node is not None and "inputDec" not in names:
        _set_prop_text(dec_node, "name", "inputDec")

    if "inputInc" not in names and dec_node is not None:
        inc = copy.deepcopy(dec_node)
        inc.set("ID", str(uuid.uuid4()))
        _set_prop_text(inc, "name", "inputInc")
        _set_frame_x(inc, "250")
        children.append(inc)

    return ET.tostring(root, encoding="unicode")


def ensure_osc_bridge(xml: str) -> str:
    if "oscIn" in xml:
        return xml

    bridge_id = str(uuid.uuid4())
    bridge = f"""<node ID="{bridge_id}" type="BOX"><properties>
      <property type="b"><key>background</key><value>0</value></property>
      <property type="c"><key>color</key><value><r>0</r><g>0</g><b>0</b><a>0</a></value></property>
      <property type="r"><key>frame</key><value><x>0</x><y>0</y><w>1</w><h>1</h></value></property>
      <property type="b"><key>grabFocus</key><value>0</value></property>
      <property type="b"><key>interactive</key><value>0</value></property>
      <property type="b"><key>locked</key><value>1</value></property>
      <property type="s"><key>name</key><value>oscIn</value></property>
      <property type="b"><key>visible</key><value>0</value></property>
      <property type="i"><key>shape</key><value>1</value></property>
    </properties><values><value><key>touch</key><locked>0</locked><lockedDefaultCurrent>0</lockedDefaultCurrent><default>false</default><defaultPull>0</defaultPull></value></values><messages><osc>
      <enabled>1</enabled><send>0</send><receive>1</receive><feedback>0</feedback><noDuplicates>0</noDuplicates>
      <connections>1111111111</connections><triggers></triggers>
      <path><partial><type>CONSTANT</type><conversion>STRING</conversion><value>/dbaudio1</value><scaleMin>0</scaleMin><scaleMax>1</scaleMax></partial></path>
      <arguments></arguments>
    </osc></messages><script><![CDATA[
function onReceiveOSC(message, connections)
  if root then
    root:notify("osc", message)
    return true
  end
  return false
end
]]></script></node>"""

    marker = "</children>"
    idx = xml.find(marker)
    if idx < 0:
        raise SystemExit("children block not found")
    return xml[:idx] + bridge + xml[idx:]


def list_betas() -> list[tuple[int, Path]]:
    found: list[tuple[int, Path]] = []
    for path in ROOT.glob("VAS CONTROL beta *.tosc"):
        match = BETA_RE.match(path.name)
        if match:
            found.append((int(match.group(1)), path))
    return sorted(found, key=lambda item: item[0])


def latest_beta() -> Path | None:
    betas = list_betas()
    return betas[-1][1] if betas else None


def next_beta_path() -> Path:
    betas = list_betas()
    minor = (betas[-1][0] + 1) if betas else 1
    return ROOT / f"VAS CONTROL beta 0.{minor:02d}.tosc"


def load_source() -> Path:
    latest = latest_beta()
    if latest is not None:
        return latest
    if DESIGN.exists():
        return DESIGN
    raise SystemExit("No .tosc source found")


def pack_xml(source: Path, lua: str) -> bytes:
    xml = zlib.decompress(source.read_bytes()).decode("utf-8")
    xml = ensure_input_buttons(xml)
    xml = inject_script(xml, lua)
    xml = disable_control_send_messages(xml)
    xml = ensure_osc_bridge(xml)
    xml = fix_zone4_label(xml)
    return zlib.compress(xml.encode("utf-8"))


def main() -> None:
    parser = argparse.ArgumentParser(description="Pack TouchOSC VAS CONTROL layouts")
    parser.add_argument(
        "--stable",
        action="store_true",
        help=f"Build stable release ({STABLE.name}) from latest beta",
    )
    args = parser.parse_args()

    lua = LUA.read_text(encoding="utf-8")
    if "]]>" in lua:
        raise SystemExit("lua contains ]]> which would break CDATA")

    source = load_source()
    packed = pack_xml(source, lua)

    if args.stable:
        STABLE.write_bytes(packed)
        DESIGN.write_bytes(packed)
        print(f"source {source.name}")
        print(f"stable {STABLE} ({STABLE.stat().st_size} bytes, lua {len(lua)} chars)")
        print(f"working copy {DESIGN}")
        return

    release = next_beta_path()
    if release.exists():
        raise SystemExit(f"refusing to overwrite existing release: {release.name}")

    release.write_bytes(packed)
    DESIGN.write_bytes(packed)
    print(f"source {source.name}")
    print(f"release {release} ({release.stat().st_size} bytes, lua {len(lua)} chars)")
    print(f"working copy {DESIGN}")


if __name__ == "__main__":
    main()

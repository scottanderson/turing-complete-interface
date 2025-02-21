from __future__ import annotations

import os
import sys
from collections import defaultdict
from dataclasses import dataclass, field
from math import isfinite
from pathlib import Path
from typing import Callable, TypedDict, Literal

try:
    import nimporter
except ImportError:
    print("Couldn't import nimporter. Assuming that save_monger is available anyway.")
from turing_complete_interface import save_monger

Pos = tuple[int, int]


def pre_parse(text: str) -> list[list[list[list[str]]]]:
    return [[
        [
            part.split(",") if "," in part else part
            for part in element.split("`")
        ] for element in section.split(";")
    ] for section in text.split("|")]


class NimPoint(TypedDict):
    x: int
    y: int


@dataclass
class GateReference:
    name: str
    pos: tuple[int, int]
    rotation: int
    id: int
    custom_data: str = ""
    custom_id: int = 0
    program_name: str = ""

    def translate(self, dp: tuple[int, int]):
        dp = self.rot(dp)
        return self.pos[0] + dp[0], self.pos[1] + dp[1]

    def rot(self, dp: tuple[int, int]):
        (a, b), (c, d) = [
            ((1, 0), (0, 1)),
            ((0, -1), (1, 0)),
            ((-1, 0), (0, -1)),
            ((0, 1), (-1, 0)),
        ][self.rotation]
        return a * dp[0] + b * dp[1], c * dp[0] + d * dp[1]

    @classmethod
    def from_nim(cls,
                 kind: str,
                 position: NimPoint,
                 rotation: int,
                 permanent_id: int,
                 custom_string: str,
                 custom_id: int,
                 program_name: str,
                 ) -> GateReference | None:
        if save_monger.is_virtual(kind):
            return None
        return GateReference(
            kind, (position["x"], position["y"]), rotation, permanent_id, custom_string, custom_id, program_name,
        )

    def to_nim(self):
        return {
            "kind": self.name,
            "position": {"x": self.pos[0], "y": self.pos[1]},
            "rotation": self.rotation,
            "permanent_id": int(self.id),
            "custom_string": self.custom_data,
            "custom_id": self.custom_id or 0,
            "program_name": self.program_name or ""
        }


@dataclass
class CircuitWire:
    id: int
    kind: str
    color: int
    label: str
    positions: list[tuple[int, int]]

    @property
    def is_byte(self):
        if self.kind == "ck_qword":
            raise NotImplementedError("This part of code is not 64bit aware")
        return self.kind == "ck_bytes"

    @classmethod
    def from_nim(cls,
                 permanent_id: int,
                 path: list[NimPoint],
                 kind: str,
                 color: int,
                 comment: str) -> CircuitWire:
        assert kind in ("ck_bit", "ck_byte", "ck_qword"), kind
        return CircuitWire(
            permanent_id, kind, color, comment, [(p["x"], p["y"]) for p in path]
        )

    def to_nim(self):
        return {
            "permanent_id": self.id,
            "path": [{"x": p[0], "y": p[1]} for p in self.positions],
            "kind": self.kind,
            "color": self.color,
            "comment": self.label
        }

    @property
    def screen_color(self):

        BIT_COLORS = {
            0: (227, 158, 69),
            1: (219, 227, 69),
            2: (150, 227, 69),
            3: (69, 227, 150),
            4: (68, 220, 228),
            5: (68, 68, 228),
            6: (152, 68, 228),
            7: (227, 69, 201),
            8: (227, 110, 79),
            9: (255, 255, 255),
            10: (122, 122, 122),
            11: (54, 54, 54),
        }
        if self.color == 0:
            if self.kind == "ck_bit":
                return BIT_COLORS[self.color]
            elif self.kind == "ck_byte":
                return (61, 154, 204)
            else:
                return (59, 198, 64)
        return BIT_COLORS[self.color]


@dataclass
class Circuit:
    gates: list[GateReference]
    wires: list[CircuitWire]
    nand: int = 99_999
    delay: int = 99_999
    save_version: int = 0
    menu_visible: bool = True
    clock_speed: int = 100
    nesting_level: int = 1
    description: str = ""
    unpacked: bool = False
    camera_position: tuple[int, int] = (0, 0)

    shape: GateShape | None = None
    store_score: bool = False
    _raw_nim_data: dict = field(default_factory=dict)

    @classmethod
    def parse(cls, text: bytes) -> Circuit:
        data = save_monger.parse_state(list(text))
        return Circuit(
            [GateReference.from_nim(**c) for c in data["components"]],
            [CircuitWire.from_nim(**c) for c in data["circuits"]],
            data["nand"],
            data["delay"],
            data["save_version"],
            data["menu_visible"],
            data["clock_speed"],
            data["nesting_level"],
            data["description"],
            data["unpacked"],
            data["camera_position"],
            shape=None,
            _raw_nim_data=data
        )

    def to_bytes(self) -> bytes:
        self._raw_nim_data["components"] = [g.to_nim() for g in self.gates]
        self._raw_nim_data["circuits"] = [w.to_nim() for w in self.wires]
        return save_monger.state_to_binary(
            self.save_version,
            [g.to_nim() for g in self.gates],
            [w.to_nim() for w in self.wires],
            self.nand if self.store_score else 99_999,  # nand
            self.delay if self.store_score else 99_999,  # delay
            self.menu_visible,
            self.clock_speed,
            self.nesting_level,
            self.description,
            self.unpacked,
            self.camera_position,
        )

    def add_component(self, kind: str, pos: tuple[int, int], rotation: int = 0, **kwargs):
        new_id = max((g.id for g in self.gates), default=1) + 1
        self.gates.append(gf := GateReference(kind, pos, rotation, new_id, **kwargs))
        return gf

    def add_wire(self, path: list[Pos], kind: str = "ck_bit", **kwargs):
        kwargs.setdefault("color", 0)
        kwargs.setdefault("label", "")
        new_id = max((w.id for w in self.wires), default=1) + 1
        self.wires.append(w := CircuitWire(new_id, kind, positions=path, **kwargs))
        return w

    def bounding_box(self, include_wires: bool = False):
        from turing_complete_interface.tc_components import get_component

        start_x, start_y = (200, 200)
        end_x, end_y = (-200, -200)
        for g in self.gates:
            shape = get_component(g.name, g.custom_data if g.name != "Custom" else g.custom_id,
                                  no_node=True)[0]
            tl = g.translate(shape.bounding_box[:2])
            br = g.translate((shape.bounding_box[0] + shape.bounding_box[2],
                              shape.bounding_box[1] + shape.bounding_box[3]))
            if tl[0] < start_x:
                start_x = tl[0]
            if tl[1] < start_y:
                start_y = tl[1]
            if br[0] > end_x:
                end_x = br[0]
            if br[1] > end_y:
                end_y = br[1]
        if include_wires:
            for w in self.wires:
                for p in w.positions:
                    if p[0] < start_x:
                        start_x = p[0]
                    if p[1] < start_y:
                        start_y = p[1]
                    if p[0] > end_x:
                        end_x = p[0]
                    if p[1] > end_y:
                        end_y = p[1]

        if 200 == end_x == end_y == start_x == start_y:
            return (0, 0, 0, 0)
        else:
            return start_x, start_y, end_x - start_x, end_y - start_y

    @property
    def connections(self):
        connections: defaultdict[Pos, set[Pos]] = defaultdict(set)
        for wire in self.wires:
            if len(wire.positions) > 1:
                a, b = connections[wire.positions[0]], connections[wire.positions[-1]]
                if a is b:
                    continue
                assert a.isdisjoint(b)
                a.update({wire.positions[0], wire.positions[-1]})
                a.update(b)
                connections[wire.positions[-1]] = a
                for p in b:
                    connections[p] = a
        return connections


@dataclass
class BigShape:
    tl: tuple[int, int]
    size: tuple[int, int]

    @property
    def br(self):
        return self.tl[0] + self.size[0], self.tl[1] + self.size[1]


@dataclass
class CircuitPin:
    pos: tuple[int, int]
    is_input: bool
    is_byte: bool = False
    is_delayed: bool = False
    name: str = None


@dataclass
class GateShape:
    name: str
    color: tuple[int, int, int]
    pins: dict[str | int, CircuitPin]
    blocks: list[tuple[int, int]]
    is_io: bool = False
    text: Callable[[GateReference], str] = staticmethod(lambda gate: str(gate.custom_data or gate.name))
    big_shape: BigShape = None

    @property
    def bounding_box(self):
        min_x = min_y = float("inf")
        max_x = max_y = -float("inf")
        for p in (
                *(p.pos for p in self.pins.values()),
                *(self.blocks),
                *((self.big_shape.tl, self.big_shape.br) if self.big_shape is not None else ())
        ):
            if p[0] < min_x:
                min_x = p[0]
            if p[0] > max_x:
                max_x = p[0]

            if p[1] < min_y:
                min_y = p[1]
            if p[1] > max_y:
                max_y = p[1]
        assert all((isfinite(min_x), isfinite(max_x), isfinite(min_y), isfinite(max_y))), (min_x, max_x, min_y, max_y)
        return min_x, min_y, max_x - min_x + 1, max_y - min_y + 1

    def pin_position(self, gate_ref: GateReference | Pos, pin_name: str):
        if isinstance(gate_ref, GateReference):
            base = gate_ref.pos
        else:
            base = gate_ref
        p = self.pins[pin_name]
        return base[0] + p.pos[0], base[1] + p.pos[1]


SPECIAL_RED = (206, 89, 107)
SPECIAL_GREEN = (0, 179, 33)
NORMAL = (28, 95, 147)
CUSTOM = (30, 165, 174)


def get_path():
    match sys.platform.lower():
        case "windows" | "win32":
            potential_paths = [Path(os.path.expandvars(r"%APPDATA%\Godot\app_userdata\Turing Complete"))]
        case "darwin":
            potential_paths = [Path("~/Library/Application Support/Godot/app_userdata/Turing Complete").expanduser()]
        case "linux":
            potential_paths = [
                Path("~/.local/share/godot/app_userdata/Turing Complete").expanduser(),
                # for wsl
                Path(os.path.expandvars("/mnt/c/Users/${USER}/AppData/Roaming/godot/app_userdata/Turing Complete/")),
            ]
        case _:
            print(f"Don't know where to find Turing Complete save on {sys.platform=}")
            return None
    for base_path in potential_paths:
        if base_path.exists():
            break
    else:
        print("You need Turing Complete installed to use everything here")
        return None
    return base_path


BASE_PATH = get_path()

SCHEMATICS_PATH = BASE_PATH / "schematics" if BASE_PATH is not None else None

from BaseClasses import Location
from .Items import LEVEL_NAMES


class ABLLoc(Location):
    game = "A Bug's Life"

    LEVEL_NAME_TO_INDEX = {v: k for k, v in LEVEL_NAMES.items()}

    @staticmethod
    def get_level_index_from_location_name(location_name: str) -> int:
        level_part = location_name.split(" - ", 1)[0].strip()
        return ABLLoc.LEVEL_NAME_TO_INDEX.get(level_part, 0)


LOCATION_TABLE = {
    f"{level} - {suffix}": 1000 + (idx * 10) + off
    for idx, level in LEVEL_NAMES.items()
    for off, suffix in enumerate(
        [
            "F Letter",
            "L Letter",
            "I Letter",
            "K Letter",
            "FLIK Letters",
            "All Grain",
            "All Enemies",
            "Level Complete",
        ]
    )
}

GRAINSANITY_ID_BASE = 2000
ENEMYSANITY_ID_BASE = 3000

def grainsanity_location_id(level_index: int, grain_amount: int) -> int:
    return GRAINSANITY_ID_BASE + (level_index * 100) + grain_amount


def enemysanity_location_id(level_index: int, pct: int) -> int:
    tier = {25: 1, 50: 2, 75: 3, 100: 4}[pct]
    return ENEMYSANITY_ID_BASE + (level_index * 10) + tier


def build_grainsanity_locations(level_index: int, step: int, max_amount: int) -> dict[str, int]:
    out = {}
    step = max(1, min(50, int(step)))
    amt = step
    while amt <= max_amount:
        lvl = LEVEL_NAMES[level_index]
        out[f"{lvl} - {amt} Grain"] = grainsanity_location_id(level_index, amt)
        amt += step
    return out


def build_enemysanity_locations(
    level_index: int,
    max_enemies: int,
    enable_25: bool,
    enable_50: bool,
    enable_75: bool,
    enable_100: bool,
) -> dict[str, int]:
    out = {}
    if max_enemies <= 1:
        return out

    if max_enemies < 4:
        enable_25 = False
        enable_75 = False
        enable_50 = True
        enable_100 = True

    lvl = LEVEL_NAMES[level_index]
    for pct, enabled in ((25, enable_25), (50, enable_50), (75, enable_75), (100, enable_100)):
        if enabled:
            out[f"{lvl} - {pct}% Enemies"] = enemysanity_location_id(level_index, pct)

    return out

ALL_GRAINSANITY_LOCATIONS: dict[str, int] = {
    f"{level_name} - {amt} Grain": grainsanity_location_id(level_idx, amt)
    for level_idx, level_name in LEVEL_NAMES.items()
    for amt in range(1, 51)
}

ALL_ENEMYSANITY_LOCATIONS: dict[str, int] = {
    f"{level_name} - {pct}% Enemies": enemysanity_location_id(level_idx, pct)
    for level_idx, level_name in LEVEL_NAMES.items()
    for pct in (25, 50, 75, 100)
}
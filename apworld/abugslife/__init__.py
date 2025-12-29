from __future__ import annotations

import itertools
from typing import List, Dict, Any

from BaseClasses import Region, Entrance, Location, Item, ItemClassification
from worlds.AutoWorld import World, WebWorld
from worlds.generic.Rules import set_rule

from .Items import ITEM_TABLE, REVERSE_ITEM_TABLE, create_item, LEVEL_NAMES
from .Locations import (
    ABLLoc,
    LOCATION_TABLE,
    build_grainsanity_locations,
    build_enemysanity_locations,
    ALL_GRAINSANITY_LOCATIONS,
    ALL_ENEMYSANITY_LOCATIONS,
)

from .Options import BugsLifeOptions

GOLD_BERRY_LEVELS = {1, 6, 10, 11, 14, 7, 12, 8, 15}

BERRY_PROXY_BY_LEVEL: Dict[int, str] = {
    17: "purple",  # Training
    3:  "purple",  # Tunnels
    2:  "purple",  # Council Chamber
    4:  "purple",  # City Entrance
    5:  "purple",  # City Square
    13: "purple",  # Battle Arena
    9:  "yellow",  # Ant Hill, Part 2
}

LEVEL_COMPLETE_REQS: Dict[int, List[Dict[str, int]]] = {
    17: [{"brown": 1, "green": 2, "blue": 0, "yellow": 0, "berry": 0}],
    1:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    3:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    2:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 1}],
    6:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    10: [
        {"brown": 2, "green": 0, "blue": 0, "yellow": 0, "berry": 0},
        {"brown": 1, "green": 4, "blue": 0, "yellow": 0, "berry": 0},
    ],
    11: [
        {"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 1},
        {"brown": 1, "green": 0, "blue": 0, "yellow": 1, "berry": 0},
    ],
    4:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    5:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    14: [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 1}],
    7:  [{"brown": 4, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    12: [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    13: [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 1}],
    9:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 2, "berry": 0}],
    8:  [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 0}],
    15: [{"brown": 1, "green": 0, "blue": 0, "yellow": 0, "berry": 1}],
}

ENEMY_MAX_BY_LEVEL = {
    17: 4,
    1:  21,
    3:  50,
    2:  3,
    6:  12,
    10: 51,
    11: 9,
    4:  26,
    5:  23,
    14: 1,
    7:  24,
    12: 32,
    13: 4,
    9:  15,
    8:  56,
    15: 16,
}


class BugsLifeWeb(WebWorld):
    theme = "stone"
    tutorials = []


class VictoryLocation(Location):
    game: str = "A Bug's Life"


class BugsLifeWorld(World):
    game = "A Bug's Life"
    web = BugsLifeWeb()

    data_version = 0
    required_client_version = (0, 6, 0)

    item_name_to_id = ITEM_TABLE
    item_id_to_name = REVERSE_ITEM_TABLE
    location_name_to_id = {
        **LOCATION_TABLE,
        **ALL_GRAINSANITY_LOCATIONS,
        **ALL_ENEMYSANITY_LOCATIONS,
    }
    options_dataclass = BugsLifeOptions
    options: BugsLifeOptions

    def generate_early(self) -> None:
        dynamic: Dict[str, int] = {}

        if self.options.enable_grainsanity.value:
            step = int(self.options.grainsanity_step.value)
            for level_idx in LEVEL_NAMES.keys():
                dynamic.update(build_grainsanity_locations(level_idx, step, 50))

        if (
            self.options.enable_enemy_25.value
            or self.options.enable_enemy_50.value
            or self.options.enable_enemy_75.value
            or self.options.enable_enemy_100.value
        ):
            for level_idx in LEVEL_NAMES.keys():
                max_e = ENEMY_MAX_BY_LEVEL.get(level_idx, 0)
                dynamic.update(
                    build_enemysanity_locations(
                        level_idx,
                        max_e,
                        bool(self.options.enable_enemy_25.value),
                        bool(self.options.enable_enemy_50.value),
                        bool(self.options.enable_enemy_75.value),
                        bool(self.options.enable_enemy_100.value),
                    )
                )

        self._dynamic_location_table = dynamic

    def _location_enabled(self, loc_name: str) -> bool:
        suffix = loc_name.split(" - ", 1)[1] if " - " in loc_name else loc_name

        if suffix == "Level Complete":
            return bool(self.options.enable_level_complete.value)

        if suffix == "FLIK Letters":
            return bool(self.options.enable_flik_all.value)

        if suffix in ("F Letter", "L Letter", "I Letter", "K Letter"):
            return bool(self.options.enable_flik_individual.value)

        if suffix == "All Grain":
            return bool(self.options.enable_grain_all.value)

        if suffix.endswith(" Grain"):
            if not bool(self.options.enable_grainsanity.value):
                return False
            try:
                amt = int(suffix.split(" ", 1)[0])
            except Exception:
                return False
            step = int(self.options.grainsanity_step.value)
            return (amt % step) == 0

        if suffix.endswith(" Enemies") and "%" in suffix:
            try:
                pct = int(suffix.split("%", 1)[0])
            except Exception:
                return False

            return {
                25: bool(self.options.enable_enemy_25.value),
                50: bool(self.options.enable_enemy_50.value),
                75: bool(self.options.enable_enemy_75.value),
                100: bool(self.options.enable_enemy_100.value),
            }.get(pct, False)

        return True

    def create_regions(self) -> None:
        menu = Region("Menu", self.player, self.multiworld)
        self.multiworld.regions.append(menu)

        for level_idx, level_name in LEVEL_NAMES.items():
            r = Region(level_name, self.player, self.multiworld)
            self.multiworld.regions.append(r)
            e = Entrance(self.player, f"Menu -> {level_name}", menu)
            menu.exits.append(e)
            e.connect(r)

        for loc_name, loc_id in self.location_name_to_id.items():
            if not self._location_enabled(loc_name):
                continue
            level_idx = ABLLoc.get_level_index_from_location_name(loc_name)
            region_name = LEVEL_NAMES.get(level_idx, "Menu")
            region = self.multiworld.get_region(region_name, self.player)
            region.locations.append(ABLLoc(self.player, loc_name, loc_id, region))

        victory = VictoryLocation(self.player, "Victory", None, menu)
        victory.event = True
        menu.locations.append(victory)

    def create_items(self) -> None:
        victory_loc = self.multiworld.get_location("Victory", self.player)
        if not victory_loc.locked:
            event_item = Item("Victory", ItemClassification.progression, None, self.player)
            event_item.classification = ItemClassification.progression
            victory_loc.place_locked_item(event_item)

        total_locations = len(self.multiworld.get_unfilled_locations(self.player))

        required: Dict[tuple[str, int], int] = {}

        def bump(kind: str, level_idx: int, count: int) -> None:
            if count <= 0:
                return
            key = (kind, level_idx)
            required[key] = max(required.get(key, 0), count)

        def option_cost(opt: Dict[str, int]) -> int:
            return (
                max(0, opt.get("brown", 0) - 1)
                + max(0, opt.get("green", 0))
                + max(0, opt.get("blue", 0))
                + max(0, opt.get("yellow", 0))
                + max(0, opt.get("berry", 0))
            )

        if self.options.enable_level_complete.value:
            for level_idx, alternatives in LEVEL_COMPLETE_REQS.items():
                chosen = min(alternatives, key=option_cost)

                bump("brown", level_idx, max(0, chosen.get("brown", 0) - 1))
                bump("green", level_idx, max(0, chosen.get("green", 0)))
                bump("blue",  level_idx, max(0, chosen.get("blue", 0)))
                bump("yellow", level_idx, max(0, chosen.get("yellow", 0)))

                berry_tier = max(0, chosen.get("berry", 0))
                if berry_tier > 0:
                    if level_idx in GOLD_BERRY_LEVELS:
                        bump("berry", level_idx, berry_tier)
                    else:
                        proxy = BERRY_PROXY_BY_LEVEL.get(level_idx, "purple")
                        bump("purple" if proxy == "purple" else "yellow", level_idx, berry_tier)

        def name_for(kind: str, level_idx: int) -> str:
            lvl = LEVEL_NAMES[level_idx]
            if kind == "berry":
                return f"Progressive Berry Upgrade - {lvl}"
            return f"Progressive {kind.capitalize()} Seed Upgrade - {lvl}"

        itempool: List = []
        for (kind, level_idx) in sorted(required.keys(), key=lambda k: (k[1], k[0])):
            for _ in range(required[(kind, level_idx)]):
                itempool.append(create_item(self, name_for(kind, level_idx)))

        if len(itempool) > total_locations:
            raise Exception(
                f"Too many required progression items for enabled locations: "
                f"{len(itempool)} items for {total_locations} locations. "
                f"Disable some location categories/options."
            )

        missing = total_locations - len(itempool)
        if missing > 0:
            progressive_kinds = ["brown", "green", "blue", "purple", "yellow", "berry"]
            filler_cycle = [
                name_for(kind, level_idx)
                for level_idx in sorted(LEVEL_NAMES.keys())
                for kind in progressive_kinds
            ]
            for nm in itertools.islice(itertools.cycle(filler_cycle), missing):
                itempool.append(create_item(self, nm))

        total_locations_now = len(self.multiworld.get_unfilled_locations(self.player))
        toggle = False
        while len(itempool) < total_locations_now:
            itempool.append(create_item(self, "Extra Life" if not toggle else "Health Upgrade"))
            toggle = not toggle

        if len(itempool) != len(self.multiworld.get_unfilled_locations(self.player)):
            raise Exception(
                f"Itempool mismatch: items={len(itempool)} "
                f"locations={len(self.multiworld.get_unfilled_locations(self.player))}"
            )

        self.multiworld.itempool += itempool

    def set_rules(self) -> None:
        def tier_to_required_progressives(seed: str, tier: int) -> int:
            if seed == "brown":
                return max(0, tier - 1)
            return max(0, tier)

        def has_seed_tier(state, level_idx: int, seed: str, tier: int) -> bool:
            if tier <= 0:
                return True
            required = tier_to_required_progressives(seed, tier)
            level_name = LEVEL_NAMES[level_idx]
            item_name = f"Progressive {seed.capitalize()} Seed Upgrade - {level_name}"
            return state.has(item_name, self.player, required)

        def has_berry_tier(state, level_idx: int, tier: int) -> bool:
            if tier <= 0:
                return True

            level_name = LEVEL_NAMES[level_idx]

            if level_idx in GOLD_BERRY_LEVELS:
                return state.has(f"Progressive Berry Upgrade - {level_name}", self.player, tier)

            proxy = BERRY_PROXY_BY_LEVEL.get(level_idx, "purple")
            if proxy == "yellow":
                return has_seed_tier(state, level_idx, "yellow", tier)
            return has_seed_tier(state, level_idx, "purple", tier)

        def option_satisfied(state, level_idx: int, opt: Dict[str, int]) -> bool:
            return (
                has_seed_tier(state, level_idx, "brown", opt.get("brown", 0))
                and has_seed_tier(state, level_idx, "green", opt.get("green", 0))
                and has_seed_tier(state, level_idx, "blue", opt.get("blue", 0))
                and has_seed_tier(state, level_idx, "yellow", opt.get("yellow", 0))
                and has_berry_tier(state, level_idx, opt.get("berry", 0))
            )

        if self.options.enable_level_complete.value:
            for level_idx, options in LEVEL_COMPLETE_REQS.items():
                loc_name = f"{LEVEL_NAMES[level_idx]} - Level Complete"
                try:
                    loc = self.multiworld.get_location(loc_name, self.player)
                except KeyError:
                    continue
                set_rule(
                    loc,
                    lambda state, li=level_idx, opts=options: any(
                        option_satisfied(state, li, o) for o in opts
                    ),
                )

        self.multiworld.completion_condition[self.player] = (
            lambda state: state.can_reach_location("Victory", self.player)
        )

    def fill_slot_data(self) -> Dict[str, Any]:
        enable_level_complete = int(self.options.enable_level_complete.value)
        enable_grain_all = int(self.options.enable_grain_all.value)
        enable_grainsanity = int(self.options.enable_grainsanity.value)
        grainsanity_step = int(self.options.grainsanity_step.value)
        enable_flik_all = int(self.options.enable_flik_all.value)
        enable_flik_individual = int(self.options.enable_flik_individual.value)
        enable_enemy_25 = int(self.options.enable_enemy_25.value)
        enable_enemy_50 = int(self.options.enable_enemy_50.value)
        enable_enemy_75 = int(self.options.enable_enemy_75.value)
        enable_enemy_100 = int(self.options.enable_enemy_100.value)

        return {
            "goal": int(self.options.goal.value),

            "enable_level_complete": enable_level_complete,
            "enable_grain_all": enable_grain_all,
            "enable_grainsanity": enable_grainsanity,
            "grainsanity_step": grainsanity_step,
            "enable_flik_all": enable_flik_all,
            "enable_flik_individual": enable_flik_individual,
            "enable_enemy_25": enable_enemy_25,
            "enable_enemy_50": enable_enemy_50,
            "enable_enemy_75": enable_enemy_75,
            "enable_enemy_100": enable_enemy_100,

            "level_complete": enable_level_complete,
            "grain_all": enable_grain_all,
            "grainsanity": enable_grainsanity,
            "step": grainsanity_step,
            "flik_all": enable_flik_all,
            "flik_individual": enable_flik_individual,
            "enemy25": enable_enemy_25,
            "enemy50": enable_enemy_50,
            "enemy75": enable_enemy_75,
            "enemy100": enable_enemy_100,
        }

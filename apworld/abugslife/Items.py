from BaseClasses import Item, ItemClassification


class ABLItem(Item):
    game = "A Bug's Life"


LEVEL_NAMES = {
    1: "Ant Hill",
    2: "Council Chamber",
    3: "Tunnels",
    4: "City Entrance",
    5: "City Square",
    6: "Cliffside",
    7: "Clover Forest",
    8: "Riverbed Flight",
    9: "Ant Hill, Part 2",
    10: "Riverbed Canyon",
    11: "Bird Nest",
    12: "The Tree",
    13: "Battle Arena",
    14: "Bug Bar",
    15: "Canyon Showdown",
    17: "Training",
}

ITEM_TABLE = {
    "Extra Life": 210,
    "Health Upgrade": 211,
}

PROGRESSIVE_PREFIXES = {
    "Berry": 300,
    "Brown Seed": 400,
    "Green Seed": 500,
    "Blue Seed": 600,
    "Purple Seed": 700,
    "Yellow Seed": 800,
}

for level_idx, level_name in LEVEL_NAMES.items():
    for label, base in PROGRESSIVE_PREFIXES.items():
        ITEM_TABLE[f"Progressive {label} Upgrade - {level_name}"] = base + level_idx

REVERSE_ITEM_TABLE = {v: k for k, v in ITEM_TABLE.items()}


def create_item(world, name: str) -> ABLItem:
    code = ITEM_TABLE[name]
    classification = (
        ItemClassification.progression
        if name.startswith("Progressive ")
        else ItemClassification.filler
    )
    return ABLItem(name, classification, code, world.player)

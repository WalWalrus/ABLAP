from dataclasses import dataclass

from Options import Choice, Toggle, PerGameCommonOptions, Range


class Goal(Choice):
    """Seed goal condition.

    Currently only supports:
    - All Levels Complete
    """
    display_name = "Goal"
    option_all_levels_complete = 0
    default = 0


class EnableLevelCompleteChecks(Toggle):
    """Enable Level Complete checks for each level.

    Safe to enable.
    """
    display_name = "Enable Level Complete checks"
    default = 1


class EnableAllGrainChecks(Toggle):
    """EXPERIMENTAL / UNSUPPORTED

    Adds 'All Grain' checks (equivalent to 50/50).

    Access rules are NOT implemented yet. May produce unreachable checks.
    """
    display_name = "Enable All Grain checks"
    default = 0


class EnableGrainsanity(Toggle):
    """Adds checks for collecting grain in steps (e.g. every 10 grain).

    Access rules are NOT implemented yet.
    This can create unreachable checks / softlocks depending on seed.
    """
    display_name = "Enable Grainsanity"
    default = 0


class GrainsanityStep(Range):
    """How many grain per Grainsanity check.

    Example: 10 means checks at 10, 20, 30, 40, 50 (up to max).
    """
    display_name = "Grainsanity step"
    range_start = 1
    range_end = 50
    default = 10

class EnableFlikAllLetters(Toggle):
    """EXPERIMENTAL

    Adds 'FLIK Letters (All)' checks.

    Access rules not implemented yet.
    """
    display_name = "Enable FLIK (all letters) checks"
    default = 0


class EnableFlikIndividualLetters(Toggle):
    """EXPERIMENTAL

    Adds individual FLIK checks.

    Access rules not implemented yet.
    """
    display_name = "Enable individual FLIK checks"
    default = 0


class EnableEnemy25PctChecks(Toggle):
    """Adds checks for killing ~25% of enemies in a level.

    Access rules are NOT implemented yet (can softlock).
    """
    display_name = "Enable 25% enemy checks"
    default = 0


class EnableEnemy50PctChecks(Toggle):
    """Adds checks for killing ~50% of enemies in a level.

    Access rules are NOT implemented yet (can softlock).
    """
    display_name = "Enable 50% enemy checks"
    default = 0


class EnableEnemy75PctChecks(Toggle):
    """Adds checks for killing ~75% of enemies in a level.

    Access rules are NOT implemented yet (can softlock).
    """
    display_name = "Enable 75% enemy checks"
    default = 0


class EnableEnemy100PctChecks(Toggle):
    """Adds checks for killing ~75% of enemies in a level.

    Access rules are NOT implemented yet (can softlock).
    """
    display_name = "Enable 100% enemy checks"
    default = 0


@dataclass
class BugsLifeOptions(PerGameCommonOptions):
    goal: Goal
    enable_level_complete: EnableLevelCompleteChecks

    enable_grain_all: EnableAllGrainChecks
    enable_grainsanity: EnableGrainsanity
    grainsanity_step: GrainsanityStep

    enable_flik_all: EnableFlikAllLetters
    enable_flik_individual: EnableFlikIndividualLetters

    enable_enemy_25: EnableEnemy25PctChecks
    enable_enemy_50: EnableEnemy50PctChecks
    enable_enemy_75: EnableEnemy75PctChecks
    enable_enemy_100: EnableEnemy100PctChecks

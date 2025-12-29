## What does randomization do to this game?

When the player completes a task (such as completing a level), an item is sent.

This does not randomize the location of grain, FLIK tokens, enemies or make large-scale cosmetic changes to the game.

Berries and seed tokens now do nothing when collected and must be received via location checks in order to progress in levels.

## What items and locations get shuffled?
All berries and seed tokens are always shuffled - if there are too few locations in the pool then required seeds/berries will be included before optional ones. Health and lives are also added to the pool if there are more locations than items. Health will increment the player's health counter by 1. Lives will increment by 1 each time (with a max of 9).

## Which items can be in another player's world?

Any of the items which can be shuffled may also be placed into another player's world.

## What does another world's item look like in A Bug's Life?

The visuals of the game are unchanged by the Archipelago randomization. The A Bug's Life Archipelago Client will display the obtained item and to whom it belongs.

## When the player receives an item, what happens?

The player's game and HUD will update accordingly. Some effects, such as receiving seed tokens may cause some UI issues but these should be cosmetic and not affect functionality.

If for any reason the player is not in the game when items come in, there may be a temporary desync.

## Known Issues

- Receiving seed tokens in some levels causes the UI to have issues but is only cosmetic.
- Some experimental checks will be unreachable due to lack of logic surrounding their collection.

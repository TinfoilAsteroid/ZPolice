# Salvage rewards

Salvage points are earned at the end of each level: **1 point for each
human saved** on that level. This includes everyone still aboard the VTOL
when the level ends. The total carries over from level to level and goes
into the save game. A new game starts at 0.

Each time the total reaches or passes one of the scores below, you get that
reward. If a level's rescues take the total past several scores at once,
you get every reward along the way. The rewards are listed on the LEVEL
COMPLETE screen.

A weapon reward puts one more of that weapon in the store, to fit on the
load-out screen. A full repair restores the VTOL to full integrity.

## Rewards by score

| Salvage | Weapon to the store | Other                                             |
|--------:|---------------------|---------------------------------------------------|
| 10      | Pulse laser         |                                                   |
| 15      |                     | Full repair                                       |
| 20      | Chain gun           |                                                   |
| 25      |                     | Night Vision - Green, fitted at once              |
| 30      | Rocket pod          |                                                   |
| 35      |                     | Vertical Thrusters, fitted at once: climb to 30 m |
| 40      | Bomb                |                                                   |
| 45      |                     | Booster module, fitted at once, its tank full     |
| 50      | Chain gun           |                                                   |
| 55      | Proximity cannon    | Full repair                                       |
| 60      | Rocket pod          |                                                   |
| 65      | Pulse laser         | Night Vision - Monochrome, fitted at once         |
| 70      | Proximity cannon    | Full repair                                       |
| 75      | Chain gun           |                                                   |
| 80      | Rocket pod          |                                                   |
| 85      |                     | Thermal Vision, fitted at once                    |
| 90      | Pulse laser         |                                                   |
| 95      | Chain gun           |                                                   |
| 100     | Rocket pod          | Full repair                                       |
| 105     | Autocannon          | Full repair                                       |
| 110     | Autocannon          | Full repair                                       |
| 115     | Missile pod         | Full repair                                       |
| 120     | Autocannon          | Full repair                                       |
| 125     | Autocannon          | Full repair                                       |
| 130     | Missile pod         | Full repair                                       |
| 135     | Missile pod         | Full repair                                       |
| 140     | Missile 
1pod         | Full repair                                       |
| 145     | Missile pod         | Full repair                                       |
| 150     |                     | Full repair, every 5 points from then on          |
| 155     |                     | Full repair, every 5 points from then on          |
| 160     |                     | Full repair, every 5 points from then on          |

## Totals

| Reward                    | How many | At                                         |
|---------------------------|---------:|--------------------------------------------|
| Pulse laser               | 3        | 10, 65, 90                                 |
| Chain gun                 | 4        | 20, 50, 75, 95                             |
| Rocket pod                | 4        | 30, 60, 80, 100                            |
| Autocannon                | 4        | 105, 110, 120, 125                         |
| Missile pod               | 5        | 115, 130, 135, 140, 145                    |
| Proximity cannon          | 2        | 55, 70                                     |
| Bomb                      | 1        | 40                                         |
| Booster module            | 1        | 45                                         |
| Night Vision - Green      | 1        | 25                                         |
| Night Vision - Monochrome | 1        | 65                                         |
| Thermal Vision            | 1        | 85                                         |
| Vertical Thrusters        | 1        | 35                                         |
| Full repair               | 3        | below 100, then every 5 points from 100 on | 

The vertical thrusters become part of the VTOL: from then on it can climb
to 30 m instead of 15 m, with no fuel needed. While they're fitted, the
HUD's altitude bar is drawn at half scale, so 30 m fills it.

The vision modes go straight onto the VTOL, as the booster does. N steps
through the ones it has in flight (see README "Vision modes").

The bomb goes on a wing pylon, one to a pod. It glides down from 10°,
steepening as it falls, and its blast does 30 damage to everything within
2 tiles, the VTOL included (see README "Bomb").

## Not given by salvage

- **Ammunition:** at the end of every level, every fitted weapon gets its
  full load back. This happens whatever your score, so it isn't a salvage
  reward.
- **Machine gun:** fitted in slot 1 at the start of a new game. It is never
  a reward.

## Where it's set

- **The scores:** in `salvage_tab` in `menu.asm`. Each entry is a score,
  then a weapon (`WPN_NONE` for none), then flags: `SA_REPAIR` (1, full
  repair), `SA_BOOSTER` (2, the booster module), `SA_NV_GREEN` (4),
  `SA_NV_MONO` (8) and `SA_THERMAL` (16), the vision modes, and `SA_VTHRUST`
  (32), the vertical thrusters. The scores must be in
  rising order, and `$FFFF` ends the table.
- **After the table:** the last score is `SALVAGE_TAIL` (145). From then on
  there is a full repair every `SALVAGE_STEP` (5) points.
- **The awards:** made by `salvage_award` in `menu.asm`.
- **Keep the copies in step:** if you change the table, update this file
  and the copy in README (under "Waves and level progress").

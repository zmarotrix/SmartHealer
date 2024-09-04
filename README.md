# SmartHealer

*for World of Warcraft 1.12.1 (Vanilla)*

Autoscales heals in macros (/heal <spell_name>) and click heals for:

- pfUI (both via button-healing and via /pfcast)
- pfUI-quickcast (/pfquickcast@heal*)
- Clique
- ClassicMouseover

Scaling is done using HealComm-1.0 library (part of the package) or [TheoryCraft](https://wow.curseforge.com/projects/project-1644) (if present).

Addon checks missing HPs of target (or player if self cast), compares it with calculated healing done and selects the lowest rank needed to fully heal the target. If TheoryCraft is
installed, addon also checks if you have enough mana to cast spell of selected rank. If you do not, it will try to use highest possible rank for which you have enough mana.

## Commands:

- `/heal <spell_name>[, overheal_multiplier]`  
  Used in macros to cast optimal rank of heal.  
  Overheal multiplier is optional and should be separated from spell name by comma "," or semicolon ";". It will override dafault overheal multiplier. See the next command.  

- `/sh_overheal <multiplier>`  
  Sets the new default overheal multiplier. When selecting spell rank, calculated heal must be higher than the missing HP * multiplier. Valid multiplier is number or percentage (1.15 or 115%).   
  If used without argument, prints current overheal multiplier.  

- `/sh_overheal   <category>   <multiplier>` 
  Sets the new overheal multiplier for <category>. If category is not found, it will be created.
  
- `/sh_toggle_player_in_category   <category>    <player_name>`  
  Adds or removes player_name from tanks category. If player_name is not in the category, it will be added. If it is, it will be removed. If you omit player_name then the currently mouse-hovered
  player will be added/removed (if you are not hovering over a player then the currently targeted player will be selected).

- `/sh_reset_all_categories`  
  Resets all categories to the default ones.

- `/sh_delete_category  <category>`
  Deletes the category.

- `/sh_clear_registry  <category>`
  Clears all players registered in the given category (but the category is not deleted). If you omit the category, it will clear all categories of player-names.

*NOTE:*  
Spell name can contain a rank. If there is a rank, heal will be scaled but with the specified rank set a max-cap. This means that `/heal Healing Wave` will rank as needed all the way up to
the maximum available rank that you know if necessary, but `/heal Healing Wave(Rank 3)` can only be ranked from 1 to 3.  
  

## Installation

1. Download **[Latest Version](https://github.com/melbaa/SmartHealer/archive/refs/heads/master.zip)**
2. Unpack the Zip file
3. Rename the folder "SmartHealer-master" to "SmartHealer"
4. Copy "SmartHealer" into \<WoW-directory\>\Interface\AddOns
5. Restart WoW

### Credits:

- Garkin's repo https://gitlab.com/AMGarkin/SmartHealer  
- Original idea of this addon is based on Ogrisch's [LazySpell](https://github.com/satan666/LazySpell).

PokeBattle_Battle::BattleStartApplyCurse.add(:CURSE_FORCE_PERFECT,
    proc { |curse_policy, _side, battle, curses_array|
        battle.amuletActivates(
            _INTL("A single error cuts through the world-flesh/\nand the rot of entropy begins to feed"),
            _INTL("You immediately white out if one of your Pokémon faints."),
            true
        )
        curses_array.push(curse_policy)
        next curses_array
    }
)

PokeBattle_Battle::BattlerFaintedCurseEffect.add(:CURSE_FORCE_PERFECT,
    proc { |curse_policy, battler, battle|
        next unless battler.curseVictim?(curse_policy)
        battle.pbDisplay(_INTL("You're overwhelmed by the power of the curse!"))
        # decision is keyed to which party (1 or 2, i.e. side 0 or 1) wins,
        # not to holder/victim -- the fainted battler here is always the
        # victim, so its idxOpposingSide is the curse holder's side.
        battle.decision = battler.idxOpposingSide + 1
    }
)

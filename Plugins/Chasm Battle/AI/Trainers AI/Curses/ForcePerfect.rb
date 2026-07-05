PokeBattle_Battle::BattleStartApplyCurse.add(:CURSE_FORCE_PERFECT,
    proc { |curse_policy, battle, curses_array|
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
    proc { |_curse_policy, battler, battle|
        next if battler.opposes?
        battle.pbDisplay(_INTL("You're overwhelmed by the power of the curse!"))
        battle.decision = 2
    }
)

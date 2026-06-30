PokeBattle_Battle::BattleStartApplyCurse.add(:CURSE_SPIKES,
    proc { |curse_policy, _side, battle, curses_array|
        battle.amuletActivates(
            _INTL("Gored Upon the Horns of the Dilemma - Boredom or the Path of Thorns?"),
            _INTL("Your side gains spikes each turn, except if removed that turn."),
        )
        curses_array.push(curse_policy)
        next curses_array
    }
)

PokeBattle_Battle::EndOfTurnCurseEffect.add(:CURSE_SPIKES,
    proc { |curse_policy, side, battle|
        victimSide = side ^ 1
        if battle.sides[victimSide].effectActive?(:SpikesRemovedThisTurn)
            battle.pbDisplay(_INTL("You were spared from spikes this turn!"))
        else
            battle.sides[victimSide].incrementEffect(:Spikes)
        end
    }
)
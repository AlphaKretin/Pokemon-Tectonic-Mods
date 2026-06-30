PokeBattle_Battle::BattleStartApplyCurse.add(:CURSE_NO_MOVING_CYCLICAL,
    proc { |curse_policy, _side, battle, curses_array|
        battle.amuletActivates(
            _INTL("Move, call, step, stop.\nRend, rive, dare, halt.\nClaw, cull, dive, hold.\nFend, flee, fail, fall."),
            _INTL("Your Pokémon cannot use moves on every 4th turn.")
        )
        curses_array.push(curse_policy)
        next curses_array
    }
)

PokeBattle_Battle::BeginningOfTurnCurseEffect.add(:CURSE_NO_MOVING_CYCLICAL,
    proc { |curse_policy, side, battle|
        victimSide = side ^ 1
        if battle.turnCount % 4 == 0
            battle.eachSameSideBattler(victimSide) do |b|
                battle.pbAnimation(:SHEERCOLD, b, b)
                b.applyEffect(:IceSculpture)
            end
            battle.sides[victimSide].applyEffect(:IceSculptureTurns, 4)
        elsif battle.turnCount % 4 == 3
            battle.pbDisplay(_INTL("The freeze will arrive next turn."))
        end
    }
)
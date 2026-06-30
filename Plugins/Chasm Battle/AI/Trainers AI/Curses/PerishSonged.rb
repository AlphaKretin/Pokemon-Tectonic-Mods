PokeBattle_Battle::BattleStartApplyCurse.add(:CURSE_PERISH_SONGED,
    proc { |curse_policy, _side, battle, curses_array|
        battle.amuletActivates(
            _INTL("A Litany of Lullabies, Seldom Sung"),
            _INTL("Your Pokemon gain the \"Perish Song\" status when they enter battle.")
        )
        curses_array.push(curse_policy)
        next curses_array
    }
)

PokeBattle_Battle::BattlerEnterCurseEffect.add(:CURSE_PERISH_SONGED,
    proc { |curse_policy, battler, _battle|
        next unless battler.curseVictim?(curse_policy)
        battler.applyEffect(:PerishSong, 4)
    }
)

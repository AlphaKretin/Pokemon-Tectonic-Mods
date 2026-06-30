PokeBattle_Battle::BattleStartApplyCurse.add(:CURSE_AVATAR_GUARD,
    proc { |curse_policy, side, battle, curses_array|
        battle.amuletActivates(
            _INTL("Escorted by, Enthroned upon, Ensconced within this Empty Eminence"),
            _INTL("An Avatar has been inserted into Yezera's party!")
        )

        # Insert the avatar into the cursed trainer's own party
        newPokemon = generateAvatarPokemon(:LINOONE,65)
        partyIndex = battle.pbParty(side).length
        battle.pbParty(side)[partyIndex] = newPokemon

        curses_array.push(curse_policy)
        next curses_array
    }
)
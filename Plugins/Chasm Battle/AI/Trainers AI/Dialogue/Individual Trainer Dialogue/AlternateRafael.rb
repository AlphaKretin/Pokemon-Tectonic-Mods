NON_AVATAR_LEGEND = %i[ARTICUNO ZAPDOS MOLTRES G. ARTICUNO G. ZAPDOS G. MOLTRES MEWTWO MEW LUGIA HO-OH CELEBI REGIROCK REGICE REGISTEEL REGIELEKI REGIDRAGO LATIAS LATIOS JIRACHI UXIE MESPRIT AZELF DIALGA PALKIA HEATRAN GIRATINA CRESSELIA MANAPHY ARCEUS TORNADUS THUNDURUS  LANDORUS ENAMORUS VICTINI HOOPA VOLCANION TYPE:NULL SILVALLY TAPU KOKO TAPU LELE TAPU FINI TAPU BULU COSMOG COSMOEM SOLGALEO LUNALA NIHILEGO BUZZWOLE PHEROMOSA XURKITREE  CELESTEELA KARTANA GUZZLORD POIPOLE NAGANADEL STAKATAKA BLACEPHALON MAGEARNA MARSHADOW MELTAN MELMETAL ETERNATUS KUBFU URSHIFU ZARUDE]

NON_RAF_LEGEND = %i[ZERAORA MELOETTA SHAYMIN ZAMAZENTA RAIKOU ENTEI SUICUNE COBALION TERRAKION VIRIZION ZACIAN ZAMAZENTA XERNEAS ZYGARDE KYOGRE DARKRAI GENESECT GLASTRIER NECROZMA]

RAF_LEGEND_MON = %i[DIANCIE CALYREX SPECTRIER DEOXYS RAYQUAZA YVELTAL GROUDON]

RAF_GYM_MON = %i[BELLOSSOM M. NINETALES WHIMSICOTT A. MAROWAK ORICORIO DHELMISE CHESNAUGHT CRADILY]

PokeBattle_AI::PlayerSendsOutPokemonDialogue.add(:ALTERNATE_RAFAEL,
  proc { |_policy, battler, trainer_speaking, dialogue_array|
      if NON_AVATAR_LEGEND.include?(battler.species) && !trainer_speaking.policyStates[:NonAvatarDialogue]
          dialogue_array.push(_INTL("How interesting."))
          dialogue_array.push(_INTL("I'll need to collect one of those, too."))
          trainer_speaking.policyStates[:NonAvatarDialogue] = true
      elsif NON_RAF_LEGEND.include?(battler.species) && !trainer_speaking.policyStates[:AvatarLegendDialogue]
          dialogue_array.push(_INTL("{1}, huh?", battler.pokemon&.speciesName))
          dialogue_array.push(_INTL("I destroyed that avatar years ago."))
          dialogue_array.push(_INTL("Now, I'll destroy it in the flesh."))
          trainer_speaking.policyStates[:AvatarLegendDialogue] = true
      elsif RAF_LEGEND_MON.include?(battler.species) && !trainer_speaking.policyStates[:RafLegendDialogue]
          dialogue_array.push(_INTL("You have one too? Copycat."))
          dialogue_array.push(_INTL("At least this will be a real fight for once."))
          trainer_speaking.policyStates[:RafLegendDialogue] = true
      elsif RAF_GYM_MON.include?(battler.species) && !trainer_speaking.policyStates[:RafTeamDialogue]
          dialogue_array.push(_INTL("I used to like that one. When I was weaker..."))
          trainer_speaking.policyStates[:RafTeamDialogue] = true
      end
      next dialogue_array
  }
)

PokeBattle_AI::TrainerSendsOutPokemonDialogue.add(:ALTERNATE_RAFAEL,
  proc { |_policy, battler, trainer_speaking, dialogue_array|
      if battler.battle.pbAbleCount(battler.index) == battler.battle.sideSizes[1] && !trainer_speaking.policyStates[:LastPokemonComment]
          dialogue_array.push(_INTL("I still win these. I always win these."))
          trainer_speaking.policyStates[:LastPokemonComment] = true
      end
      next dialogue_array
  }
)

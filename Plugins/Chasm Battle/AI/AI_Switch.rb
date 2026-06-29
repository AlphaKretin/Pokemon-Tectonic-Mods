class Integer
    def to_change
        if self >= 0
            return "+" + to_s
        else
            return to_s
        end
    end
end

class PokeBattle_AI
    def pbEnemyShouldWithdraw?(idxBattler)
        return false if @battleArena
        return battlePalaceWithdraw?(idxBattler) if @battleArena
        chosenPartyIndex = pbDetermineSwitch(idxBattler)
        if chosenPartyIndex >= 0
            @battle.pbRegisterSwitch(idxBattler, chosenPartyIndex)
            return true
        end
        return false
    end

    def battlePalaceWithdraw?(idxBattler)
        thispkmn = @battle.battlers[idxBattler]
        shouldswitch = false
        if thispkmn.effects[:PerishSong] == 1
            shouldswitch = true
        elsif !@battle.pbCanChooseAnyMove?(idxBattler) &&
              thispkmn.turnCount && thispkmn.turnCount > 5
            shouldswitch = true
        else
            hppercent = thispkmn.hp * 100 / thispkmn.totalhp
            percents = []
            maxindex = -1
            maxpercent = 0
            factor = 0
            @battle.pbParty(idxBattler).each_with_index do |pkmn, i|
                if @battle.pbCanSwitch?(idxBattler, i)
                    percents[i] = 100 * pkmn.hp / pkmn.totalhp
                    if percents[i] > maxpercent
                        maxindex = i
                        maxpercent = percents[i]
                    end
                else
                    percents[i] = 0
                end
            end
            if hppercent < 50
                factor = (maxpercent < hppercent) ? 20 : 40
            end
            if hppercent < 25
                factor = (maxpercent < hppercent) ? 30 : 50
            end
            case thispkmn.status
            when :SLEEP
                factor += 20
            when :POISON
                factor += 10
            when :BURN
                factor += thispkmn.getStatusCount(:BURN) > 0 ? 20 : 10 # Severe status check
            when :FROSTBITE
                factor += thispkmn.getStatusCount(:FROSTBITE) > 0 ? 20 : 10 # Severe status check
            when :NUMB
                factor += thispkmn.getStatusCount(:NUMB) > 0 ? 30 : 15 # Severe status check
            end
            if @justswitched[idxBattler]
                factor -= 60
                factor = 0 if factor < 0
            end
            shouldswitch = (pbAIRandom(100) < factor)
            if shouldswitch && maxindex >= 0
                @battle.pbRegisterSwitch(idxBattler, maxindex)
                return true
            end
        end
        @justswitched[idxBattler] = shouldswitch
        if shouldswitch
            @battle.pbParty(idxBattler).each_with_index do |_pkmn, i|
                next unless @battle.pbCanSwitch?(idxBattler, i)
                @battle.pbRegisterSwitch(idxBattler, i)
                return true
            end
        end
        return false
    end

    def pbDetermineSwitch(idxBattler)
        battler = @battle.battlers[idxBattler]
        owner = @battle.pbGetOwnerFromBattlerIndex(idxBattler)

        stayInRating = 0
        PBDebug.log("[AI SWITCH] #{battler.pbThis} (#{battler.index}) is determining whether it should switch out")

        # Defensive matchup
        defensiveMatchupRating, killInfoArray = worstDefensiveMatchupAgainstActiveFoes(battler)
        defensiveMatchupRating = (0.5 * defensiveMatchupRating).floor
        stayInRating += defensiveMatchupRating
        PBDebug.log("[STAY-IN RATING] #{battler.pbThis} defensive matchup rating: #{defensiveMatchupRating.to_change}")

        # Value of its own moves
        bestMoveScore, killInfo = switchRatingBestMoveScore(battler, killInfoArray: killInfoArray)
        offensiveMatchupRating = (0.5 * bestMoveScore).floor
        
        urgency = 0
        if offensiveMatchupRating < 0
            urgency = battler.getUrgency
            PBDebug.log("[STAY-IN RATING] Urgency is #{urgency}")
            offensiveMatchupRating -= urgency
        else
            PBDebug.log("[STAY-IN RATING] No Urgency is needed")
        end
        
        stayInRating += offensiveMatchupRating
        PBDebug.log("[STAY-IN RATING] #{battler.pbThis} offensive matchup rating: #{offensiveMatchupRating.to_change}")

        # Other things that affect the stay in rating
        stayInRating += miscStayInRatingModifiers(battler)
        stayInRating += speedTierRating(battler)
        stayInRating += battler.levelNerfSwitch(0.4).round # AI nerf

        # Only considers swapping into pokemon whose rating would be at least a +30 upgrade
        upgradeThreshold = 30
        upgradeThreshold -= 5 if owner.tribalBonus.hasTribeBonus?(:CHARMER)

        # Determine who to swap into if at all
        PBDebug.log("[AI SWITCH] #{battler.pbThis} (#{battler.index}) is trying to find a switch. Staying in is rated: #{stayInRating}.")
        list = pbGetPartyWithSwapRatings(idxBattler, urgency, futilityThreshold: stayInRating + upgradeThreshold)
        listSwapOutCandidates(battler, list)

        list.delete_if { |val| val[1] < stayInRating + upgradeThreshold }

        if list.empty?
            PBDebug.log("[AI SWITCH] #{battler.pbThis} (#{battler.index}) fails to find any swap candidates (stay-in rating: #{stayInRating}).")
        else
            partySlotNumber = list[0][0]
            if @battle.pbCanSwitch?(idxBattler, partySlotNumber)
                PBDebug.log("[AI SWITCH] #{battler.pbThis} (#{idxBattler}) will switch with #{@battle.pbParty(idxBattler)[partySlotNumber].name}")
                return partySlotNumber
            end
        end
        return -1
    rescue StandardError => exception
        pbPrintException($!) if $DEBUG
        echoln("FAILURE ENCOUNTERED IN pbDetermineSwitch FOR BATTLER INDEX #{idxBattler}")
        return -1
    end

    def miscStayInRatingModifiers(battler)
        stayInRating = 0

        # Less likely to switch when coming in later would cause it to die to hazards
        entryDamage, hazardScore = @battle.applyHazards(battler, true)
        if entryDamage >= battler.hp
            stayInRating += 30
            PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) likely to die to hazards if switches back in later (+30)")
            return stayInRating # Selfish modifiers don't matter
        end

        # Pokémon is about to faint because of Perish Song
        if battler.effects[:PerishSong] == 2
            stayInRating -= 10
            PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is soon-ish to die to perish song (-10)")
        elsif battler.effects[:PerishSong] == 1
            stayInRating -= 25
            stayInRating -= 25 if battler.hp > battler.totalhp / 2
            PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is about to die to perish song (#{stayInRating})")
        end

        # More likely to switch when poison has worsened
        if battler.poisoned?
            poisonBias = -10 * (2 ** battler.getPoisonDoublings)
            stayInRating += poisonBias
            PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is poisoned at count (#{battler.getStatusCount(:POISON)}) (#{poisonBias.to_change})")
        end

        # Switch influencing effect of certain battler effects
        battler.eachEffect(true) do |effect, value, effectData|
            next unless effectData.stay_in_rating_proc
            oldStayInRating = stayInRating
            stayInRating = effectData.stay_in_rating_proc.call(@battle, battler, value, stayInRating)
            ratingChange = stayInRating - oldStayInRating
            if ratingChange != 0
                PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) has effect #{effectData.real_name} (#{ratingChange})")\
            end
        end

        # Less likely to switch when any opponent has a force switch out move
        # Even less likely if the opponent just used such a move
        battler.eachOpposing do |b|
            if b.hasForceSwitchMove?
                stayInRating += 10
                PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) has an opponent that can force swaps (+10)")
            end

            pursuitMove = b.canChoosePursuit?(battler)
            if pursuitMove
                pursuitScore, pursuitKillInfo = pbGetMoveScore(pursuitMove, b, battler)
                pursuitScore = (pursuitScore / PokeBattle_AI::EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO).ceil
                stayInRating += pursuitScore
                PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) has an opponent that can target it with pursuit (#{pursuitScore.to_change})")
            end
        end

        # Less likely to switch when has perrenial payload
        stayInRating += 15 if battler.hasActiveAbilityAI?(:PERENNIALPAYLOAD)

        # Less likely to switch if FEAR
        stayInRating += 30 if battler.ownersPolicies.include?(:FEAR) && battler.level <= 10
        
        # More likely to switch if weather setter in policy
        weatherSwitchInfo = [
            [:SUN_TEAM, @battle.sunny?, :DROUGHT, :HEATROCK],
            [:RAIN_TEAM, @battle.rainy?, :DRIZZLE, :DAMPROCK],
            [:SANDSTORM_TEAM, @battle.sandy?, :SANDSTREAM, :SMOOTHROCK],
            [:HAIL_TEAM, @battle.icy?, :SNOWWARNING, :ICYROCK],
            [:MOONGLOW_TEAM, @battle.moonGlowing?, :MOONGAZE, :MIRROREDROCK],
            [:ECLIPSE_TEAM, @battle.eclipsed?, :HARBINGER, :PINPOINTROCK],
        ]
        weatherSwitchInfo.each do |weatherSwitchEntry|
            weatherPolicy = weatherSwitchEntry[0]
            weatherActive = weatherSwitchEntry[1]
            weatherAbility = weatherSwitchEntry[2]
            weatherItem = weatherSwitchEntry[3]
            if battler.ownersPolicies.include?(weatherPolicy)
                if weatherActive
                    if battler.hasActiveAbilityAI?(weatherAbility) || battler.hasItem?(weatherItem)
                    stayInRating -= 13 
                    PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) wants to switch to preserve its weather (-13)")
                    end
                elsif battler.hasActiveAbilityAI?(weatherAbility)
                    stayInRating -= 20
                    PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) wants to switch so it can reset the weather (-20)")
                end
            end
        end
        
        # Less likely to switch if has stat boosts
        unless battler.hasActiveAbilityAI?(:DOWNLOAD) || battler.hasActiveAbilityAI?(:SELECTIVESCUTES) # This should be a more complicated check but prob not worth time
            stayInSteps = statStepsValueScore(battler) * 0.06
            stayInSteps = stayInSteps.round
            if stayInSteps > 0
                stayInRating += stayInSteps
                PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) wants to keep its stat steps (#{stayInSteps.to_change})")
            end
        end
        return stayInRating
    end

    # Less likely to be preserved if needs to "use" HP for turns, and has low HP
    def speedTierRating(battler)
        stayInRating = 0
        if battler.hp <= battler.totalhp * 0.5
            sTier = battler.getSpeedTier
            if sTier == 2
                PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is bloodied and FAST, no penalty")
                return stayInRating
            else
                currentHP = battler.hp.to_f
                currentHP += battler.totalhp * 0.25 if battler.hasActiveAbilityAI?(:REGENERATOR) || battler.hasActiveAbilityAI?(:HOLIDAYCHEER)
                currentHP += battler.totalhp * 0.1 if battler.hasTribeBonus?(:CARETAKER)
                currentHP += battler.totalhp * ENTRY_LOWEST_HEALING_ABILITY_FRACTION if battler.hasActiveAbilityAI?(:REFRESHMENTS) && battler.ownersPolicies.include?(:SUN_TEAM)
                currentHP += battler.totalhp * ENTRY_LOWEST_HEALING_ABILITY_FRACTION if battler.hasActiveAbilityAI?(:TOLLTHEBELLS) && battler.ownersPolicies.include?(:ECLIPSE_TEAM)
                if currentHP > battler.totalhp * 0.5
                    PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is bloodied but will regenerate, no penalty")
                    return stayInRating
                end
                currentHP /= battler.totalhp * 0.6 # .6 instead of .5 is intentional to bias score
                if sTier == 1
                    stayInRating += 23
                    stayInRating -= 23 * currentHP
                    PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is bloodied and AVERAGE (+#{stayInRating.round})")
                    return stayInRating.round
                else
                    stayInRating += 42
                    stayInRating -= 42 * currentHP
                    PBDebug.log("[STAY-IN RATING] #{battler.pbThis} (#{battler.index}) is bloodied and SLOW (+#{stayInRating.round})")
                    return stayInRating.round
                end
            end    
        end
        return stayInRating
    end

    def pbDefaultChooseNewEnemy(idxBattler, safeSwitch = false)
        urgency = 0
        list = pbGetPartyWithSwapRatings(idxBattler, safeSwitch,urgency)
        list.delete_if { |val| !@battle.pbCanSwitchLax?(idxBattler, val[0]) }
        # An avatar/boss Pokemon's PRESERVE_LAST_POKEMON score (-50 in
        # getSwitchRatingForPartyMember) is only a soft nudge -- if every
        # other living Pokemon scores even worse (bad matchups), the AI can
        # still pick it early. In doubles that's harmless (the other active
        # slot keeps the side going), which is why pbCanSwitch? deliberately
        # leaves a fainted boss/avatar occupying its slot forever once sent
        # out. Singles has no second slot to fall back on, so once that one
        # slot is stuck on a fainted avatar, the side can never field anyone
        # else again -- forbid sending an avatar out early there. Scoped to
        # boss Pokemon specifically, not PRESERVE_LAST_POKEMON generally,
        # since that policy has other, non-avatar uses in singles that should
        # keep their existing soft-preference behavior.
        if @battle.singleBattle? && list.length > 1
            party = @battle.pbParty(idxBattler)
            nonAvatar = list.reject { |val| party[val[0]]&.boss? }
            list = nonAvatar unless nonAvatar.empty?
        end
        if list.length != 0
            listSwapOutCandidates(@battle.battlers[idxBattler], list)
            return list[0][0]
        end
        return -1
    end

    def listSwapOutCandidates(battler, list)
        PBDebug.log("[AI] #{battler.pbThis} (#{battler.index}) swap out candidates are:")
        list.each do |listEntry|
            enemyTrainer = @battle.pbGetOwnerFromBattlerIndex(battler.index)
            allyPokemon = enemyTrainer.party[listEntry[0]]
            next if allyPokemon.nil?
            PBDebug.log("#{allyPokemon.name || "Party member #{listEntry[0]}"}: #{listEntry[1]}")
        end
    end

    # Set to true while calibrating FUTILITY_MARGIN: computes the real score
    # for every candidate regardless of the cheap estimate, logs
    # (estimate, real) pairs to Analysis/futility_validation.txt instead of
    # actually pruning anything. Flip to false (and remove the logging
    # once satisfied) for the real speedup.
    FUTILITY_PRUNING_VALIDATE = false
    # How far below the cutoff the cheap estimate has to fall before a
    # candidate is skipped outright -- covers what estimateSwitchScoreCeiling
    # deliberately leaves out (hazards, switch-in abilities, misc
    # modifiers). Calibrated via FUTILITY_PRUNING_VALIDATE against 1,304
    # candidate evaluations across 12 battles (6 random pairings + 6 picked
    # for closely-matched ratings, since lopsided matchups rarely exercise
    # the switch-or-stay decision closely enough to stress this): margin 40
    # had exactly 1 miss (a pruned candidate whose real score would have
    # actually cleared the threshold), margin 60 had zero -- a real drop-off
    # rather than a borderline zero, which is the basis for trusting 60
    # specifically rather than just picking the smallest zero-miss value
    # seen. Re-run that validation pass if this ever needs revisiting.
    FUTILITY_MARGIN = 60

    # Rates every other Pokemon in the trainer's party and returns a sorted list of the indices and swap in rating
    def pbGetPartyWithSwapRatings(idxBattler, safeSwitch = false, urgency, futilityThreshold: nil)
        list = []
        battlerSlot = @battle.battlers[idxBattler]

        @battle.pbParty(idxBattler).each_with_index do |pkmn, partyIndex|
            next unless pkmn
            next unless pkmn.able?(false, @battle.getAbleParametersByBattlerIndex(partyIndex, idxBattler))
            next if battlerSlot.pokemonIndex == partyIndex
            next unless @battle.pbCanSwitch?(idxBattler, partyIndex)

            estimate = (futilityThreshold && !safeSwitch) ? estimateSwitchScoreCeiling(pkmn, battlerSlot, urgency) : nil

            if FUTILITY_PRUNING_VALIDATE
                realScore = getSwitchRatingForPartyMember(pkmn, partyIndex, battlerSlot, safeSwitch, urgency)
                if estimate
                    File.open("Analysis/futility_validation.txt", "a") do |f|
                        f.puts("#{pkmn.species}\t#{estimate}\t#{realScore}\t#{futilityThreshold}\t#{urgency}")
                    end
                end
                list.push([partyIndex, realScore])
                next
            end

            if estimate && estimate + FUTILITY_MARGIN < futilityThreshold
                next # Cheap estimate has no realistic chance of clearing the bar -- skip the full simulation.
            end

            switchScore = getSwitchRatingForPartyMember(pkmn, partyIndex, battlerSlot, safeSwitch, urgency)
            list.push([partyIndex, switchScore])
        end
        list.sort_by! { |entry| entry[1].nil? ? 99_999 : -entry[1] }
        return list
    end

    def getSwitchRatingForPartyMember(pkmn, partyIndex, battlerSlot, safeSwitch = false,urgency)
        # For preserving the pokemon placed in the last slot -- exact, not a
        # heuristic: this policy unconditionally overwrites switchScore to
        # -50 regardless of everything else computed below, so skip the
        # simulation entirely rather than throwing its result away.
        if battlerSlot.ownersPolicies.include?(:PRESERVE_LAST_POKEMON) && partyIndex == @battle.pbParty(battlerSlot.index).length - 1
            echoln("[SWITCH SCORING] #{pkmn.name} should be preserved by policy (-50)")
            return -50
        end

        switchScore = 0

        # Create a battler to simulate what would happen if the Pokemon was in battle right now
        fakeBattler = PokeBattle_Battler.new(@battle, battlerSlot.index, true)
        fakeBattler.pbInitializeFake(pkmn, partyIndex)

        # Account for hazards
        hazardSwitchScore, entryDamageTaken, dieingOnEntry = getHazardEvaluationForEnteringBattler(fakeBattler)
        switchScore += hazardSwitchScore

        # Track the damage taken
        fakeBattler.hp -= entryDamageTaken

        # More want to swap if has a entry ability that matters
        # Intentionally checked even if the pokemon will die on entry
        switchScore += getEntryAbilityEvaluationForEnteringBattler(fakeBattler, dieingOnEntry)
        switchScore += getAlliesAbilityEvaluationForEnteringBattler(fakeBattler, dieingOnEntry)

        if safeSwitch
            echoln("[SWITCH SCORING] Evaluating #{fakeBattler.pbThis} as a SAFE switch")
        else
            echoln("[SWITCH SCORING] Evaluating #{fakeBattler.pbThis} as a UN-SAFE switch")
        end

        # Only matters if the pokemon will live
        unless dieingOnEntry
            # Find the worst matchup against the current player battlers
            defensiveMatchupRating, killInfoArray = worstDefensiveMatchupAgainstActiveFoes(fakeBattler)
            if safeSwitch
                defensiveMatchupRating = (0.5 * defensiveMatchupRating).floor
            else
                defensiveMatchupRating = (0.75 * defensiveMatchupRating).floor
            end
            switchScore += defensiveMatchupRating
            if killInfoArray.empty?
                echoln("[SWITCH SCORING] #{fakeBattler.pbThis} defensive matchup rating: #{defensiveMatchupRating.to_change} (doesn't think it can be fainted)")
            else
                echoln("[SWITCH SCORING] #{fakeBattler.pbThis} defensive matchup rating: #{defensiveMatchupRating.to_change} (thinks can be fainted!)")
            end

            offensiveMatchupRating, killInfo = switchRatingBestMoveScore(fakeBattler, killInfoArray: killInfoArray)
            if safeSwitch
                offensiveMatchupRating = (0.5 * offensiveMatchupRating).floor unless urgency >= 20
            else
                offensiveMatchupRating = (0.25 * offensiveMatchupRating).floor unless urgency >= 20
            end
            offensiveMatchupRating -= urgency * 0.5 if offensiveMatchupRating <= 0
            offensiveMatchupRating = offensiveMatchupRating.floor
            switchScore += offensiveMatchupRating
            if killInfo
                echoln("[SWITCH SCORING] #{fakeBattler.pbThis} offensive matchup rating: #{offensiveMatchupRating.to_change} (thinks can faint a foe!)")
            else
                echoln("[SWITCH SCORING] #{fakeBattler.pbThis} offensive matchup rating: #{offensiveMatchupRating.to_change} (doesn't think it can faint anyone)")
            end
        end

        # Focus sash Endeavor quick Attack Rattata
        if battlerSlot.ownersPolicies.include?(:FEAR)
            if safeSwitch && fakeBattler.level <= 10
                canEndeavor = false
                fakeBattler.eachOpposing do |b|
                    next if b.pbHasType?(:GHOST)
                    canEndeavor = true
                switchScore += 30 if canEndeavor
                end
            end
        end

        return switchScore
    end

    # Coarse, type-effectiveness-only ceiling per move-scoring tier (see
    # pbGetMoveScoreDamage's 50/100/150/200/250 bands) -- generously rounded
    # up within each type-modifier bracket, not the real percentage-damage
    # formula. Every dual-type combination's effectiveness multiplies out to
    # one of these six values, so this covers all of them.
    TYPE_MOD_TO_MOVE_SCORE_CEILING = {
        0.0 => 20, 0.25 => 90, 0.5 => 130, 1.0 => 200, 2.0 => 250, 4.0 => 250,
    }.freeze

    # Cheap, type-effectiveness-only stand-in for getSwitchRatingForPartyMember,
    # used to decide whether that full (expensive) simulation -- which builds
    # a fake battler and runs complete move-scoring -- is worth running at
    # all for this candidate. The same idea as a chess engine's futility
    # pruning: a fast, approximate evaluation good enough to prove a branch
    # isn't worth exploring further, not a mathematically guaranteed bound.
    # Deliberately ignores hazards, switch-in abilities, and
    # getSwitchRatingForPartyMember's misc modifiers; FUTILITY_MARGIN (see
    # pbGetPartyWithSwapRatings) is calibrated to cover that gap empirically
    # (see FUTILITY_PRUNING_VALIDATE) rather than derived exactly -- there's
    # no practical way to derive it exactly, since damageScore's
    # contributors are scattered across dozens of independent ability/item/
    # move-effect handlers with no shared ceiling.
    #
    # Returns nil ("can't estimate safely, don't prune") when urgency
    # relaxes getSwitchRatingForPartyMember's own scale-down, since this
    # doesn't attempt to mirror that adjustment, or when there's no
    # opposing/own typing to compare.
    def estimateSwitchScoreCeiling(pkmn, battlerSlot, urgency)
        return nil if urgency >= 20

        foeTypes = []
        battlerSlot.eachOpposing(true) { |foe| foeTypes.concat(foe.pbTypes(true)) }
        foeTypes.uniq!
        return nil if foeTypes.empty?

        pkmnTypes = [pkmn.type1, pkmn.type2].compact.uniq
        return nil if pkmnTypes.empty?

        # Best case for the candidate's own offense: its best known move
        # type against the foe's typing.
        bestOffenseMod = 0.0
        pkmn.moves.each do |move|
            moveType = GameData::Move.get(move.id).type
            next unless moveType
            mod = Effectiveness.calculate(moveType, foeTypes)
            bestOffenseMod = mod if mod > bestOffenseMod
        end

        # Worst case for the candidate's defense: the foe's best type
        # against it (using the foe's own typing as a stand-in for "whatever
        # STAB move it's likely to have" -- cheaper than enumerating the
        # foe's actual moveset, and a reasonable proxy since most attackers
        # carry STAB).
        worstDefenseMod = 0.0
        foeTypes.each do |t|
            mod = Effectiveness.calculate(t, pkmnTypes)
            worstDefenseMod = mod if mod > worstDefenseMod
        end

        offenseScoreEstimate = TYPE_MOD_TO_MOVE_SCORE_CEILING[bestOffenseMod] || 250
        defenseScoreEstimate = TYPE_MOD_TO_MOVE_SCORE_CEILING[worstDefenseMod] || 250

        # Mirrors getSwitchRatingForPartyMember's own scaling for the
        # non-safe-switch (pbDetermineSwitch) path -- keep in sync if that
        # changes. The defensive side isn't a plain negation of
        # defenseScoreEstimate: worstDefensiveMatchupAgainstActiveFoes gets
        # its number from switchRatingBestMoveScore too (just called with
        # the foe as the attacker), so it goes through the *same*
        # -40 + score/2.5 bias-and-scale before rateDefensiveMatchup negates
        # it -- skipping that step here was the bug that first made this
        # estimator wildly too pessimistic (caught by FUTILITY_PRUNING_VALIDATE).
        offensiveBiased = -40 + offenseScoreEstimate / EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO
        defensiveBiased = -40 + defenseScoreEstimate / EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO

        offensiveEstimate = (0.25 * offensiveBiased).floor
        defensiveEstimate = (0.75 * -defensiveBiased).floor

        offensiveEstimate + defensiveEstimate
    end

    def getHazardEvaluationForEnteringBattler(battler)
        # Calculate how much damage the pokemon is likely to take from entry hazards
        entryDamage, hazardScore = @battle.applyHazards(battler, true)

        dieingOnEntry = false

        # Try not to swap in pokemon who will die to entry hazard damage
        if battler.hp <= entryDamage
            hazardScore -= 40
            dieingOnEntry = true
            entryDamage = battler.hp
            echoln("[SWITCH SCORING] #{battler.pbThis} will die from hazards! (-40)")
        elsif entryDamage > 0
            percentDamage = (entryDamage / battler.totalhp.to_f)
            hazardDamageSwitchMalus = -(percentDamage * 10).floor
            hazardScore += hazardDamageSwitchMalus
            percentDamageDisplay = (100 * percentDamage).round(1)
            echoln("[SWITCH SCORING] #{battler.pbThis} will take #{percentDamageDisplay} percent HP damage from hazards (#{hazardDamageSwitchMalus.to_change})")
        end

        return hazardScore, entryDamage, dieingOnEntry
    end

    def getEntryAbilityEvaluationForEnteringBattler(battler, _dieingOnEntry)
        totalAbilityScore = 0
        battler.eachActiveAbility do |abilityID|
            switchAbilityEffectScore = BattleHandlers.triggerAbilityOnSwitchIn(abilityID, battler, @battle, true)
            abilitySwitchModifier = (switchAbilityEffectScore / PokeBattle_AI::EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO).ceil
            totalAbilityScore += abilitySwitchModifier
            echoln("[SWITCH SCORING] #{battler.pbThis} values the effect of #{abilityID} as #{switchAbilityEffectScore} (#{abilitySwitchModifier.to_change})")
        end
        return totalAbilityScore
    end

    def getAlliesAbilityEvaluationForEnteringBattler(battler, _dieingOnEntry)
        totalAbilityScore = 0
        battler.eachAlly do |ally|
            ally.eachActiveAbility do |ability|
                switchAbilityEffectScore = BattleHandlers.triggerAbilityOnAllySwitchIn(ability, battler, ally, battler.battle, true)
                abilitySwitchModifier = (switchAbilityEffectScore / PokeBattle_AI::EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO).ceil
                totalAbilityScore += abilitySwitchModifier
            end
        end
        return totalAbilityScore
    end

    # The battler passed in could be a real battler, or a fake one
    def worstDefensiveMatchupAgainstActiveFoes(battler)
        matchups = []
        killInfoArray = []
        battler.eachOpposing(true) do |opposingBattler|
            scoringKey = [battler.personalID, opposingBattler.personalID]
            if @precalculatedDefensiveMatchup.key?(scoringKey)
                matchup, killInfo = @precalculatedDefensiveMatchup[scoringKey]
            else
                matchup, killInfo = rateDefensiveMatchup(battler, opposingBattler)
                @precalculatedDefensiveMatchup[scoringKey] = [matchup, killInfo]
            end
            matchups.push(matchup)
            killInfoArray.push(killInfo) if killInfo
        end
        if matchups.empty?
            worstDefensiveMatchup = 0
        else
            worstDefensiveMatchup = matchups.min
        end
        return worstDefensiveMatchup, killInfoArray
    end

    # The battler passed in could be a real battler, or a fake one
    def rateDefensiveMatchup(battler, opposingBattler)
        # How good are the opponent's moves against me?
        bestMoveScore, killInfo = switchRatingBestMoveScore(opposingBattler, opposingBattler: battler)
        matchupScore = -1 * bestMoveScore

        # Set-up counterplay scoring
        if      (battler.hasActiveItemAI?(:REDCARD) && opposingBattler.activatesTargetItem?(true)) ||
                battler.hasActiveAbilityAI?(GameData::Ability.getByFlag("SetupCounterAI"))
            matchupScore += statStepsValueScore(opposingBattler) * 0.15
        end

        # Value of stalling > DISABLED < 
        #matchupScore += passingTurnBattlerEffectScore(battler, @battle)

        # Fear of unknown
        matchupScore -= opposingBattler.unknownMovesCountAI * 2

        return matchupScore, killInfo
    end

    EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO = 2.5

    def switchRatingBestMoveScore(battler, opposingBattler: nil, killInfoArray: [])
        maxScore, killInfo = highestMoveScoreForBattler(battler, opposingBattler: opposingBattler, killInfoArray: killInfoArray)
        maxMoveScoreBiasChange = -40
        maxMoveScoreBiasChange += (maxScore / EFFECT_SCORE_TO_SWITCH_SCORE_CONVERSION_RATIO).round
        return maxMoveScoreBiasChange, killInfo
    end

    def highestMoveScoreForBattler(battler, opposingBattler: nil, killInfoArray: [])
        if battler.pbOwnedByPlayer?
            maxScore, bestMove, killInfo = pbScorePredictedPlayerMoves(battler, opposingBattler: opposingBattler, killInfoArray: killInfoArray)
        else
            choices, killInfo = pbGetBestTrainerMoveChoices(battler, opposingBattler: opposingBattler, killInfoArray: killInfoArray)
            maxScore = 0
            bestMove = nil
            choices.each do |c|
                next unless c[1] > maxScore
                maxScore = c[1]
                bestMove = battler.getMoves[c[0]]&.id
            end
        end
        if opposingBattler
            echoln("[MOVES SCORING] #{battler.pbThis}'s best move against target #{opposingBattler.pbThis(true)} is #{bestMove} at score #{maxScore}")
        else
            echoln("[MOVES SCORING] #{battler.pbThis}'s best move is #{bestMove} at score #{maxScore}")
        end
        return maxScore, killInfo
    end
end

# Battle-side support for fusions with species-specific form-change mechanics.
#
# ── 1. countsAs? ──────────────────────────────────────────────────────────────
# Any move/ability that gates on a species via countsAs? (Light That Burns The
# Sky, Genotheosis, Transcendent Energy, Techno Blast, etc.) automatically works
# for fusions once the battler returns true for a matching component.
#
# ── 2. pbAttackPhasePurestLight ───────────────────────────────────────────────
# Decodes the Necrozma component's form for Ultra Burst in a fusion.
#
# ── 3. PokeBattle_RealBattlePeer ──────────────────────────────────────────────
# MultipleForms handlers are keyed by species ID, so they never fire for fusion
# species.  Intercept pbOnEnteringBattle and pbOnLeavingBattle to call each
# component's handler directly, then re-encode the result into the fusion form.
# HP is temporarily synced to the fusion's HP so fainted? checks inside handlers
# (Necrozma, Mimikyu, Mega species…) work correctly.
#
# ── 4. pbCheckForm ────────────────────────────────────────────────────────────
# Ability-triggered form changes (Zen Mode, Shields Down, Schooling, Power
# Construct) check isSpecies? and would silently no-op for fusions.  Override to
# detect the matching component and apply the form change on that axis only.
#
# ── 5. pbCheckFormOnWeatherChange ─────────────────────────────────────────────
# Same pattern for weather-based changes (Castform Forecast, Cherrim Flower Gift).
#
# ── 6. pbCheckFormOnMovesetChange ─────────────────────────────────────────────
# Keldeo resolute form when Secret Sword is in the moveset.
#
# ── 7. pbUseMove — Stance Change ─────────────────────────────────────────────
# Aegislash Stance Change is inline in pbUseMove; intercept to apply correctly
# on the Aegislash component axis.
#
# ── 8. Move-class overrides ───────────────────────────────────────────────────
# Meloetta (Relic Song), Mewtwo (Genotheosis), Ampharos (Transcendent Energy).
# countsAs? handles the species check; additionally fix the form-value check and
# pbChangeForm call to use encoded fusion forms.
#
# ── 9. Damage-calc item overrides ─────────────────────────────────────────────
# Adamant Orb, Lustrous Orb, Griseous Orb: replace isSpecies? with countsAs?.

# ── Shared battler helper ─────────────────────────────────────────────────────
# Given a species and a desired component form, compute and return the full
# encoded fusion form (or nil if this battler is not a fusion with a matching
# component, or the form would not change).
class PokeBattle_Battler
    def pbFusionComponentEncodedForm(species, new_comp_form)
        return nil unless @pokemon&.fused_species?
        num_sf = GameData::FusedSpecies.count_forms(@pokemon.fusion_secondary.species)
        [:primary, :secondary].each do |axis|
            component = axis == :primary ? @pokemon.fusion_primary : @pokemon.fusion_secondary
            next unless component&.isSpecies?(species)
            curr_pf  = @form / num_sf
            curr_sf  = @form % num_sf
            new_form = axis == :primary ? new_comp_form * num_sf + curr_sf : curr_pf * num_sf + new_comp_form
            return nil if @form == new_form
            return new_form
        end
        nil
    end

    # Returns the decoded form of the first fusion component matching +species+,
    # or nil.  Useful when a move/ability needs to check the component's form.
    def pbFusionComponentForm(species)
        return nil unless @pokemon&.fused_species?
        num_sf = GameData::FusedSpecies.count_forms(@pokemon.fusion_secondary.species)
        [:primary, :secondary].each do |axis|
            component = axis == :primary ? @pokemon.fusion_primary : @pokemon.fusion_secondary
            next unless component&.isSpecies?(species)
            return axis == :primary ? @form / num_sf : @form % num_sf
        end
        nil
    end
end

# ── 1. countsAs? ──────────────────────────────────────────────────────────────

class PokeBattle_Battler
    unless method_defined?(:_countsAs_without_fusions)
        alias_method :_countsAs_without_fusions, :countsAs?
    end
    def countsAs?(species)
        return true if _countsAs_without_fusions(species)
        if @pokemon&.fused_species?
            return true if @pokemon.fusion_primary&.isSpecies?(species)
            return true if @pokemon.fusion_secondary&.isSpecies?(species)
        end
        false
    end
end

# ── 2. pbAttackPhasePurestLight ───────────────────────────────────────────────

class PokeBattle_Battle
    unless method_defined?(:_pbAttackPhasePurestLight_without_fusions)
        alias_method :_pbAttackPhasePurestLight_without_fusions, :pbAttackPhasePurestLight
    end
    def pbAttackPhasePurestLight
        pbPriority.each do |b|
            next unless @choices[b.index][0] == :UseMove && !b.fainted?
            next if b.asleep? && b.statusCount > 1
            next if b.movedThisRound?
            next unless b.hasActiveAbility?(:PURESTLIGHT)
            move = @choices[b.index][2]
            next if move.callsAnotherMove?
            next unless move.id == :LIGHTTHATBURNSTHESKY
            next unless b.pokemon&.fused_species?

            necrozma_axis = nil
            if b.pokemon.fusion_primary&.isSpecies?(:NECROZMA)
                necrozma_axis = :primary
            elsif b.pokemon.fusion_secondary&.isSpecies?(:NECROZMA)
                necrozma_axis = :secondary
            end
            next unless necrozma_axis

            num_sf        = GameData::FusedSpecies.count_forms(b.pokemon.fusion_secondary.species)
            curr_pf       = b.form / num_sf
            curr_sf       = b.form % num_sf
            necrozma_form = (necrozma_axis == :primary) ? curr_pf : curr_sf

            ultra_form = case necrozma_form
                         when 1 then 3   # Dusk Mane  → Ultra (Dusk Mane)
                         when 2 then 4   # Dawn Wings → Ultra (Dawn Wings)
                         else nil
                         end
            next unless ultra_form

            new_form = (necrozma_axis == :primary) \
                       ? ultra_form * num_sf + curr_sf \
                       : curr_pf   * num_sf + ultra_form
            next if b.form == new_form

            @scene.pbCommonAnimation("UltraBurst", b)
            b.pbChangeForm(new_form, _INTL("Bright light bursts out of {1}!", b.pbThis))
        end
        _pbAttackPhasePurestLight_without_fusions
    end
end

# ── 3. PokeBattle_RealBattlePeer — entering/leaving battle ───────────────────
#
# For each component of a fusion, call that component's MultipleForms handler
# directly.  Temporarily sync the component's HP to the fusion's HP so that
# fainted? checks inside handlers (Necrozma, Mimikyu, Mega species, etc.) use
# the correct value.

class PokeBattle_RealBattlePeer
    unless method_defined?(:_pbOnEnteringBattle_without_fusions)
        alias_method :_pbOnEnteringBattle_without_fusions, :pbOnEnteringBattle
    end
    def pbOnEnteringBattle(battle, pkmn, wild = false)
        if pkmn&.fused_species?
            num_sf = GameData::FusedSpecies.count_forms(pkmn.fusion_secondary.species)
            [:primary, :secondary].each do |axis|
                component = axis == :primary ? pkmn.fusion_primary : pkmn.fusion_secondary
                next unless component
                new_comp = MultipleForms.call("getFormOnEnteringBattle", component, wild)
                next if new_comp.nil?
                curr_pf   = pkmn.form / num_sf
                curr_sf   = pkmn.form % num_sf
                comp_form = axis == :primary ? curr_pf : curr_sf
                next if comp_form == new_comp
                pkmn.form = axis == :primary \
                            ? new_comp * num_sf + curr_sf \
                            : curr_pf  * num_sf + new_comp
            end
        end
        _pbOnEnteringBattle_without_fusions(battle, pkmn, wild)
    end

    unless method_defined?(:_pbOnLeavingBattle_without_fusions)
        alias_method :_pbOnLeavingBattle_without_fusions, :pbOnLeavingBattle
    end
    def pbOnLeavingBattle(battle, pkmn, usedInBattle, endBattle = false)
        if pkmn&.fused_species?
            num_sf = GameData::FusedSpecies.count_forms(pkmn.fusion_secondary.species)
            [:primary, :secondary].each do |axis|
                component = axis == :primary ? pkmn.fusion_primary : pkmn.fusion_secondary
                next unless component
                # Sync HP so that pkmn.fainted? inside handlers returns the correct value.
                orig_hp      = component.hp
                component.hp = pkmn.hp
                new_comp = MultipleForms.call("getFormOnLeavingBattle", component, battle, usedInBattle, endBattle)
                component.hp = orig_hp
                next if new_comp.nil?
                curr_pf   = pkmn.form / num_sf
                curr_sf   = pkmn.form % num_sf
                comp_form = axis == :primary ? curr_pf : curr_sf
                next if comp_form == new_comp
                pkmn.form = axis == :primary \
                            ? new_comp * num_sf + curr_sf \
                            : curr_pf  * num_sf + new_comp
            end
        end
        _pbOnLeavingBattle_without_fusions(battle, pkmn, usedInBattle, endBattle)
    end
end

# ── 4. pbCheckForm — ability-triggered form changes ───────────────────────────
#
# Darmanitan (Zen Mode), Minior (Shields Down), Wishiwashi (Schooling),
# Zygarde (Power Construct).  The original isSpecies? checks all fail for
# fusions; we run fusion-aware checks first, then let the original run (its
# checks are no-ops for fusions).

class PokeBattle_Battler
    unless method_defined?(:_pbCheckForm_without_fusions)
        alias_method :_pbCheckForm_without_fusions, :pbCheckForm
    end
    def pbCheckForm(endOfRound = false)
        if @pokemon&.fused_species?
            return if fainted? || effectActive?(:Transform)
            num_sf = GameData::FusedSpecies.count_forms(@pokemon.fusion_secondary.species)
            [:primary, :secondary].each do |axis|
                component = axis == :primary ? @pokemon.fusion_primary : @pokemon.fusion_secondary
                next unless component
                curr_pf   = @form / num_sf
                curr_sf   = @form % num_sf
                comp_form = axis == :primary ? curr_pf : curr_sf

                new_comp = nil
                msg      = nil

                # Darmanitan — Zen Mode
                if component.isSpecies?(:DARMANITAN) && hasAbility?(:ZENMODE)
                    expected = @hp <= @totalhp / 2 ? 1 : 0
                    if comp_form != expected
                        showMyAbilitySplash(:ZENMODE, true)
                        hideMyAbilitySplash
                        new_comp = expected
                        msg      = _INTL("{1} triggered!", getAbilityName(:ZENMODE))
                    end
                end

                # Minior — Shields Down
                if component.isSpecies?(:MINIOR) && hasAbility?(:SHIELDSDOWN)
                    expected = aboveHalfHealth? ? comp_form % 7 : (comp_form % 7) + 7
                    if comp_form != expected
                        showMyAbilitySplash(:SHIELDSDOWN, true)
                        hideMyAbilitySplash
                        animation = aboveHalfHealth? ? "ShieldsUp" : "ShieldsDown"
                        @battle.pbCommonAnimation(animation, self)
                        new_comp = expected
                        msg      = _INTL("{1} #{aboveHalfHealth? ? 'deactivated' : 'activated'}!",
                                         getAbilityName(:SHIELDSDOWN))
                    end
                end

                # Wishiwashi — Schooling
                if component.isSpecies?(:WISHIWASHI) && hasAbility?(:SCHOOLING)
                    expected = (@level >= 20 && @hp > @totalhp / 4) ? 1 : 0
                    if comp_form != expected
                        showMyAbilitySplash(:SCHOOLING, true)
                        hideMyAbilitySplash
                        @battle.pbCommonAnimation("SchoolForm", self)
                        new_comp = expected
                        msg      = expected == 1 \
                                   ? _INTL("{1} formed a school!", pbThis) \
                                   : _INTL("{1} stopped schooling!", pbThis)
                    end
                end

                # Zygarde — Power Construct (end-of-round only)
                if component.isSpecies?(:ZYGARDE) && hasAbility?(:POWERCONSTRUCT) &&
                   endOfRound && @hp <= @totalhp / 2 && comp_form <= 1
                    @battle.pbDisplay(_INTL("You sense the presence of many!"))
                    showMyAbilitySplash(:POWERCONSTRUCT, true)
                    hideMyAbilitySplash
                    @battle.pbCommonAnimation("ZygardeForms", self)
                    new_comp = comp_form + 2
                    msg      = _INTL("{1} transformed into its Complete Forme!", pbThis)
                end

                if new_comp
                    new_form = axis == :primary \
                               ? new_comp * num_sf + curr_sf \
                               : curr_pf  * num_sf + new_comp
                    pbChangeForm(new_form, msg)
                end
            end
        end
        _pbCheckForm_without_fusions(endOfRound)
    end
end

# ── 5. pbCheckFormOnWeatherChange — Castform & Cherrim ────────────────────────

class PokeBattle_Battler
    unless method_defined?(:_pbCheckFormOnWeatherChange_without_fusions)
        alias_method :_pbCheckFormOnWeatherChange_without_fusions, :pbCheckFormOnWeatherChange
    end
    def pbCheckFormOnWeatherChange(abilityLossCheck = false)
        if @pokemon&.fused_species?
            return if fainted? || effectActive?(:Transform)
            num_sf = GameData::FusedSpecies.count_forms(@pokemon.fusion_secondary.species)
            [:primary, :secondary].each do |axis|
                component = axis == :primary ? @pokemon.fusion_primary : @pokemon.fusion_secondary
                next unless component
                curr_pf   = @form / num_sf
                curr_sf   = @form % num_sf
                comp_form = axis == :primary ? curr_pf : curr_sf

                # Castform — Forecast
                if component.isSpecies?(:CASTFORM)
                    if hasActiveAbility?(:FORECAST)
                        new_comp = 0
                        case @battle.pbWeather
                        when :Sunshine, :HarshSun   then new_comp = 1
                        when :Rainstorm, :HeavyRain then new_comp = 2
                        when :Hail, :IceAge         then new_comp = 3
                        when :Sandstorm, :StarStorm then new_comp = 4
                        when :Moonglow, :BloodMoon  then new_comp = 5
                        when :Eclipse, :RingEclipse then new_comp = 6
                        end
                        if comp_form != new_comp
                            showMyAbilitySplash(:FORECAST, true)
                            hideMyAbilitySplash
                            @battle.pbCommonAnimation("Forecast", self)
                            new_form = axis == :primary \
                                       ? new_comp * num_sf + curr_sf \
                                       : curr_pf  * num_sf + new_comp
                            pbChangeForm(new_form, _INTL("{1} transformed!", pbThis))
                        end
                    elsif comp_form != 0
                        new_form = axis == :primary \
                                   ? 0 * num_sf + curr_sf \
                                   : curr_pf * num_sf + 0
                        pbChangeForm(new_form, _INTL("{1} transformed!", pbThis))
                    end
                end

                # Cherrim — Flower Gift
                if component.isSpecies?(:CHERRIM)
                    if hasActiveAbility?(:FLOWERGIFT)
                        new_comp = @battle.sunny? ? 1 : 0
                        if comp_form != new_comp
                            showMyAbilitySplash(:FLOWERGIFT, true)
                            hideMyAbilitySplash
                            @battle.pbCommonAnimation("Forecast", self)
                            new_form = axis == :primary \
                                       ? new_comp * num_sf + curr_sf \
                                       : curr_pf  * num_sf + new_comp
                            pbChangeForm(new_form, _INTL("{1} transformed!", pbThis))
                        end
                    elsif comp_form != 0
                        new_form = axis == :primary \
                                   ? 0 * num_sf + curr_sf \
                                   : curr_pf * num_sf + 0
                        pbChangeForm(new_form, _INTL("{1} transformed!", pbThis))
                    end
                end
            end
        end
        _pbCheckFormOnWeatherChange_without_fusions(abilityLossCheck)
    end
end

# ── 6. pbCheckFormOnMovesetChange — Keldeo ────────────────────────────────────

class PokeBattle_Battler
    unless method_defined?(:_pbCheckFormOnMovesetChange_without_fusions)
        alias_method :_pbCheckFormOnMovesetChange_without_fusions, :pbCheckFormOnMovesetChange
    end
    def pbCheckFormOnMovesetChange
        if @pokemon&.fused_species?
            return if fainted? || effectActive?(:Transform)
            num_sf = GameData::FusedSpecies.count_forms(@pokemon.fusion_secondary.species)
            [:primary, :secondary].each do |axis|
                component = axis == :primary ? @pokemon.fusion_primary : @pokemon.fusion_secondary
                next unless component&.isSpecies?(:KELDEO)
                curr_pf   = @form / num_sf
                curr_sf   = @form % num_sf
                comp_form = axis == :primary ? curr_pf : curr_sf
                new_comp  = pbHasMove?(:SECRETSWORD) ? 1 : 0
                next if comp_form == new_comp
                new_form = axis == :primary \
                           ? new_comp * num_sf + curr_sf \
                           : curr_pf  * num_sf + new_comp
                pbChangeForm(new_form, _INTL("{1} transformed!", pbThis))
                break
            end
        end
        _pbCheckFormOnMovesetChange_without_fusions
    end
end

# ── 7. Stance Change — Aegislash ─────────────────────────────────────────────
#
# The original isSpecies?(:AEGISLASH) check is inline in pbUseMove and would
# fail for a fusion.  Add a fusion-aware check at the top of pbUseMove that
# fires first; the original check is then a no-op for fusions.

class PokeBattle_Battler
    unless method_defined?(:_pbUseMove_without_fusions)
        alias_method :_pbUseMove_without_fusions, :pbUseMove
    end
    def pbUseMove(choice, specialUsage = false)
        if @pokemon&.fused_species? && hasAbility?(:STANCECHANGE)
            move = choice[2]
            if move&.damagingMove?
                new_form = pbFusionComponentEncodedForm(:AEGISLASH, 1)
                if new_form
                    @battle.pbCommonAnimation("StanceAttack", self)
                    pbChangeForm(new_form, _INTL("{1} changed to Blade Forme!", pbThis))
                end
            elsif move&.id == :KINGSSHIELD
                new_form = pbFusionComponentEncodedForm(:AEGISLASH, 0)
                if new_form
                    @battle.pbCommonAnimation("StanceProtect", self)
                    pbChangeForm(new_form, _INTL("{1} changed to Shield Forme!", pbThis))
                end
            end
        end
        _pbUseMove_without_fusions(choice, specialUsage)
    end
end

# ── 8. Move-class overrides ───────────────────────────────────────────────────

# Relic Song (Meloetta) — the original pbEndOfMoveUsageEffect checks
# user.isSpecies?(:MELOETTA).  Override to also handle fusion components.
class PokeBattle_Move_ChangeUserMeloettaForm
    unless method_defined?(:_pbEndOfMoveUsageEffect_without_fusions)
        alias_method :_pbEndOfMoveUsageEffect_without_fusions, :pbEndOfMoveUsageEffect
    end
    def pbEndOfMoveUsageEffect(user, targets, numHits, switchedBattlers)
        if user.pokemon&.fused_species?
            return if numHits == 0 || user.fainted? || user.transformed?
            return if user.hasActiveAbility?(:SHEERFORCE)
            num_sf = GameData::FusedSpecies.count_forms(user.pokemon.fusion_secondary.species)
            [:primary, :secondary].each do |axis|
                component = axis == :primary ? user.pokemon.fusion_primary : user.pokemon.fusion_secondary
                next unless component&.isSpecies?(:MELOETTA)
                curr_pf   = user.form / num_sf
                curr_sf   = user.form % num_sf
                comp_form = axis == :primary ? curr_pf : curr_sf
                new_comp  = (comp_form + 1) % 2
                new_form  = axis == :primary \
                            ? new_comp * num_sf + curr_sf \
                            : curr_pf  * num_sf + new_comp
                user.pbChangeForm(new_form, _INTL("{1} transformed!", user.pbThis))
                return
            end
            return
        end
        _pbEndOfMoveUsageEffect_without_fusions(user, targets, numHits, switchedBattlers)
    end
end

# Genotheosis (Mewtwo) — countsAs?(:MEWTWO) already works via our override.
# Fix the form==0 check (which tests the encoded fusion form, not the Mewtwo
# component's form) and fix pbEffectGeneral to use the encoded target form.
class PokeBattle_Move_ChangeUserMewtwoChoiceOfForm
    unless method_defined?(:_pbMoveFailed_genotheosis_without_fusions)
        alias_method :_pbMoveFailed_genotheosis_without_fusions, :pbMoveFailed?
    end
    def pbMoveFailed?(user, targets, show_message)
        if user.pokemon&.fused_species? && user.countsAs?(:MEWTWO)
            comp_form = user.pbFusionComponentForm(:MEWTWO)
            unless comp_form
                @battle.pbDisplay(_INTL("But {1} can't use the move!", user.pbThis)) if show_message
                return true
            end
            if comp_form != 0
                @battle.pbDisplay(_INTL("But {1} has already transformed!", user.pbThis)) if show_message
                return true
            end
            return false
        end
        _pbMoveFailed_genotheosis_without_fusions(user, targets, show_message)
    end

    unless method_defined?(:_pbCanChooseMove_genotheosis_without_fusions)
        alias_method :_pbCanChooseMove_genotheosis_without_fusions, :pbCanChooseMove?
    end
    def pbCanChooseMove?(user, commandPhase, show_message)
        if user.pokemon&.fused_species? && user.countsAs?(:MEWTWO)
            comp_form = user.pbFusionComponentForm(:MEWTWO) || 0
            if comp_form != 0
                if show_message
                    msg = _INTL("{1} has already transformed!", user.pbThis)
                    commandPhase ? @battle.pbDisplayPaused(msg) : @battle.pbDisplay(msg)
                end
                return false
            end
            return true
        end
        _pbCanChooseMove_genotheosis_without_fusions(user, commandPhase, show_message)
    end

    unless method_defined?(:_pbEffectGeneral_genotheosis_without_fusions)
        alias_method :_pbEffectGeneral_genotheosis_without_fusions, :pbEffectGeneral
    end
    def pbEffectGeneral(user)
        if user.pokemon&.fused_species? && user.countsAs?(:MEWTWO) && @chosenForm
            new_form = user.pbFusionComponentEncodedForm(:MEWTWO, @chosenForm)
            if new_form
                user.pbChangeForm(new_form, _INTL("{1} augmented its genes and transformed!", user.pbThis))
                return
            end
        end
        _pbEffectGeneral_genotheosis_without_fusions(user)
    end
end

# Transcendent Energy (Ampharos) — countsAs?(:AMPHAROS) already works.
# Fix form!=0 check and pbEffectGeneral.
class PokeBattle_Move_TwoTurnChangeUserAmpharosForm
    unless method_defined?(:_pbMoveFailed_transenergy_without_fusions)
        alias_method :_pbMoveFailed_transenergy_without_fusions, :pbMoveFailed?
    end
    def pbMoveFailed?(user, targets, show_message)
        if user.pokemon&.fused_species? && user.countsAs?(:AMPHAROS)
            comp_form = user.pbFusionComponentForm(:AMPHAROS) || 0
            if comp_form != 0
                @battle.pbDisplay(_INTL("But {1} can't use it the way it is now!", user.pbThis(true))) if show_message
                return true
            end
            return false
        end
        _pbMoveFailed_transenergy_without_fusions(user, targets, show_message)
    end

    unless method_defined?(:_pbEffectGeneral_transenergy_without_fusions)
        alias_method :_pbEffectGeneral_transenergy_without_fusions, :pbEffectGeneral
    end
    def pbEffectGeneral(user)
        return unless @damagingTurn
        if user.pokemon&.fused_species? && user.countsAs?(:AMPHAROS)
            new_form = user.pbFusionComponentEncodedForm(:AMPHAROS, 1)
            if new_form
                user.pbChangeForm(new_form, _INTL("{1} transcended its limits and transformed!", user.pbThis))
                return
            end
        end
        _pbEffectGeneral_transenergy_without_fusions(user)
    end
end

# ── 9. Damage-calc item overrides ─────────────────────────────────────────────
# Replace isSpecies? with countsAs? so that fusions holding these orbs while
# containing the corresponding component still receive the damage boost.

BattleHandlers::DamageCalcUserItem.add(:ADAMANTORB,
    proc { |item, user, _target, _move, mults, _baseDmg, type, aiCheck|
        if user.countsAs?(:DIALGA) && %i[DRAGON STEEL].include?(type)
            mults[:base_damage_multiplier] *= 1.2
            user.aiLearnsItem(item) unless aiCheck
        end
    }
)

BattleHandlers::DamageCalcUserItem.add(:LUSTROUSORB,
    proc { |item, user, _target, _move, mults, _baseDmg, type, aiCheck|
        if user.countsAs?(:PALKIA) && %i[DRAGON WATER].include?(type)
            mults[:base_damage_multiplier] *= 1.2
            user.aiLearnsItem(item) unless aiCheck
        end
    }
)

BattleHandlers::DamageCalcUserItem.add(:GRISEOUSORB,
    proc { |item, user, _target, _move, mults, _baseDmg, type, aiCheck|
        if user.countsAs?(:GIRATINA) && %i[DRAGON GHOST].include?(type)
            mults[:base_damage_multiplier] *= 1.2
            user.aiLearnsItem(item) unless aiCheck
        end
    }
)

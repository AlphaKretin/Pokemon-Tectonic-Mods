# Battle-side support for fusions containing Necrozma.
#
# Three patches:
#
# 1. PokeBattle_Battler#countsAs? — Light That Burns The Sky validates its user
#    with user.countsAs?(:NECROZMA).  Override to also return true when the
#    battler is a fusion whose primary or secondary component is Necrozma.
#
# 2. PokeBattle_Battle#pbAttackPhasePurestLight — decodes the fusion's form to
#    find the Necrozma component's actual form (1 = Dusk Mane, 2 = Dawn Wings)
#    and computes the correct encoded Ultra form (3 or 4) to pass to pbChangeForm.
#
# 3. PokeBattle_Battler#pbOnLeavingBattle — the standard MultipleForms
#    "getFormOnLeavingBattle" handler for NECROZMA fires on the party Pokemon.
#    For a fusion, the party Pokemon's species is the fusion ID, so no handler
#    fires and the Necrozma component stays in Ultra form after battle.
#    Override to explicitly revert it.

# ── 1. countsAs? ──────────────────────────────────────────────────────────────

class PokeBattle_Battler
    unless method_defined?(:_countsAs_without_fusions)
        alias_method :_countsAs_without_fusions, :countsAs?
    end
    def countsAs?(species)
        return true if _countsAs_without_fusions(species)
        # For fused battlers, also check the stored component species so that
        # moves/abilities gated on a specific species (e.g. Light That Burns The
        # Sky requiring Necrozma) work correctly.
        if @pokemon&.fused_species?
            return true if @pokemon.fusion_primary&.isSpecies?(species)
            return true if @pokemon.fusion_secondary&.isSpecies?(species)
        end
        return false
    end
end

# ── 2. pbAttackPhasePurestLight ───────────────────────────────────────────────

class PokeBattle_Battle
    unless method_defined?(:_pbAttackPhasePurestLight_without_fusions)
        alias_method :_pbAttackPhasePurestLight_without_fusions, :pbAttackPhasePurestLight
    end
    def pbAttackPhasePurestLight
        # Handle fusion battlers before delegating to the original.
        # The original reads b.form directly expecting 1 (Dusk Mane) or 2 (Dawn
        # Wings), but for a fusion b.form is an encoded value, so it never matches
        # and the Ultra Burst never fires.  We decode the Necrozma component's
        # form here and compute the correct encoded target form.
        pbPriority.each do |b|
            next unless @choices[b.index][0] == :UseMove && !b.fainted?
            next if b.asleep? && b.statusCount > 1
            next if b.movedThisRound?
            next unless b.hasActiveAbility?(:PURESTLIGHT)
            move = @choices[b.index][2]
            next if move.callsAnotherMove?
            next unless move.id == :LIGHTTHATBURNSTHESKY
            next unless b.pokemon&.fused_species?

            # Identify the Necrozma component and which axis it is.
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

# ── 3. pbOnLeavingBattle — Ultra form reversion ───────────────────────────────

class PokeBattle_Battler
    if method_defined?(:pbOnLeavingBattle) && !method_defined?(:_pbOnLeavingBattle_without_fusions)
        alias_method :_pbOnLeavingBattle_without_fusions, :pbOnLeavingBattle
    end
    def pbOnLeavingBattle(battle, usedInBattle, endBattle = false)
        # Revert fusion Necrozma from Ultra form (3 or 4) back to its fused form
        # (1 or 2) when the battle ends or the Pokemon faints.
        # The normal MultipleForms "getFormOnLeavingBattle" handler only fires for
        # the Necrozma species itself; for a fusion the party Pokemon's species is
        # the fusion ID and no handler is registered for it.
        if @pokemon&.fused_species? && (@pokemon.fainted? || endBattle)
            [:primary, :secondary].each do |axis|
                component = (axis == :primary) \
                            ? @pokemon.fusion_primary \
                            : @pokemon.fusion_secondary
                next unless component&.isSpecies?(:NECROZMA) && component.form >= 3

                # form 3 → 1 (Dusk Mane), form 4 → 2 (Dawn Wings)
                new_component_form = component.form - 2
                num_sf  = GameData::FusedSpecies.count_forms(@pokemon.fusion_secondary.species)
                curr_pf = @pokemon.form / num_sf
                curr_sf = @pokemon.form % num_sf
                new_form = (axis == :primary) \
                           ? new_component_form * num_sf + curr_sf \
                           : curr_pf * num_sf + new_component_form
                @pokemon.form = new_form
                pbUpdate(true)
                break
            end
        end
        if respond_to?(:_pbOnLeavingBattle_without_fusions, true)
            _pbOnLeavingBattle_without_fusions(battle, usedInBattle, endBattle)
        end
    end
end

# Fusion-aware overrides for form-changing items.
#
# Three problems solved here:
#
# 1. Universal Formaliser reads form-0's @formalizer by default.  For fusions the
#    correct formalizer depends on the CURRENT form (to keep the non-formalizable
#    axis fixed).  Overriding the handler to use pkmn.species_data.formalizer
#    (the current form's list) fixes this.
#
# 2. Simple form-toggle items (Gracidea, Reveal Glass, etc.) reject any Pokemon
#    whose species is not exactly the target.  Fusions pass through this check as
#    their species is a compound ID.  Each handler is re-registered to also check
#    the stored component Pokemon, then toggle only that component's form axis.
#
# 3. N-Solarizer / N-Lunarizer absorb Solgaleo/Lunala into Necrozma via pkmn.fused.
#    For fusions containing Necrozma, the absorbed Pokemon is stored in the
#    Necrozma *component's* .fused attribute, and the fusion's encoded form is
#    updated to reflect the component's new form.
#
# All non-fusion behaviour is preserved verbatim so these overrides are transparent
# to the rest of the game.

# ── Helper ────────────────────────────────────────────────────────────────────

# Checks whether a fused Pokemon contains a component matching any of the given
# species, and if so applies +toggle_fn+ to that component's form axis.
#
# Returns the new encoded fusion form if a matching component was found, or nil.
#
# +toggle_fn+ receives the component's current form index and should return the
# desired new form index.
def pbFusionFormToggle(pkmn, *species_list, &toggle_fn)
    return nil unless pkmn.fused_species?
    num_sf = GameData::FusedSpecies.count_forms(pkmn.fusion_secondary.species)
    [:primary, :secondary].each do |axis|
        component = (axis == :primary) ? pkmn.fusion_primary : pkmn.fusion_secondary
        next unless component && species_list.any? { |s| component.isSpecies?(s) }
        current_pf = pkmn.form / num_sf
        current_sf = pkmn.form % num_sf
        if axis == :primary
            return toggle_fn.call(current_pf) * num_sf + current_sf
        else
            return current_pf * num_sf + toggle_fn.call(current_sf)
        end
    end
    return nil
end

# Generic helper: returns [component, :primary|:secondary] for the first fusion
# component matching +species+, or nil.  Used by absorption-item handlers
# (DNA Splicers, Reins of Unity, N-Solarizer, N-Lunarizer).
def pbFusionAbsorbingComponent(pkmn, species)
    return nil unless pkmn.fused_species?
    if pkmn.fusion_primary&.isSpecies?(species)
        return [pkmn.fusion_primary, :primary]
    elsif pkmn.fusion_secondary&.isSpecies?(species)
        return [pkmn.fusion_secondary, :secondary]
    end
    nil
end

# ── Universal Formaliser ──────────────────────────────────────────────────────
# Re-registered to use the CURRENT form's @formalizer instead of form 0's.
# For regular Pokemon the behaviour is identical (form 0 is always read in the
# original, which typically matches every form anyway).  For fusions the current
# form's @formalizer correctly restricts which axes are shown.

ItemHandlers::UseOnPokemon.add(:UNIVERSALFORMALIZER, proc { |item, pkmn, scene|
    species = pkmn.species
    # Fusions: read current form's formalizer so non-formalizable axes stay fixed.
    species_data = pkmn.fused_species? \
                   ? pkmn.species_data \
                   : GameData::Species.get_species_form(species, 0)
    valid_forms = species_data.formalizer.clone
    valid_forms.delete(pkmn.form)
    if valid_forms.length > 0
        possibleForms     = valid_forms
        possibleFormNames = valid_forms.map { |form|
            form_data = GameData::Species.get_species_form(species, form)
            next form_data.form_name
        }
        possibleFormNames.push(_INTL("Cancel"))
        choice = pbMessage(_INTL("Which form shall the Pokemon take?"), possibleFormNames, possibleFormNames.length)
        if choice < possibleForms.length
            pbSceneDefaultDisplay(_INTL("{1} swapped to {2}!", pkmn.name, possibleFormNames[choice]), scene)
            showPokemonChangesWindow(pkmn) {
                pkmn.form = possibleForms[choice]
            }
        end
        next true
    else
        pbSceneDefaultDisplay(_INTL("Cannot use this item on that Pokemon."), scene)
        next false
    end
})

# ── Simple form-toggle items ──────────────────────────────────────────────────
# Each handler checks for a fusion component first.  If found, only that
# component's form axis is toggled; the other axis is unchanged.
# If no fusion component matches, the original non-fusion logic runs.

ItemHandlers::UseOnPokemon.add(:GRACIDEA, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :SHAYMIN) { |f| f == 0 ? 1 : 0 }
    if new_form
        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        pkmn.setForm(new_form) {
            scene&.pbRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    unless pkmn.isSpecies?(:SHAYMIN)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Shaymin."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    formToSet = pkmn.form == 0 ? 1 : 0
    pkmn.setForm(formToSet) {
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

ItemHandlers::UseOnPokemon.add(:REVEALGLASS, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :TORNADUS, :THUNDURUS, :LANDORUS, :ENAMORUS) { |f| f == 0 ? 1 : 0 }
    if new_form
        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        pkmn.setForm(new_form) {
            scene&.pbRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    if !pkmn.isSpecies?(:TORNADUS) &&
       !pkmn.isSpecies?(:THUNDURUS) &&
       !pkmn.isSpecies?(:LANDORUS) &&
       !pkmn.isSpecies?(:ENAMORUS)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Tornadus, Thundurus, Landorus, or Enamorus."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    newForm = (pkmn.form == 0) ? 1 : 0
    pkmn.setForm(newForm) {
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

ItemHandlers::UseOnPokemon.add(:PRISONBOTTLE, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :HOOPA) { |f| f == 0 ? 1 : 0 }
    if new_form
        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        pkmn.setForm(new_form) {
            scene&.pbRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    if !pkmn.isSpecies?(:HOOPA)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Hoopa."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
    end
    newForm = (pkmn.form == 0) ? 1 : 0
    pkmn.setForm(newForm) {
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

ItemHandlers::UseOnPokemon.add(:GRISEOUSCORE, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :GIRATINA) { |f| f == 0 ? 1 : 0 }
    if new_form
        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        pkmn.setForm(new_form) {
            scene&.pbRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    unless pkmn.isSpecies?(:GIRATINA)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Giratina."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    formToSet = pkmn.form == 0 ? 1 : 0
    pkmn.setForm(formToSet) {
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

ItemHandlers::UseOnPokemon.add(:LUSTROUSGLOBE, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :PALKIA) { |f| f == 0 ? 1 : 0 }
    if new_form
        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        pkmn.setForm(new_form) {
            scene&.pbRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    unless pkmn.isSpecies?(:PALKIA)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Palkia."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    formToSet = pkmn.form == 0 ? 1 : 0
    pkmn.setForm(formToSet) {
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

ItemHandlers::UseOnPokemon.add(:ADAMANTCRYSTAL, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :DIALGA) { |f| f == 0 ? 1 : 0 }
    if new_form
        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        pkmn.setForm(new_form) {
            scene&.pbRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    unless pkmn.isSpecies?(:DIALGA)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Dialga."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    formToSet = pkmn.form == 0 ? 1 : 0
    pkmn.setForm(formToSet) {
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

# Zygarde Cube uses pkmn.species == :ZYGARDE (direct comparison) rather than
# isSpecies?, so pbFusionFormToggle's component check handles it correctly.
ItemHandlers::UseOnPokemon.add(:ZYGARDECUBE, proc { |item, pkmn, scene|
    new_form = pbFusionFormToggle(pkmn, :ZYGARDE) { |f| f == 0 ? 1 : 0 }
    if new_form
        pkmn.form = new_form
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1}'s Ability changed to {2}!", pkmn.name,
                                   GameData::Ability.get(pkmn.ability).name), scene)
        next true
    end
    if pkmn.species == :ZYGARDE
        pkmn.form = pkmn.form == 0 ? 1 : 0
        scene&.pbRefresh
        pbSceneDefaultDisplay(_INTL("{1}'s Ability changed to {2}!", pkmn.name,
                                   GameData::Ability.get(pkmn.ability).name), scene)
        next true
    else
        pbSceneDefaultDisplay(_INTL("Cannot use this item on that Pokemon."), scene)
        next false
    end
})

# ── DNA Splicers (Kyurem absorption) ─────────────────────────────────────────
# DNA Splicers absorb Reshiram (form 1) or Zekrom (form 2) into Kyurem.
# Identical structure to N-Solarizer/N-Lunarizer.
# Battle form changes (forms 3/4 when entering, revert on leaving) are handled
# automatically by PokeBattle_RealBattlePeer via the Kyurem MultipleForms handler.

ItemHandlers::UseOnPokemon.add(:DNASPLICERS, proc { |item, pkmn, scene|
    unless scene&.supportsFusion?
        pbSceneDefaultDisplay(_INTL("You cannot use this item in this menu."), scene)
        next false
    end

    # ── Fusion containing Kyurem ───────────────────────────────────────────
    result = pbFusionAbsorbingComponent(pkmn, :KYUREM)
    if result
        component, axis = result

        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end

        if component.fused
            # Already absorbed — unfuse
            if $Trainer.party_full?
                pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
                next false
            end
            absorbed  = component.fused
            new_form  = pbFusionNecrozmaEncode(pkmn, axis, 0)
            pkmn.setForm(new_form) {
                component.fused = nil
                $Trainer.party.push(absorbed)
                scene&.pbHardRefresh
                pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
            }
            next true
        end

        # Not yet fused — choose Reshiram or Zekrom
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:RESHIRAM) && !poke2.isSpecies?(:ZEKROM)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        target_form = poke2.isSpecies?(:RESHIRAM) ? 1 : 2
        new_form = pbFusionNecrozmaEncode(pkmn, axis, target_form)
        pkmn.setForm(new_form) {
            component.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end

    # ── Original non-fusion logic ──────────────────────────────────────────
    if !pkmn.isSpecies?(:KYUREM)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Kyurem."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    if pkmn.fused.nil?
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:RESHIRAM) && !poke2.isSpecies?(:ZEKROM)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        newForm = poke2.isSpecies?(:RESHIRAM) ? 1 : 2
        pkmn.setForm(newForm) {
            pkmn.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    if $Trainer.party_full?
        pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
        next false
    end
    pkmn.setForm(0) {
        $Trainer.party[$Trainer.party.length] = pkmn.fused
        pkmn.fused = nil
        scene&.pbHardRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

# ── Reins of Unity (Calyrex absorption) ──────────────────────────────────────
# Reins of Unity absorb Glastrier (form 1) or Spectrier (form 2) into Calyrex.
# Same structure as DNA Splicers / N-Solarizer.

ItemHandlers::UseOnPokemon.add(:REINSOFUNITY, proc { |item, pkmn, scene|
    unless scene&.supportsFusion?
        pbSceneDefaultDisplay(_INTL("You cannot use this item in this menu."), scene)
        next false
    end

    # ── Fusion containing Calyrex ──────────────────────────────────────────
    result = pbFusionAbsorbingComponent(pkmn, :CALYREX)
    if result
        component, axis = result

        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end

        if component.fused
            if $Trainer.party_full?
                pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
                next false
            end
            absorbed = component.fused
            new_form = pbFusionNecrozmaEncode(pkmn, axis, 0)
            pkmn.setForm(new_form) {
                component.fused = nil
                $Trainer.party.push(absorbed)
                scene&.pbHardRefresh
                pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
            }
            next true
        end

        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:GLASTRIER) && !poke2.isSpecies?(:SPECTRIER)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        target_form = poke2.isSpecies?(:GLASTRIER) ? 1 : 2
        new_form = pbFusionNecrozmaEncode(pkmn, axis, target_form)
        pkmn.setForm(new_form) {
            component.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end

    # ── Original non-fusion logic ──────────────────────────────────────────
    unless pkmn.isSpecies?(:CALYREX)
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Calyrex."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    if pkmn.fused.nil?
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        other_pkmn = $Trainer.party[chosen]
        if pkmn == other_pkmn
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif other_pkmn.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif other_pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !other_pkmn.isSpecies?(:GLASTRIER) && !other_pkmn.isSpecies?(:SPECTRIER)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        newForm = other_pkmn.isSpecies?(:GLASTRIER) ? 1 : 2
        pkmn.setForm(newForm) {
            pkmn.fused = other_pkmn
            $Trainer.remove_pokemon_at_index(chosen)
            scene.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    if $Trainer.party_full?
        pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."))
        next false
    end
    pkmn.setForm(0) {
        $Trainer.party[$Trainer.party.length] = pkmn.fused
        pkmn.fused = nil
        scene.pbHardRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name))
    }
    next true
})

# ── N-Solarizer / N-Lunarizer (Necrozma absorption) ──────────────────────────
# These items absorb Solgaleo/Lunala into a Necrozma, changing it to Dusk Mane
# (form 1) or Dawn Wings (form 2), stored via pkmn.fused.
#
# For a Universal Splicer fusion containing Necrozma:
#   - The absorbed Pokemon is stored in the Necrozma component's .fused attribute.
#   - The fusion's encoded form is updated to reflect the component's new form.
#   - Unfusing works in reverse: the component's .fused is released to the party
#     and the component reverts to form 0.
#
# Helper: returns [necrozma_component, :primary|:secondary] for a fused pkmn, or nil.
def pbFusionNecrozmaComponent(pkmn)
    return nil unless pkmn.fused_species?
    if pkmn.fusion_primary&.isSpecies?(:NECROZMA)
        return [pkmn.fusion_primary, :primary]
    elsif pkmn.fusion_secondary&.isSpecies?(:NECROZMA)
        return [pkmn.fusion_secondary, :secondary]
    end
    return nil
end

# Encodes a new fusion form where the Necrozma component is at +necrozma_form+.
def pbFusionNecrozmaEncode(pkmn, axis, necrozma_form)
    num_sf  = GameData::FusedSpecies.count_forms(pkmn.fusion_secondary.species)
    curr_pf = pkmn.form / num_sf
    curr_sf = pkmn.form % num_sf
    return (axis == :primary) \
           ? necrozma_form * num_sf + curr_sf \
           : curr_pf * num_sf + necrozma_form
end

ItemHandlers::UseOnPokemon.add(:NSOLARIZER, proc { |item, pkmn, scene|
    unless scene&.supportsFusion?
        pbSceneDefaultDisplay(_INTL("You cannot use this item in this menu."), scene)
        next false
    end

    # ── Fusion containing Necrozma ─────────────────────────────────────────
    result = pbFusionNecrozmaComponent(pkmn)
    if result
        component, axis = result

        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        if component.form == 2
            # Already Dawn Wings — N-Solarizer can't overwrite
            pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Necrozma."), scene)
            next false
        end

        if component.fused
            # Dusk Mane — unfuse: release Solgaleo back to party
            if $Trainer.party_full?
                pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
                next false
            end
            solgaleo = component.fused
            new_form  = pbFusionNecrozmaEncode(pkmn, axis, 0)
            pkmn.setForm(new_form) {
                component.fused = nil
                $Trainer.party.push(solgaleo)
                scene&.pbHardRefresh
                pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
            }
            next true
        end

        # Form 0 — fuse with Solgaleo
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:SOLGALEO)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        new_form = pbFusionNecrozmaEncode(pkmn, axis, 1)
        pkmn.setForm(new_form) {
            component.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end

    # ── Original non-fusion logic ──────────────────────────────────────────
    if !pkmn.isSpecies?(:NECROZMA) || pkmn.form == 2
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Necrozma."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    if pkmn.fused.nil?
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:SOLGALEO)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        pkmn.setForm(1) {
            pkmn.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    if $Trainer.party_full?
        pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
        next false
    end
    pkmn.setForm(0) {
        $Trainer.party[$Trainer.party.length] = pkmn.fused
        pkmn.fused = nil
        scene&.pbHardRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

ItemHandlers::UseOnPokemon.add(:NLUNARIZER, proc { |item, pkmn, scene|
    unless scene&.supportsFusion?
        pbSceneDefaultDisplay(_INTL("You cannot use this item in this menu."), scene)
        next false
    end

    # ── Fusion containing Necrozma ─────────────────────────────────────────
    result = pbFusionNecrozmaComponent(pkmn)
    if result
        component, axis = result

        if pkmn.fainted?
            pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
            next false
        end
        if component.form == 1
            # Already Dusk Mane — N-Lunarizer can't overwrite
            pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Necrozma."), scene)
            next false
        end

        if component.fused
            # Dawn Wings — unfuse: release Lunala back to party
            if $Trainer.party_full?
                pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
                next false
            end
            lunala   = component.fused
            new_form = pbFusionNecrozmaEncode(pkmn, axis, 0)
            pkmn.setForm(new_form) {
                component.fused = nil
                $Trainer.party.push(lunala)
                scene&.pbHardRefresh
                pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
            }
            next true
        end

        # Form 0 — fuse with Lunala
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:LUNALA)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        new_form = pbFusionNecrozmaEncode(pkmn, axis, 2)
        pkmn.setForm(new_form) {
            component.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end

    # ── Original non-fusion logic ──────────────────────────────────────────
    if !pkmn.isSpecies?(:NECROZMA) || pkmn.form == 1
        pbSceneDefaultDisplay(_INTL("It has no effect on Pokémon other than Necrozma."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end
    if pkmn.fused.nil?
        chosen = scene.pbChoosePokemon(_INTL("Fuse with which Pokémon?"))
        next false if chosen < 0
        poke2 = $Trainer.party[chosen]
        if pkmn == poke2
            pbSceneDefaultDisplay(_INTL("It cannot be fused with itself."), scene)
            next false
        elsif poke2.egg?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with an Egg."), scene)
            next false
        elsif poke2.fainted?
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that fainted Pokémon."), scene)
            next false
        elsif !poke2.isSpecies?(:LUNALA)
            pbSceneDefaultDisplay(_INTL("It cannot be fused with that Pokémon."), scene)
            next false
        end
        pkmn.setForm(2) {
            pkmn.fused = poke2
            $Trainer.remove_pokemon_at_index(chosen)
            scene&.pbHardRefresh
            pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
        }
        next true
    end
    if $Trainer.party_full?
        pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
        next false
    end
    pkmn.setForm(0) {
        $Trainer.party[$Trainer.party.length] = pkmn.fused
        pkmn.fused = nil
        scene&.pbHardRefresh
        pbSceneDefaultDisplay(_INTL("{1} changed Forme!", pkmn.name), scene)
    }
    next true
})

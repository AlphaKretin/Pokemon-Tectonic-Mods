# Fusion-aware overrides for form-changing items.
#
# Two problems solved here:
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

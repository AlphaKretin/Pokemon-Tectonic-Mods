# Adds fusion state storage and a detection helper to Pokemon.
# Kept here rather than in FusedSpecies.rb because this state is only
# meaningful in the context of the Universal Splicers item.
class Pokemon
    attr_accessor :fusion_primary    # Original primary Pokemon, preserved across the fusion
    attr_accessor :fusion_secondary  # Original secondary Pokemon, preserved across the fusion
    attr_accessor :fusion_exp_at_fusion  # fusion's exp at the moment of fusing (for unfuse distribution)

    def fused_species?
        species_data.is_a?(GameData::FusedSpecies)
    end

    # ── Form-change propagation ───────────────────────────────────────────────
    # When a fused Pokemon's form changes (e.g. via Universal Formaliser), the
    # new encoded form is decoded back into (primary_form, secondary_form) and
    # both stored component Pokemon are updated so they come back with the right
    # form on unfuse.
    unless method_defined?(:_set_form_without_fusions)
        alias_method :_set_form_without_fusions, :form=
    end
    def form=(value)
        if fused_species? && fusion_primary && fusion_secondary
            num_sf    = GameData::FusedSpecies.count_forms(fusion_secondary.species)
            new_pf    = value / num_sf
            new_sf    = value % num_sf
            fusion_primary.form   = new_pf unless fusion_primary.form   == new_pf
            fusion_secondary.form = new_sf unless fusion_secondary.form == new_sf
        end
        _set_form_without_fusions(value)
    end

    # setForm is a separate method from form= that also accepts a block; override it
    # too so that item handlers using setForm(n) { ... } also propagate component forms.
    unless method_defined?(:_set_form_block_without_fusions)
        alias_method :_set_form_block_without_fusions, :setForm
    end
    def setForm(value, &block)
        if fused_species? && fusion_primary && fusion_secondary
            num_sf    = GameData::FusedSpecies.count_forms(fusion_secondary.species)
            new_pf    = value / num_sf
            new_sf    = value % num_sf
            fusion_primary.form   = new_pf unless fusion_primary.form   == new_pf
            fusion_secondary.form = new_sf unless fusion_secondary.form == new_sf
        end
        _set_form_block_without_fusions(value, &block)
    end
end

ItemHandlers::UseOnPokemon.add(:UNIVERSALSPLICERS, proc { |item, pkmn, scene|
    unless scene&.supportsFusion?
        pbSceneDefaultDisplay(_INTL("You cannot use this item in this menu."), scene)
        next false
    end
    if pkmn.fainted?
        pbSceneDefaultDisplay(_INTL("This can't be used on the fainted Pokémon."), scene)
        next false
    end

    # ── Unfusing ──────────────────────────────────────────────────────────────
    # If the chosen Pokemon is already a fusion, split it back into its components.
    if pkmn.fused_species?
        if $Trainer.party.length >= 6
            pbSceneDefaultDisplay(_INTL("You have no room to separate the Pokémon."), scene)
            next false
        end
        primary   = pkmn.fusion_primary
        secondary = pkmn.fusion_secondary
        pkmn_idx  = $Trainer.party.index(pkmn)

        # Distribute EXP gained while fused: each component receives half.
        # If the fusion is at the level cap, boost both components to the cap instead
        # (accounts for EXP that was silently lost against the cap).
        exp_gained = pkmn.fusion_exp_at_fusion \
                     ? (pkmn.exp - pkmn.fusion_exp_at_fusion) \
                     : 0
        level_cap = getLevelCap
        at_cap    = level_cap > 0 && pkmn.level >= level_cap

        [primary, secondary].each do |component|
            if at_cap
                cap_exp = component.growth_rate.minimum_exp_for_level(level_cap)
                component.exp = cap_exp if component.exp < cap_exp
            elsif exp_gained > 0
                new_exp = component.growth_rate.add_exp(component.exp, exp_gained)
                if level_cap > 0
                    cap_exp = component.growth_rate.minimum_exp_for_level(level_cap)
                    new_exp = [new_exp, cap_exp].min
                end
                component.exp = new_exp
            end
        end

        $Trainer.party[pkmn_idx] = primary  # restore primary to the same slot
        $Trainer.party.push(secondary)      # append secondary to the end
        scene&.pbHardRefresh
        pbSceneDefaultDisplay(_INTL("{1} and {2} were separated!", primary.name, secondary.name), scene)
        next true
    end

    # ── Fusing ────────────────────────────────────────────────────────────────
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
    elsif poke2.fused_species?
        pbSceneDefaultDisplay(_INTL("A fused Pokémon cannot be fused again."), scene)
        next false
    end

    # Let the player pick which arrangement they want via the choice UI.
    choice = pbChooseFusion(pkmn, poke2)
    next false if choice.nil?

    fusion_species  = choice[:fusion]
    primary_pkmn    = choice[:primary]
    secondary_pkmn  = choice[:secondary]

    # Build a new Pokemon from the chosen FusedSpecies.
    # Level is the average of both parents.
    fused_level = ((primary_pkmn.level + secondary_pkmn.level) / 2.0).round
    fused       = Pokemon.new(fusion_species.id, fused_level, primary_pkmn.owner)
    # Set the encoded form BEFORE assigning components so the form= override
    # does not try to update still-nil fusion_primary/fusion_secondary.
    fused.form = fusion_species.form if fusion_species.form > 0
    fused.fusion_primary        = primary_pkmn
    fused.fusion_secondary      = secondary_pkmn
    fused.fusion_exp_at_fusion  = fused.exp

    # Moveset: start from the primary's exact current moves, then offer each of
    # the secondary's moves that aren't already known.  pbLearnMove handles the
    # full "which move to forget?" UI so the player can accept or decline each one.
    fused.moves = primary_pkmn.moves.map(&:clone)
    secondary_pkmn.moves.each do |move|
        next if fused.hasMove?(move.id)
        pbLearnMove(fused, move.id)
    end

    # Replace primary_pkmn in-place (preserves its party slot), then remove
    # secondary_pkmn.  Capture secondary's index *before* any mutation to
    # avoid index-shift surprises.
    secondary_idx = $Trainer.party.index(secondary_pkmn)
    $Trainer.party[$Trainer.party.index(primary_pkmn)] = fused
    $Trainer.remove_pokemon_at_index(secondary_idx)
    scene&.pbHardRefresh
    pbSceneDefaultDisplay(_INTL("{1} and {2} fused into {3}!",
                                primary_pkmn.name, secondary_pkmn.name, fused.name), scene)
    next true
})

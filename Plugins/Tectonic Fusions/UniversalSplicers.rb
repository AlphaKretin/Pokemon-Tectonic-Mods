# Adds fusion state storage and a detection helper to Pokemon.
# Kept here rather than in FusedSpecies.rb because this state is only
# meaningful in the context of the Universal Splicers item.
class Pokemon
    attr_accessor :fusion_head  # Original head Pokemon, preserved across the fusion
    attr_accessor :fusion_body  # Original body Pokemon, preserved across the fusion

    def fused_species?
        species_data.is_a?(GameData::FusedSpecies)
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
        head = pkmn.fusion_head
        body = pkmn.fusion_body
        pkmn_idx = $Trainer.party.index(pkmn)
        $Trainer.party[pkmn_idx] = head  # restore head to the same slot
        $Trainer.party.push(body)        # append body to the end
        scene&.pbHardRefresh
        pbSceneDefaultDisplay(_INTL("{1} and {2} were separated!", head.name, body.name), scene)
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

    # Create the FusedSpecies (auto-registers in FUSION_CACHE) and build a new
    # Pokemon from it.  The new Pokemon's level is the average of both parents.
    fusion_species = GameData::FusedSpecies.new(pkmn.species, poke2.species)
    fused_level    = ((pkmn.level + poke2.level) / 2.0).round
    fused          = Pokemon.new(fusion_species.id, fused_level, pkmn.owner)
    fused.fusion_head = pkmn
    fused.fusion_body = poke2

    # Replace pkmn in-place (preserves its party slot), then remove poke2.
    # Fetching poke2's index *before* any mutation avoids index-shift surprises.
    poke2_idx = $Trainer.party.index(poke2)
    $Trainer.party[$Trainer.party.index(pkmn)] = fused
    $Trainer.remove_pokemon_at_index(poke2_idx)
    scene&.pbHardRefresh
    pbSceneDefaultDisplay(_INTL("{1} and {2} fused into {3}!", pkmn.name, poke2.name, fused.name), scene)
    next true
})

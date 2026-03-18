# Enables fused Pokemon to evolve component-by-component.
#
# When a fused Pokemon levels up, each component's evolution conditions are
# evaluated using the fusion's current level (and other fusion attributes such
# as happiness where relevant).  The first component that qualifies triggers an
# evolution into a new FusedSpecies (e.g. Bulbasaur/Squirtle → Bulbasaur/Wartortle).
#
# Components are checked primary-first; if both components would evolve at the
# same level, the primary evolves first and the secondary will trigger on the
# next qualifying level-up check.
#
# After the evolution animation, the stored component Pokemon's species is updated
# so it comes back as the correct evolved species on unfuse.
class Pokemon
    # Stores pending component evolution info between check and apply phases.
    # { which: :primary | :secondary, new_species: Symbol, new_form: Integer }
    attr_accessor :fusion_pending_component_update

    # ── Evolution check ──────────────────────────────────────────────────────

    unless method_defined?(:_check_evolution_on_level_up_without_fusions)
        alias_method :_check_evolution_on_level_up_without_fusions, :check_evolution_on_level_up
    end
    def check_evolution_on_level_up(finalCheck = true)
        return _check_evolution_on_level_up_without_fusions(finalCheck) unless fused_species?
        # Respect the standard blockers on the fusion itself.
        return nil if hasItem?(:EVERSTONE) || hasItem?(:EVIOLITE)

        [:primary, :secondary].each do |which|
            component = (which == :primary) ? @fusion_primary : @fusion_secondary
            next unless component

            # Evaluate each of the component's evolution paths using the fusion's
            # level (and other fusion stats) as the trigger values.
            component.species_data.get_evolutions.each do |new_component_species, evo_method, evo_param|
                next unless GameData::Evolution.get(evo_method).call_level_up(self, evo_param, finalCheck)

                new_primary_sym   = (which == :primary)   ? new_component_species : @fusion_primary.species
                new_secondary_sym = (which == :secondary) ? new_component_species : @fusion_secondary.species
                # The evolving component resets to form 0; the unchanged component keeps its form.
                new_pf = (which == :primary)   ? 0 : @fusion_primary.form
                new_sf = (which == :secondary) ? 0 : @fusion_secondary.form
                new_fusion = GameData::FusedSpecies.new(new_primary_sym, new_secondary_sym, new_pf, new_sf)
                @fusion_pending_component_update = { which: which, new_species: new_component_species, new_form: new_fusion.form }
                return new_fusion.id
            end
        end
        return nil
    end

    # ── Post-evolution component update ──────────────────────────────────────

    unless method_defined?(:_action_after_evolution_without_fusions)
        alias_method :_action_after_evolution_without_fusions, :action_after_evolution
    end
    def action_after_evolution(new_species)
        if @fusion_pending_component_update
            update    = @fusion_pending_component_update
            component = (update[:which] == :primary) ? @fusion_primary : @fusion_secondary
            # Updating the stored component's species means unfusing later will
            # correctly return the evolved Pokemon (e.g. Wartortle, not Squirtle).
            component.species = update[:new_species]
            component.form    = 0  # evolved species resets to its base form
            # Update own encoded form in case the new species has a different form
            # count, which would shift the encoding.  Direct @form assignment avoids
            # recursively triggering the form= component-update hook.
            @form = update[:new_form] if update[:new_form]
            @fusion_pending_component_update = nil
        end
        _action_after_evolution_without_fusions(new_species)
    end
end

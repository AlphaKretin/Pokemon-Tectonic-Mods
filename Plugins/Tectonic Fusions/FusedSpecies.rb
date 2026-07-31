module GameData
    # Lazy cache for FusedSpecies instances, keyed by their fusion ID symbol (form 0)
    # or [fusion_id_symbol, form_number] for non-zero forms.
    # Lives alongside Species::DATA but is never written to disk.
    # Populated automatically when a FusedSpecies is instantiated.
    class Species
        FUSION_CACHE = {}

        class << self
            # Each alias is guarded so that reloading this file (e.g. after a debug
            # restart) does not re-alias the already-overridden method, which would
            # make _xxx_without_fusions point back to the override and loop forever.
            unless method_defined?(:_exists_without_fusions)
                alias_method :_exists_without_fusions, :exists?
            end
            # Also returns true for fusion IDs held in FUSION_CACHE or reconstructable
            # from DATA.  Without this, SpeciesMetrics (and anything else that calls
            # Species.exists? as a guard) raises "Undefined species" for fusions.
            def exists?(other)
                sym = case other
                      when Symbol then other
                      when String then other.to_sym
                      else nil
                      end
                if sym && !DATA.key?(sym)
                    return true if FUSION_CACHE.key?(sym)
                    return true if GameData::FusedSpecies.try_reconstruct(sym)
                end
                return _exists_without_fusions(other)
            end

            unless method_defined?(:_get_without_fusions)
                alias_method :_get_without_fusions, :get
            end
            # Falls through to FUSION_CACHE when the symbol is not in DATA.
            # If the symbol looks like a fusion ID (not in DATA, not yet cached),
            # attempts to reconstruct it before raising "Unknown ID".
            def get(other)
                sym = other.is_a?(String) ? other.to_sym : other
                if sym.is_a?(Symbol) && !DATA.key?(sym)
                    return FUSION_CACHE[sym] if FUSION_CACHE.key?(sym)
                    reconstructed = GameData::FusedSpecies.try_reconstruct(sym)
                    return reconstructed if reconstructed
                end
                return _get_without_fusions(other)
            end

            unless method_defined?(:_get_species_form_without_fusions)
                alias_method :_get_species_form_without_fusions, :get_species_form
            end
            # Returns a cached (or reconstructed) fusion when the species symbol
            # is not present in DATA.  For non-zero forms, checks the [id, form]
            # cache key first so each form combination returns the correct object.
            def get_species_form(species, form)
                if species.is_a?(Symbol) && !DATA.key?(species)
                    form_int = form.to_i
                    if form_int > 0
                        cache_key = [species, form_int]
                        return FUSION_CACHE[cache_key] if FUSION_CACHE.key?(cache_key)
                        reconstructed = GameData::FusedSpecies.try_reconstruct(species, form_int)
                        return reconstructed if reconstructed
                    end
                    return FUSION_CACHE[species] if FUSION_CACHE.key?(species)
                    reconstructed = GameData::FusedSpecies.try_reconstruct(species)
                    return reconstructed if reconstructed
                end
                return _get_species_form_without_fusions(species, form)
            end

            # ── Cry ─────────────────────────────────────────────────────────
            unless method_defined?(:_check_cry_file_without_fusions)
                alias_method :_check_cry_file_without_fusions, :check_cry_file
            end
            def check_cry_file(species, form = 0)
                return _check_cry_file_without_fusions(species, form) if DATA.key?(species)
                fusion = GameData::FusedSpecies.try_reconstruct(species, form)
                return nil unless fusion
                _check_cry_file_without_fusions(fusion.primary_species.species, fusion.primary_species.form)
            end
        end
    end

    # A species that is created on the fly by fusing two component species together.
    # Properties are calculated from the primary and secondary species rather than loaded from PBS.
    # The primary species contributes the front half of the name and first type;
    # the secondary species contributes the back half of the name and second type.
    #
    # Form support: each combination of component forms is a separate "form" of the fusion.
    # The encoded form number is:  primary_form * count_forms(secondary) + secondary_form
    # This allows the Universal Formaliser and any other form-changing mechanism to cycle
    # through all combinations by setting pkmn.form to different values in [0, num_forms).
    class FusedSpecies < Species
        attr_reader :primary_species
        attr_reader :secondary_species

        # Returns the total number of forms a species has (including form 0).
        # Forms are expected to be sequential (DATA keys :SPECIES_1, :SPECIES_2, …).
        def self.count_forms(species_id)
            count = 1
            i     = 1
            while GameData::Species::DATA.key?(:"#{species_id}_#{i}")
                count += 1
                i     += 1
            end
            count
        end

        # Attempts to parse +fusion_id+ as a fusion of two known species by trying
        # every underscore in the string as the primary/secondary split point.  Returns the
        # resulting FusedSpecies (which is also cached) or nil if no valid split is found.
        #
        # Works with multi-word species IDs like MR_MIME or TYPE_NULL because it
        # tries ALL split positions, not just the first underscore.
        #
        # +form+ is the encoded fusion form number; it is decoded into the two component
        # form indices using count_forms for the secondary species.
        def self.try_reconstruct(fusion_id, form = 0)
            parts = fusion_id.to_s.split("_")
            return nil if parts.length < 2
            (1...parts.length).each do |i|
                primary_sym   = parts[0...i].join("_").to_sym
                secondary_sym = parts[i..].join("_").to_sym
                next unless GameData::Species::DATA.key?(primary_sym) && GameData::Species::DATA.key?(secondary_sym)
                num_secondary  = count_forms(secondary_sym)
                primary_form   = form / num_secondary
                secondary_form = form % num_secondary
                return new(primary_sym, secondary_sym, primary_form, secondary_form) # auto-registers in FUSION_CACHE
            end
            return nil
        end

        # @param primary        [Symbol] base species ID of the primary component
        # @param secondary      [Symbol] base species ID of the secondary component
        # @param primary_form   [Integer] form index of the primary component (default 0)
        # @param secondary_form [Integer] form index of the secondary component (default 0)
        def initialize(primary, secondary, primary_form = 0, secondary_form = 0)
            # Fetch form-specific species data for each component.
            @primary_species   = GameData::Species.get_species_form(primary, primary_form) \
                                 || GameData::Species.get(primary)
            @secondary_species = GameData::Species.get_species_form(secondary, secondary_form) \
                                 || GameData::Species.get(secondary)

            # Identity: the fusion ID is always based on the BASE species IDs (not form
            # variant IDs), so all form combinations share the same @id.
            @id         = :"#{@primary_species.species}_#{@secondary_species.species}"
            @id_number  = -1
            @species    = @id
            @form       = primary_form * GameData::FusedSpecies.count_forms(@secondary_species.species) + secondary_form
            @pokedex_form = @form

            # Name and flavour text are stored raw; override name/category/pokedex_entry
            # below so translation helpers are bypassed entirely for fusions.
            @real_name         = fuse_names(@primary_species.real_name, @secondary_species.real_name)
            @real_form_name    = nil
            @real_category     = "Fusion"
            @real_pokedex_entry = "A fusion of #{@primary_species.real_name} and #{@secondary_species.real_name}."

            # Typing: head's primary type + body's primary type.
            # Head always contributes its first type.
            # Body contributes: its other type if it shares a type with type1 and is dual-typed;
            # otherwise its second type if it has one; otherwise its first type.
            @type1 = @primary_species.type1
            secondary_is_dual = @secondary_species.type1 != @secondary_species.type2
            @type2 = if secondary_is_dual && @secondary_species.type1 == @type1
                         @secondary_species.type2
                     elsif secondary_is_dual && @secondary_species.type2 == @type1
                         @secondary_species.type1
                     elsif secondary_is_dual
                         @secondary_species.type2
                     else
                         @secondary_species.type1
                     end

            # Stats: weighted blend of both parents per STAT_WEIGHTING.
            # stat_rounding 0 skips the rounding logic in the base initializer
            # (which we never call); we do our own rounding here.
            @stat_rounding = 0
            @base_stats = {}
            GameData::Stat.each_main do |s|
                primary_stat = 0
                secondary_stat = 0
                if PRIMARY_STATS.include?(s.id)
                    primary_stat = @primary_species.base_stats[s.id]
                    secondary_stat = @secondary_species.base_stats[s.id]
                else
                    # HP, Special Stats
                    primary_stat = @secondary_species.base_stats[s.id]
                    secondary_stat = @primary_species.base_stats[s.id]
                end
                high_weight = STAT_WEIGHTING[0]
                low_weight  = STAT_WEIGHTING[1]
                total = high_weight + low_weight
                fused_stat = (high_weight * primary_stat + low_weight * secondary_stat) / total.to_f
                @base_stats[s.id] = fused_stat.round
            end

            @base_exp    = ((@primary_species.base_exp + @secondary_species.base_exp) / 2.0).round
            @growth_rate = @primary_species.growth_rate
            @gender_ratio = @primary_species.gender_ratio
            @catch_rate  = [@primary_species.catch_rate, @secondary_species.catch_rate].min
            @happiness   = ((@primary_species.happiness + @secondary_species.happiness) / 2.0).round

            # Moves: union of both parents' full learnsets (including moves inherited
            # from their own pre-evolutions), since fusions have no PBS-defined
            # prevolution chain of their own to inherit through.
            # When both parents teach the same move at a level, keep the lower level
            # (earlier access is more lenient).
            primary_level_moves = @primary_species.level_moves.map { |entry| entry.dup }
            secondary_level_moves = @secondary_species.level_moves.map { |entry| entry.dup }
            combined_level_moves = {}
            (primary_level_moves + secondary_level_moves).each do |entry|
                level, move = entry
                if combined_level_moves.key?(move)
                    combined_level_moves[move] = [combined_level_moves[move], level].min
                else
                    combined_level_moves[move] = level
                end
            end
            @moves = combined_level_moves.map { |move, level| [level, move] }

            @form_move = nil

            # Includes each component's own inherited_tutor_moves so that tutor/egg
            # moves inherited from a component's real pre-evolution (or unlocked by
            # an ancestor's TutorAny flag) aren't lost, mirroring the level_moves fix above.
            @tutor_moves = (@primary_species.tutor_moves + @primary_species.inherited_tutor_moves +
                            @secondary_species.tutor_moves + @secondary_species.inherited_tutor_moves).uniq
            @tutor_moves.sort_by! { |a| a.to_s }

            @line_moves = (@primary_species.line_moves + @secondary_species.line_moves).uniq
            @line_moves.sort_by! { |a| a.to_s }

            # Abilities: head's first ability + body's second ability (or body's first if it has only one).
            ability1 = @primary_species.abilities[0]
            ability2 = (@secondary_species.abilities.length > 1) ? @secondary_species.abilities[1] : @secondary_species.abilities[0]
            @abilities        = [ability1, ability2].compact

            # hidden abilities don't exist in Chasm Engine so this is mostly pointless
            @hidden_abilities = @primary_species.hidden_abilities.dup

            @wild_item_common   = nil
            @wild_item_uncommon = nil
            @wild_item_rare     = nil

            @hatch_steps = [@primary_species.hatch_steps, @secondary_species.hatch_steps].max
            @evolutions  = [] # Fusions do not evolve via standard PBS data

            # Physical dimensions: average, kept as integer tenths (same as base class)
            @height = ((@primary_species.height + @secondary_species.height) / 2.0).round
            @weight = ((@primary_species.weight + @secondary_species.weight) / 2.0).round

            @generation = [@primary_species.generation, @secondary_species.generation].max

            # No mega evolution for fusions
            @mega_stone   = nil
            @mega_move    = nil
            @unmega_form  = 0
            @mega_message = 0

            @notes = ""
            @earliest_available        = nil
            @earliest_available_normal = nil

            # Tribes: union of both parents (inherit from neither, since fusions have
            # no prevolution chain)
            @tribes = (@primary_species.tribes(true) + @secondary_species.tribes(true)).uniq

            @defined_in_extension = false

            # Flags: union of both parents
            @flags        = (@primary_species.flags + @secondary_species.flags).uniq
            @sticky_items = []

            # Formaliser form list: only vary the axes whose base species is
            # Formaliser-compatible (i.e. the base form has a non-empty @formalizer).
            # This prevents the Universal Formaliser from accidentally changing an axis
            # that belongs to a species whose form changes are gated behind a specific
            # item (e.g. Shaymin via Gracidea, Giratina via Griseous Core).
            num_pf = GameData::FusedSpecies.count_forms(@primary_species.species)
            num_sf = GameData::FusedSpecies.count_forms(@secondary_species.species)
            pf_base_formalizer = (GameData::Species.get(@primary_species.species).formalizer rescue [])
            sf_base_formalizer = (GameData::Species.get(@secondary_species.species).formalizer rescue [])
            pf_formalizable = pf_base_formalizer.any?
            sf_formalizable = sf_base_formalizer.any?

            @formalizer = []
            if pf_formalizable && sf_formalizable
                # Both axes are free to vary.
                num_pf.times { |pf| num_sf.times { |sf| @formalizer << pf * num_sf + sf } }
            elsif pf_formalizable
                # Only vary the primary axis; keep secondary fixed at this instance's sf.
                num_pf.times { |pf| @formalizer << pf * num_sf + secondary_form }
            elsif sf_formalizable
                # Only vary the secondary axis; keep primary fixed at this instance's pf.
                num_sf.times { |sf| @formalizer << primary_form * num_sf + sf }
            end
            # If neither is formalizable, @formalizer stays [] and the item says "no effect".

            # Register in the fusion cache so GameData::Species.get/:get_species_form
            # can find this instance by its ID without it being in DATA.
            # Form-0 entries use the bare ID symbol; non-zero forms use [id, form_num].
            cache_key = @form == 0 ? @id : [@id, @form]
            GameData::Species::FUSION_CACHE[cache_key] = self
            # Ensure the bare symbol key always resolves to something so existence
            # and identity checks work even if form 0 was never explicitly created.
            GameData::Species::FUSION_CACHE[@id] ||= self
        end

        # Returns the fused display name directly, bypassing the message-hash lookup
        # since fusions have no entry in any translation table.
        def name
            fuse_names(primary_species.name, secondary_species.name)
        end

        # Combines the component form names, separated by " / ".
        # Returns "" when both components are on their base form (form name is empty).
        def form_name
            pf_name = (@primary_species.form_name.to_s   rescue "")
            sf_name = (@secondary_species.form_name.to_s rescue "")
            parts   = [pf_name, sf_name].reject(&:empty?)
            return parts.empty? ? "" : parts.join(" / ")
        end

        def full_name
            name
        end

        def category
            "Fusion"
        end

        def pokedex_entry
            "A fusion of #{primary_species.name} and #{secondary_species.name}."
        end

        # Fusions have no form-specific moves.
        def form_specific_moves
            return []
        end

        # ── Evolution chain (for MasterDex display) ──────────────────────────────
        # The inherited methods iterate @evolutions which is always [] for fusions.
        # Instead, we derive the fusion's evolution/pre-evolution chain dynamically
        # from the two components, pairing each component's relative with the
        # unchanged partner to produce the corresponding fusion species ID.
        #
        # Example – Bulbasaur/Squirtle (primary=Bulbasaur, secondary=Squirtle):
        #   get_evolutions  → [:IVYSAUR_SQUIRTLE, :Level, 16]   (primary evolves)
        #                     [:BULBASAUR_WARTORTLE, :Level, 16] (secondary evolves)
        #   get_prevolutions → [] (both components are base forms)
        #
        # The returned format [species_sym, method_sym, parameter] matches what
        # GameData::Species#get_evolutions / get_prevolutions normally returns, so
        # the MasterDex helpers (getEvolutionsRecursive, drawPageEvolution, etc.)
        # work without any additional changes.
        #
        # .species is used (not .id) so that the fusion IDs are always based on the
        # base species symbol, regardless of which form variant @primary_species is.
        def get_evolutions(exclude_invalid = true)
            result = []
            primary_sym   = @primary_species.species
            secondary_sym = @secondary_species.species
            @primary_species.get_evolutions(exclude_invalid).each do |evo_species, evo_method, evo_param|
                result << [:"#{evo_species}_#{secondary_sym}", evo_method, evo_param]
            end
            @secondary_species.get_evolutions(exclude_invalid).each do |evo_species, evo_method, evo_param|
                result << [:"#{primary_sym}_#{evo_species}", evo_method, evo_param]
            end
            return result
        end

        def get_prevolutions
            result = []
            primary_sym   = @primary_species.species
            secondary_sym = @secondary_species.species
            @primary_species.get_prevolutions.each do |prev_species, evo_method, evo_param|
                result << [:"#{prev_species}_#{secondary_sym}", evo_method, evo_param]
            end
            @secondary_species.get_prevolutions.each do |prev_species, evo_method, evo_param|
                result << [:"#{primary_sym}_#{prev_species}", evo_method, evo_param]
            end
            return result
        end

        private

        # Combines two names: first ceil(len/2) characters of the primary name
        # followed by the last floor(len/2) characters of the secondary name.
        # Example: "Bulbasaur" + "Squirtle" → "Bulba" + "rtle" = "Bulbartle"
        def fuse_names(primary_name, secondary_name)
            primary_half = primary_name[0, (primary_name.length / 2.0).ceil]
            secondary_half = secondary_name[(secondary_name.length / 2.0).floor..]
            return primary_half + secondary_half
        end
    end
end

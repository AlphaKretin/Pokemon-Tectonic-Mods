module GameData
    # Lazy cache for FusedSpecies instances, keyed by their fusion ID symbol.
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
            # is not present in DATA.
            def get_species_form(species, form)
                if species.is_a?(Symbol) && !DATA.key?(species)
                    return FUSION_CACHE[species] if FUSION_CACHE.key?(species)
                    reconstructed = GameData::FusedSpecies.try_reconstruct(species)
                    return reconstructed if reconstructed
                end
                return _get_species_form_without_fusions(species, form)
            end
        end
    end

    # A species that is created on the fly by fusing two component species together.
    # Properties are calculated from the head and body species rather than loaded from PBS.
    # Convention: the head species contributes the front half of the name and primary type;
    # the body species contributes the back half of the name and secondary typing.
    class FusedSpecies < Species
        attr_reader :head_species
        attr_reader :body_species

        # Attempts to parse +fusion_id+ as a fusion of two known species by trying
        # every underscore in the string as the head/body split point.  Returns the
        # resulting FusedSpecies (which is also cached) or nil if no valid split is found.
        #
        # Works with multi-word species IDs like MR_MIME or TYPE_NULL because it
        # tries ALL split positions, not just the first underscore.
        def self.try_reconstruct(fusion_id)
            parts = fusion_id.to_s.split("_")
            return nil if parts.length < 2
            (1...parts.length).each do |i|
                head_sym = parts[0...i].join("_").to_sym
                body_sym = parts[i..].join("_").to_sym
                next unless GameData::Species::DATA.key?(head_sym) && GameData::Species::DATA.key?(body_sym)
                return new(head_sym, body_sym) # auto-registers in FUSION_CACHE
            end
            return nil
        end

        # @param head [GameData::Species] the species whose front half is used
        # @param body [GameData::Species] the species whose back half is used
        def initialize(head, body)
            @head_species = GameData::Species.get(head)
            @body_species = GameData::Species.get(body)

            # Identity
            @id         = :"#{@head_species.id}_#{@body_species.id}"
            @id_number  = -1
            @species    = @id
            @form       = 0
            @pokedex_form = 0

            # Name and flavour text are stored raw; override name/category/pokedex_entry
            # below so translation helpers are bypassed entirely for fusions.
            @real_name         = fuse_names(@head_species.real_name, @body_species.real_name)
            @real_form_name    = nil
            @real_category     = "Fusion"
            @real_pokedex_entry = "A fusion of #{@head_species.real_name} and #{@body_species.real_name}."

            # Typing: head's primary type + body's primary type.
            # Head always contributes its first type.
            # Body contributes: its other type if it shares a type with type1 and is dual-typed;
            # otherwise its second type if it has one; otherwise its first type.
            @type1 = @head_species.type1
            body_is_dual = @body_species.type1 != @body_species.type2
            @type2 = if body_is_dual && @body_species.type1 == @type1
                         @body_species.type2
                     elsif body_is_dual && @body_species.type2 == @type1
                         @body_species.type1
                     elsif body_is_dual
                         @body_species.type2
                     else
                         @body_species.type1
                     end

            # Stats: average of both parents, clamped to at least 1.
            # stat_rounding 0 skips the rounding logic in the base initializer
            # (which we never call); we do our own rounding here.
            @stat_rounding = 0
            @base_stats = {}
            GameData::Stat.each_main do |s|
                avg = ((@head_species.base_stats[s.id] || 1) + (@body_species.base_stats[s.id] || 1)) / 2.0
                @base_stats[s.id] = [avg.round, 1].max
            end

            @base_exp    = ((@head_species.base_exp + @body_species.base_exp) / 2.0).round
            @growth_rate = @head_species.growth_rate
            @gender_ratio = @head_species.gender_ratio
            @catch_rate  = [@head_species.catch_rate, @body_species.catch_rate].min
            @happiness   = ((@head_species.happiness + @body_species.happiness) / 2.0).round

            # Moves: union of both parents. When both parents teach the same move at
            # a level, keep the lower level (earlier access is more lenient).
            head_level_moves = @head_species.moves.map { |entry| entry.dup }
            body_level_moves = @body_species.moves.map { |entry| entry.dup }
            combined_level_moves = {}
            (head_level_moves + body_level_moves).each do |entry|
                level, move = entry
                if combined_level_moves.key?(move)
                    combined_level_moves[move] = [combined_level_moves[move], level].min
                else
                    combined_level_moves[move] = level
                end
            end
            @moves = combined_level_moves.map { |move, level| [level, move] }

            @form_move = nil

            @tutor_moves = (@head_species.tutor_moves + @body_species.tutor_moves).uniq
            @tutor_moves.sort_by! { |a| a.to_s }

            @line_moves = (@head_species.line_moves + @body_species.line_moves).uniq
            @line_moves.sort_by! { |a| a.to_s }

            # Abilities: head's first ability + body's second ability (or body's first if it has only one).
            ability1 = @head_species.abilities[0]
            ability2 = (@body_species.abilities.length > 1) ? @body_species.abilities[1] : @body_species.abilities[0]
            @abilities        = [ability1, ability2].compact

            # hidden abilities don't exist in Chasm Engine so this is mostly pointless
            @hidden_abilities = @head_species.hidden_abilities.dup

            @wild_item_common   = nil
            @wild_item_uncommon = nil
            @wild_item_rare     = nil

            @hatch_steps = [@head_species.hatch_steps, @body_species.hatch_steps].max
            @evolutions  = [] # Fusions do not evolve

            # Physical dimensions: average, kept as integer tenths (same as base class)
            @height = ((@head_species.height + @body_species.height) / 2.0).round
            @weight = ((@head_species.weight + @body_species.weight) / 2.0).round

            @generation = [@head_species.generation, @body_species.generation].max

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
            @tribes = (@head_species.tribes(true) + @body_species.tribes(true)).uniq

            @defined_in_extension = false

            # Flags: union of both parents
            @flags        = (@head_species.flags + @body_species.flags).uniq
            @formalizer   = []
            @sticky_items = []

            # Register in the fusion cache so GameData::Species.get/:get_species_form
            # can find this instance by its ID without it being in DATA.
            GameData::Species::FUSION_CACHE[@id] = self
        end

        # Returns the fused display name directly, bypassing the message-hash lookup
        # since fusions have no entry in any translation table.
        def name
            fuse_names(head_species.name, body_species.name)
        end

        def form_name
            return ""
        end

        def full_name
            name
        end

        def category
            "Fusion"
        end

        def pokedex_entry
            "A fusion of #{head_species.name} and #{body_species.name}."
        end

        # Fusions have no form-specific moves.
        def form_specific_moves
            return []
        end

        private

        # Combines two names: first ceil(len/2) characters of the head name
        # followed by the last floor(len/2) characters of the body name.
        # Example: "Bulbasaur" + "Squirtle" → "Bulba" + "rtle" = "Bulbartle"
        def fuse_names(head_name, body_name)
            head_half = head_name[0, (head_name.length / 2.0).ceil]
            body_half = body_name[(body_name.length / 2.0).floor..]
            return head_half + body_half
        end
    end
end

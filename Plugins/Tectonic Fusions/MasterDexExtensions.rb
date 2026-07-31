# Patches the MasterDex scene so that fused species display all pages correctly.
#
# Root cause: PokemonPokedexInfo_Scene#pbGetAvailableForms builds the @available
# list by iterating GameData::Species.each, which only walks DATA.  FusedSpecies
# instances live in FUSION_CACHE, so the iteration finds nothing, @available
# stays [], and every page method silently renders nothing.
#
# Fix: before falling through to the normal logic, detect that @species is a
# fused species and return a single hand-built form-0 entry.  This gives all
# page drawing methods exactly one form to iterate over, which is all they need.
class PokemonPokedexInfo_Scene
    # ── drawPageEvolution override ────────────────────────────────────────────
    # For fused species the normal method produces duplicate entries (both
    # components can independently evolve into many of the same intermediate
    # fusions) and clutters each line with "(through X)" suffixes.
    # This override deduplicates by species ID and drops that suffix entirely;
    # all other rendering logic is left identical to the original.
    unless method_defined?(:_drawPageEvolution_without_fusions)
        alias_method :_drawPageEvolution_without_fusions, :drawPageEvolution
    end
    def drawPageEvolution
        fusion_data = GameData::Species::FUSION_CACHE[@species]
        fusion_data ||= GameData::FusedSpecies.try_reconstruct(@species) if @species && !GameData::Species::DATA.key?(@species)
        return _drawPageEvolution_without_fusions unless fusion_data

        bg_path = "Graphics/Pictures/Pokedex/bg_evolution"
        bg_path += "_dark" if darkMode?
        @sprites["background"].setBitmap(_INTL(bg_path))
        overlay = @sprites["overlay"].bitmap
        base   = MessageConfig.pbDefaultTextMainColor
        shadow = MessageConfig.pbDefaultTextShadowColor
        xLeft  = 36

        for i in @available
            next unless i[2] == @form
            fSpecies = GameData::Species.get_species_form(@species, i[2])

            prevolutions  = fSpecies.get_prevolutions
            allEvolutions = getEvolutionsRecursive(fSpecies)

            coordinateY = 54
            index = 0
            @evolutionsArray = []

            # ── Pre-evolutions ─────────────────────────────────────────────────
            unless prevolutions.empty?
                drawFormattedTextEx(overlay, xLeft, coordinateY, 450,
                                    _INTL("<u>Pre-Evolutions</u>"), base, shadow)
                coordinateY += 34

                seen = {}
                prevolutions.each do |evolution|
                    species   = evolution[0]
                    method    = evolution[1]
                    parameter = evolution[2]
                    next if !method || !species || seen[species]
                    seen[species] = true
                    speciesData = GameData::Species.get_species_form(species, i[2])
                    next if speciesData.nil?
                    @evolutionsArray.push(evolution)
                    text = _INTL("<b>{1}</b> {2}", speciesData.name,
                                 describeEvolutionMethod(method, parameter))
                    color = index == @evolutionIndex ? Color.new(255, 100, 80) : base
                    drawFormattedTextEx(overlay, xLeft, coordinateY, 450, text, color, shadow)
                    coordinateY += 30
                    coordinateY += 30 if overlay.text_size(text).width > 450
                    index += 1
                end

                coordinateY += 30
            end

            # ── Evolutions: flatten, deduplicate, no "(through X)" ─────────────
            unless allEvolutions.empty?
                drawFormattedTextEx(overlay, xLeft, coordinateY, 450,
                                    _INTL("<u>Evolutions</u>"), base, shadow)
                coordinateY += 34

                seen = {}
                allEvolutions.each do |_fromSpecies, evolutions|
                    evolutions.each do |evolution|
                        species   = evolution[0]
                        method    = evolution[1]
                        parameter = evolution[2]
                        next if method.nil? || species.nil? || seen[species]
                        seen[species] = true
                        speciesData = GameData::Species.get_species_form(species, i[2])
                        next if speciesData.nil?
                        @evolutionsArray.push(evolution)
                        text = _INTL("<b>{1}</b> {2}", speciesData.name,
                                     describeEvolutionMethod(method, parameter))
                        color = index == @evolutionIndex ? Color.new(255, 100, 80) : base
                        drawFormattedTextEx(overlay, xLeft, coordinateY, 450, text, color, shadow)
                        coordinateY += 30
                        coordinateY += 30 if overlay.text_size(text).width > 450
                        index += 1
                    end
                end
            end

            if @evolutionsArray.empty?
                noneLabel = _INTL("None")
                noneLabelWidth = overlay.text_size(noneLabel).width
                drawTextEx(overlay, Graphics.width / 2 - noneLabelWidth / 2,
                            coordinateY + 30, 450, 1, noneLabel, base, shadow)
            end
        end
    end

    # ── pbGetAvailableForms override ──────────────────────────────────────────
    unless method_defined?(:_pbGetAvailableForms_without_fusions)
        alias_method :_pbGetAvailableForms_without_fusions, :pbGetAvailableForms
    end
    def pbGetAvailableForms
        base_fusion = GameData::Species::FUSION_CACHE[@species]
        unless base_fusion
            base_fusion = GameData::FusedSpecies.try_reconstruct(@species) if @species && !GameData::Species::DATA.key?(@species)
        end
        return _pbGetAvailableForms_without_fusions unless base_fusion

        num_pf = GameData::FusedSpecies.count_forms(base_fusion.primary_species.species)
        num_sf = GameData::FusedSpecies.count_forms(base_fusion.secondary_species.species)
        total  = num_pf * num_sf

        # Determine the gender value used for all entries (same as single-entry case).
        gender = case base_fusion.gender_ratio
                 when :AlwaysFemale then 1
                 else 0
                 end

        ret = []
        total.times do |form_num|
            pf = form_num / num_sf
            sf = form_num % num_sf
            # Retrieve (or create) the FusedSpecies for this specific combination.
            specific   = GameData::FusedSpecies.new(
                base_fusion.primary_species.species,
                base_fusion.secondary_species.species,
                pf, sf
            )
            form_label = specific.form_name
            if form_label.empty?
                form_label = case base_fusion.gender_ratio
                             when :AlwaysFemale then _INTL("Female")
                             when :Genderless   then (total > 1 ? _INTL("Form %d", form_num) : _INTL("One Form"))
                             else (total > 1 ? _INTL("Form %d", form_num) : _INTL("Male"))
                             end
            end
            ret << [form_label, gender, form_num]
        end

        @multiple_forms = total > 1
        return ret
    end
end

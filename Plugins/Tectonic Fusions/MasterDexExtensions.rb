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
    unless method_defined?(:_pbGetAvailableForms_without_fusions)
        alias_method :_pbGetAvailableForms_without_fusions, :pbGetAvailableForms
    end
    def pbGetAvailableForms
        fusion_data = GameData::Species::FUSION_CACHE[@species]
        unless fusion_data
            # Also catch fusions that are reconstructable but not yet cached
            fusion_data = GameData::FusedSpecies.try_reconstruct(@species) if @species && !GameData::Species::DATA.key?(@species)
        end
        if fusion_data
            @multiple_forms = false
            case fusion_data.gender_ratio
            when :AlwaysFemale
                return [[_INTL("Female"), 1, 0]]
            when :Genderless
                return [[_INTL("One Form"), 0, 0]]
            else
                # AlwaysMale or mixed-gender: show a single male entry.
                return [[_INTL("Male"), 0, 0]]
            end
        end
        return _pbGetAvailableForms_without_fusions
    end
end

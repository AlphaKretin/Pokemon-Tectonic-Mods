# Monkey-patches to fix tribe display overflow for fused Pokémon.
# Fused species inherit tribes from both components, often producing 4–6 tribes
# where the original UI only allocated space for 3.  These patches show a count
# (e.g. "6 Tribes") instead of overflowing.
#
# Both patches are self-contained in this file; no other plugin files are
# modified.  Load order is safe because "Chasm *" plugins (C) load before
# "Tectonic Fusions" (T) alphabetically, so the target classes exist first.

# ── MasterDex info page (PokemonPokedexInfo_Scene#drawPageInfo) ───────────────
# The original joins all tribe names into a single string and renders it in a
# 2-line drawTextEx box at (266, 166, w=224).  With many tribes the string is
# just truncated.  This override calls the original then, if there are more than
# 3 tribes, erases the truncated tribe text and draws a plain count instead.
# The erase rect (266, 166, 224, 64) sits well clear of all other elements on
# the page (type icons at y=120, Pokédex entry at y=244).
class PokemonPokedexInfo_Scene
    unless method_defined?(:_drawPageInfo_without_tribe_overflow_fix)
        alias_method :_drawPageInfo_without_tribe_overflow_fix, :drawPageInfo
    end
    def drawPageInfo
        _drawPageInfo_without_tribe_overflow_fix
        species_data = GameData::Species.get_species_form(@species, @form)
        return unless species_data.tribes.length > 3
        overlay = @sprites["overlay"].bitmap
        base   = MessageConfig.pbDefaultTextMainColor
        shadow = MessageConfig.pbDefaultTextShadowColor
        overlay.fill_rect(266, 166, 224, 64, Color.new(0, 0, 0, 0))
        drawTextEx(overlay, 266, 166, 224, 2,
                   _INTL("{1} Tribes", species_data.tribes.length), base, shadow)
    end
end

# ── Summary stats page (PokemonSummary_Scene#drawPageThree) ───────────────────
# The original draws each tribe on its own 32-px line starting at y=136.  With
# more than 3 tribes these lines overflow into the ability and stat areas.
#
# Strategy: temporarily replace @pokemon.tribes with [] via a singleton method
# so the original draws the compact "None" label (one line at tribesY+32 = 168)
# instead of individual overflowing lines.  After the call we erase only the
# "None" text — a narrow rect (x=56..256, y=168..200) that stops just before
# the stat labels which start at statNameX = 260 — and draw the count there.
class PokemonSummary_Scene
    unless method_defined?(:_drawPageThree_without_tribe_overflow_fix)
        alias_method :_drawPageThree_without_tribe_overflow_fix, :drawPageThree
    end
    def drawPageThree
        tribes = @pokemon.tribes
        if tribes.length > 3
            count = tribes.length
            @pokemon.define_singleton_method(:tribes) { [] }
            begin
                _drawPageThree_without_tribe_overflow_fix
            ensure
                @pokemon.singleton_class.remove_method(:tribes)
            end
            overlay    = @sprites["overlay"].bitmap
            tribe_base   = MessageConfig.pbDefaultTextMainColor
            tribe_shadow = MessageConfig.pbDefaultTextShadowColor
            # Erase "None" text (≈50px wide starting at x=56) without reaching
            # the stat labels that begin at x=260.
            overlay.fill_rect(56, 168, 200, 32, Color.new(0, 0, 0, 0))
            drawFormattedTextEx(overlay, 56, 168, 200,
                                _INTL("{1} Tribes", count), tribe_base, tribe_shadow)
        else
            _drawPageThree_without_tribe_overflow_fix
        end
    end
end

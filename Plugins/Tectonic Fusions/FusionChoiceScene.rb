# Full-screen side-by-side UI for choosing which of two possible fusions to
# create.  Shown after the player picks a second Pokémon to fuse with the
# first; lets them put either Pokémon in the primary role before committing.
#
# Design language follows the rest of Chasm Engine:
#   - Party bg.png background
#   - SpriteWindow_Base panels (auto-applies the game's window skin / dark mode)
#   - MessageConfig colour helpers for all theme-aware text
#   - Graphics/Pictures/types bitmap (64×28 per icon), same as Summary screen
#   - pbSetSystemFont / pbSetSmallFont + pbDrawTextPositions throughout
#
# Usage:
#   result = pbChooseFusion(pkmn_a, pkmn_b)
#   # nil if cancelled, or { fusion:, primary:, secondary: }

class FusionChoiceScene
    # ── Layout ───────────────────────────────────────────────────────────────
    PANEL_A_X     = 8
    PANEL_B_X     = 264   # 8 + 240 + 16 gap; right margin = 512-504 = 8 ✓
    PANEL_W       = 240
    PANEL_H       = 376   # fills y=8..384 (full screen height minus top margin)
    PANEL_Y       = 8
    CONTENT_INSET = 16    # window-skin border width

    # ── Type-icon dimensions (matches Graphics/Pictures/types strip) ─────────
    TYPE_ICON_W   = 64
    TYPE_ICON_H   = 28

    # ── Stat order and display labels (keys match GameData::Stat IDs) ─────────
    STAT_ORDER  = [:HP, :ATTACK, :DEFENSE, :SPECIAL_ATTACK, :SPECIAL_DEFENSE, :SPEED].freeze
    STAT_LABELS = {
        HP:               "HP",
        ATTACK:           "Attack",
        DEFENSE:          "Defense",
        SPECIAL_ATTACK:   "Sp. Atk",
        SPECIAL_DEFENSE:  "Sp. Def",
        SPEED:            "Speed",
    }.freeze

    # ── Signature gold accent for higher stats / selected name ───────────────
    # Matches SIGNATURE_COLOR_LIGHTER in PokemonPokedexInfo_Scene.
    COLOR_GOLD        = Color.new(228, 207, 128)
    COLOR_GOLD_SHADOW = darkMode? ? MessageConfig.pbDefaultTextShadowColor : MessageConfig.pbDefaultTextMainColor

    # ── Z levels (all within @viewport) ──────────────────────────────────────
    Z_BG      = 0
    Z_PANELS  = 100   # SpriteWindow_Base default
    Z_SPRITES = 110
    Z_OVERLAY = 120

    # ────────────────────────────────────────────────────────────────────────

    def pbStartScene(fusion_a, fusion_b, pkmn_a, pkmn_b)
        @fusion_a = fusion_a
        @fusion_b = fusion_b
        @pkmn_a   = pkmn_a
        @pkmn_b   = pkmn_b
        @selected = 0

        @viewport   = Viewport.new(0, 0, Graphics.width, Graphics.height)
        @viewport.z = 99_999
        @sprites    = {}

        @typebitmap = AnimatedBitmap.new(addLanguageSuffix("Graphics/Pictures/types"))

        # ── Background ──────────────────────────────────────────────────────
        @sprites["bg"] = IconSprite.new(0, 0, @viewport)
        @sprites["bg"].setBitmap("Graphics/Pictures/Party/bg")
        @sprites["bg"].z = Z_BG

        # ── Panel windows (game window skin — handles dark/light mode) ───────
        @sprites["panel_a"] = SpriteWindow_Base.new(PANEL_A_X, PANEL_Y, PANEL_W, PANEL_H)
        @sprites["panel_a"].viewport = @viewport
        @sprites["panel_a"].z = Z_PANELS

        @sprites["panel_b"] = SpriteWindow_Base.new(PANEL_B_X, PANEL_Y, PANEL_W, PANEL_H)
        @sprites["panel_b"].viewport = @viewport
        @sprites["panel_b"].z = Z_PANELS

        # ── Pokémon front sprites ────────────────────────────────────────────
        # Sprite centre sits 70px below the content top; at zoom=1.0 a 96px sprite
        # spans cy+22..cy+118, leaving cy+122 clear for the ability/type section.
        sprite_y = PANEL_Y + CONTENT_INSET + 80
        [[@fusion_a, @pkmn_a, PANEL_A_X, "sprite_a"],
         [@fusion_b, @pkmn_b, PANEL_B_X, "sprite_b"]].each do |fusion, pkmn, px, key|
            @sprites[key] = PokemonSprite.new(@viewport)
            @sprites[key].setOffset(PictureOrigin::Center)
            @sprites[key].x      = px + PANEL_W / 2
            @sprites[key].y      = sprite_y
            @sprites[key].z      = Z_SPRITES
            @sprites[key].zoom_x = 1.0
            @sprites[key].zoom_y = 1.0
            begin
                @sprites[key].setSpeciesBitmap(fusion.id, 0, 0, false, false, false)
            rescue
                @sprites[key].setPokemonBitmap(pkmn, false)
            end
        end

        # ── Text / icon overlay (sits above everything) ───────────────────────
        @sprites["overlay"] = BitmapSprite.new(Graphics.width, Graphics.height, @viewport)
        @sprites["overlay"].z = Z_OVERLAY

        drawPanels
        pbFadeInAndShow(@sprites) { pbUpdate }
    end

    # ── Main loop ────────────────────────────────────────────────────────────

    def pbScene
        result = nil
        loop do
            Graphics.update
            Input.update
            pbUpdate

            if Input.trigger?(Input::BACK)
                pbPlayCloseMenuSE
                break
            elsif Input.trigger?(Input::LEFT) || Input.trigger?(Input::RIGHT)
                pbPlayCursorSE
                @selected = 1 - @selected
                drawPanels
            elsif Input.trigger?(Input::USE)
                result = pbHandleUse
                break unless result.nil?
            end
        end
        return result
    end

    def pbEndScene
        pbFadeOutAndHide(@sprites) { pbUpdate }
        @typebitmap&.dispose
        pbDisposeSpriteHash(@sprites)
        @viewport.dispose
    end

    # ── Drawing ──────────────────────────────────────────────────────────────

    private

    def pbUpdate
        pbUpdateSpriteHash(@sprites)
    end

    # Redraws both panels on the overlay bitmap.
    def drawPanels
        overlay = @sprites["overlay"].bitmap
        overlay.clear
        drawPanelContent(overlay, @fusion_a, PANEL_A_X, @selected == 0)
        drawPanelContent(overlay, @fusion_b, PANEL_B_X, @selected == 1)
    end

    # Draws text, type icons, and stats for one panel.
    # +fusion+    — the FusedSpecies for this panel
    # +panel_x+   — left edge of the panel window
    # +selected+  — whether this panel is currently focused
    def drawPanelContent(overlay, fusion, panel_x, selected)
        other = (fusion == @fusion_a) ? @fusion_b : @fusion_a

        # Coordinate helpers (all absolute screen positions)
        cx  = panel_x + CONTENT_INSET            # content left edge
        cy  = PANEL_Y  + CONTENT_INSET            # content top (same for both panels)
        cc  = panel_x  + PANEL_W / 2              # horizontal centre
        cr  = panel_x  + PANEL_W - CONTENT_INSET  # content right edge (for right-align)
        cw  = PANEL_W  - CONTENT_INSET * 2        # drawable width

        base   = MessageConfig.pbDefaultTextMainColor
        shadow = MessageConfig.pbDefaultTextShadowColor

        # ── Name (SystemFont, centred; gold when selected) ────────────────────
        pbSetSystemFont(overlay)
        name_base   = selected ? COLOR_GOLD        : base
        name_shadow = selected ? COLOR_GOLD_SHADOW : shadow
        pbDrawTextPositions(overlay, [[fusion.name, cc, cy - 9, 2, name_base, name_shadow]])

        # ── Abilities + type icons (cy+132 to cy+178) ────────────────────────────
        # Ability text runs in the left column; type icons are stacked vertically
        # in the right-most 64px (cr-TYPE_ICON_W to cr).
        # Dual types (28px each, no gap) fill the full 56px section height.
        # Single type is vertically centred in the 44px ability area.
        pbSetSmallFont(overlay)
        t1     = fusion.type1
        t2     = fusion.type2
        t1_num = GameData::Type.get(t1).id_number
        type_x = cr - TYPE_ICON_W
        if t1 == t2
            ty = cy + 132 + (44 - TYPE_ICON_H) / 2   # centre in 44px ability area
            overlay.blt(type_x, ty, @typebitmap.bitmap,
                        Rect.new(0, t1_num * TYPE_ICON_H, TYPE_ICON_W, TYPE_ICON_H))
        else
            t2_num = GameData::Type.get(t2).id_number
            overlay.blt(type_x, cy + 132,              @typebitmap.bitmap,
                        Rect.new(0, t1_num * TYPE_ICON_H, TYPE_ICON_W, TYPE_ICON_H))
            overlay.blt(type_x, cy + 132 + TYPE_ICON_H, @typebitmap.bitmap,
                        Rect.new(0, t2_num * TYPE_ICON_H, TYPE_ICON_W, TYPE_ICON_H))
        end
        fusion.abilities.each_with_index do |abil_id, i|
            abil_name = begin
                            GameData::Ability.get(abil_id).name
                        rescue
                            abil_id.to_s
                        end
            pbDrawTextPositions(overlay, [[abil_name, cx, cy + 132 + i * 22, 0, base, shadow]])
        end

        # ── Separator before stats ─────────────────────────────────────────────
        # Dual-type section ends at cy+188. 4px gap; separator centred at cy+180.
        overlay.fill_rect(cx, cy + 190, cw, 1, shadow)

        # ── Stats (SmallFont; y = cy+182 onwards, 20px per row) ───────────────
        total_self  = STAT_ORDER.sum { |s| fusion.base_stats[s].to_i }
        total_other = STAT_ORDER.sum { |s| other.base_stats[s].to_i }

        stat_textpos = []
        STAT_ORDER.each_with_index do |stat_id, i|
            val   = fusion.base_stats[stat_id].to_i
            oval  = other.base_stats[stat_id].to_i
            delta = val - oval
            row_y = cy + 182 + i * 20
            higher = val >= oval
            vc  = higher ? COLOR_GOLD        : base
            vs  = higher ? COLOR_GOLD_SHADOW : shadow
            stat_textpos << [STAT_LABELS[stat_id], cx,      row_y, 0, base, shadow]
            stat_textpos << [val.to_s,             cr - 50, row_y, 1, vc,   vs    ]
            if delta != 0
                delta_str = delta > 0 ? "+#{delta}" : "#{delta}"
                dc = delta > 0 ? COLOR_GOLD        : base
                ds = delta > 0 ? COLOR_GOLD_SHADOW : shadow
                stat_textpos << [delta_str, cr, row_y, 1, dc, ds]
            end
        end
        pbDrawTextPositions(overlay, stat_textpos)

        # ── Total ──────────────────────────────────────────────────────────────
        # Stats end at cy+182+5*20+20=cy+302. 4px gap; separator centred at cy+304.
        overlay.fill_rect(cx, cy + 315, cw, 1, shadow)
        total_delta = total_self - total_other
        tc = (total_self >= total_other) ? COLOR_GOLD        : base
        ts = (total_self >= total_other) ? COLOR_GOLD_SHADOW : shadow
        total_textpos = [
            [_INTL("Total"), cx,      cy + 306, 0, base, shadow],
            [total_self.to_s, cr - 50, cy + 306, 1, tc,   ts    ],
        ]
        if total_delta != 0
            total_delta_str = total_delta > 0 ? "+#{total_delta}" : "#{total_delta}"
            tdc = total_delta > 0 ? COLOR_GOLD        : base
            tds = total_delta > 0 ? COLOR_GOLD_SHADOW : shadow
            total_textpos << [total_delta_str, cr, cy + 306, 1, tdc, tds]
        end
        pbDrawTextPositions(overlay, total_textpos)
    end

    # ── Interaction ───────────────────────────────────────────────────────────

    # Shows the Fuse / View Dex / Cancel command window over the current panel.
    # Returns { fusion:, primary:, secondary: } on "Fuse", nil otherwise.
    def pbHandleUse
        current_fusion    = (@selected == 0) ? @fusion_a : @fusion_b
        current_primary   = (@selected == 0) ? @pkmn_a   : @pkmn_b
        current_secondary = (@selected == 0) ? @pkmn_b   : @pkmn_a

        pbPlayDecisionSE
        cmd = Window_CommandPokemon.new([_INTL("Fuse"), _INTL("MasterDex"), _INTL("Cancel")])
        cmd.viewport = @viewport
        cmd.z        = Z_OVERLAY + 10   # ensure it sits above the overlay
        cmd.x        = (Graphics.width  - cmd.width)  / 2
        cmd.y        = (Graphics.height - cmd.height) / 2

        choice = nil
        loop do
            Graphics.update
            Input.update
            pbUpdateSpriteHash(@sprites)
            cmd.update
            if Input.trigger?(Input::BACK)
                pbPlayCloseMenuSE
                choice = -1
                break
            elsif Input.trigger?(Input::USE)
                pbPlayDecisionSE
                choice = cmd.index
                break
            end
        end
        cmd.dispose

        case choice
        when 0  # Fuse
            return { fusion: current_fusion, primary: current_primary, secondary: current_secondary }
        when 1  # View Dex
            pbOpenDex(current_fusion)
            return nil
        else    # Cancel / BACK
            return nil
        end
    end

    # Opens the Master Dex for +fusion_species+, then redraws panels on return.
    def pbOpenDex(fusion_species)
        dex_entry = {
            species: fusion_species.id,
            data:    fusion_species,
            index:   0,
            shift:   false,
        }
        pbFadeOutIn {
            dex_scene  = PokemonPokedexInfo_Scene.new
            dex_screen = PokemonPokedexInfoScreen.new(dex_scene)
            dex_screen.pbStartScreen([dex_entry], 0, -1)
        }
        drawPanels
    end
end

# ── Helper ────────────────────────────────────────────────────────────────────

# Opens the FusionChoiceScene for pkmn_a and pkmn_b.
# Returns { fusion: FusedSpecies, primary: Pokemon, secondary: Pokemon }, or
# nil if the player cancelled.
def pbChooseFusion(pkmn_a, pkmn_b)
    fusion_ab = GameData::FusedSpecies.new(pkmn_a.species, pkmn_b.species)
    fusion_ba = GameData::FusedSpecies.new(pkmn_b.species, pkmn_a.species)

    scene = FusionChoiceScene.new
    scene.pbStartScene(fusion_ab, fusion_ba, pkmn_a, pkmn_b)
    ret = scene.pbScene
    scene.pbEndScene
    return ret
end

# On-demand fusion sprite generation and caching.
#
# The first time a fused Pokémon's sprite is needed the two component sprites
# are loaded, each positioned on a shared canvas using their battle metrics,
# and the result is saved as a PNG in a dedicated folder so future loads are
# just a file read.
#
# Split method: top half of canvas from primary, bottom half from secondary.
# Metrics centre each component on its own canvas before the halves are cut,
# so tall floating Pokémon align at the same visual midpoint as short grounded
# ones.
#
# Session caching: generated BitmapWrappers are registered in RPG::Cache
# immediately after generation so they can be loaded in the same session.
# MKXP-Z builds its filesystem path index at startup; files written at runtime
# are invisible to Bitmap.new until the next launch.  Registering in
# RPG::Cache bypasses that limitation – subsequent AnimatedBitmap.new calls
# hit the cache instead of going to disk.
#
# Cache folders (separate from normal game graphics):
#   Graphics/Pokemon/Fusions/Front/
#   Graphics/Pokemon/Fusions/Back/
#   Graphics/Pokemon/Fusions/Icons/
#   Graphics/Characters/Fusions/Followers/
#
# Filename convention mirrors the engine's own:
#   <FUSION_ID>[_<form>][_shiny].png
#   e.g. PIKACHU_CHARIZARD.png, PIKACHU_CHARIZARD_2_shiny.png

module FusionSprites
    FRONT_DIR    = "Graphics/Pokemon/Fusions/Front"
    BACK_DIR     = "Graphics/Pokemon/Fusions/Back"
    ICONS_DIR    = "Graphics/Pokemon/Fusions/Icons"
    FOLLOWER_DIR = "Graphics/Characters/Fusions/Followers"

    # Standard number of direction rows in a follower spritesheet
    # (down, left, right, up).
    FOLLOWER_ROW_COUNT = 4

    # ── Helpers ──────────────────────────────────────────────────────────────

    # Returns the cache file path (no extension) for the given parameters.
    def self.cache_path(species_id, form, dir, shiny = false)
        path  = "#{dir}/#{species_id}"
        path += "_#{form}"  if form  > 0
        path += "_shiny"    if shiny
        path
    end

    # Creates all directories in +path+ if they don't already exist.
    def self.ensure_dir(path)
        cumulative = ""
        path.split("/").each do |part|
            cumulative = cumulative.empty? ? part : "#{cumulative}/#{part}"
            Dir.mkdir(cumulative) unless File.directory?(cumulative)
        end
    end

    # Blits +src_bm+ centred on +canvas+.
    def self.blit_centered(canvas, src_bm)
        x = (canvas.width  - src_bm.width)  / 2
        y = (canvas.height - src_bm.height) / 2
        canvas.blt(x, y, src_bm, Rect.new(0, 0, src_bm.width, src_bm.height))
    end

    # Registers +bm+ in RPG::Cache under +full_path+ so AnimatedBitmap.new
    # finds it in this session without going through MKXP's path index.
    # +bm+ must be a BitmapWrapper; its never_dispose flag is set so it
    # persists for the rest of the session.
    def self.prime_session_cache(full_path, bm)
        bm.never_dispose = true
        RPG::Cache.setKey(full_path, bm)
    end

    # Composes a top-half / bottom-half fusion from two bitmaps.
    # Each bitmap is centred on a shared canvas by dimensions only; no metric
    # offsets are applied.  Battle metrics are for in-scene positioning, not
    # composition — applying them shifts content away from the visual centre
    # and produces a lopsided split.
    # Canvas is sized to the larger of the two sprites.
    # Returns a BitmapWrapper; the caller is responsible for it (do NOT
    # dispose if it has been handed to RPG::Cache).
    def self.compose_halves(prim_bm, sec_bm)
        w = [prim_bm.width,  sec_bm.width ].max
        h = [prim_bm.height, sec_bm.height].max

        prim_canvas = Bitmap.new(w, h)
        sec_canvas  = Bitmap.new(w, h)
        blit_centered(prim_canvas, prim_bm)
        blit_centered(sec_canvas,  sec_bm)

        result  = BitmapWrapper.new(w, h)
        split_y = h / 2
        result.blt(0, 0,       prim_canvas, Rect.new(0, 0,       w, split_y))
        result.blt(0, split_y, sec_canvas,  Rect.new(0, split_y, w, h - split_y))

        prim_canvas.dispose
        sec_canvas.dispose
        result
    end

    # Composes a per-row fusion for a character-set (follower) spritesheet.
    # Standard follower sheets have FOLLOWER_ROW_COUNT rows (one per facing
    # direction), each row containing animation frames.  Each row is split at
    # its vertical midpoint: top half from primary, bottom half from secondary.
    # This keeps every direction consistent rather than splitting the sheet as
    # a single image (which would make some directions show primary and others
    # show secondary depending on where the overall midpoint falls).
    # Returns a BitmapWrapper; the caller is responsible for it.
    def self.compose_follower_halves(prim_bm, sec_bm)
        w     = [prim_bm.width,  sec_bm.width ].max
        h     = [prim_bm.height, sec_bm.height].max
        row_h = h / FOLLOWER_ROW_COUNT

        result = BitmapWrapper.new(w, h)
        FOLLOWER_ROW_COUNT.times do |row|
            row_y  = row * row_h
            half_h = row_h / 2
            result.blt(0, row_y,          prim_bm, Rect.new(0, row_y,          w, half_h))
            result.blt(0, row_y + half_h, sec_bm,  Rect.new(0, row_y + half_h, w, row_h - half_h))
        end
        result
    end

    # ── Generators ───────────────────────────────────────────────────────────

    # Generates and caches the front or back battle sprite for the fusion.
    # Uses +back+ to select the back_sprite metrics and the back sprite file.
    def self.generate_battle(fusion_id, form, shiny, back)
        fusion = GameData::FusedSpecies.try_reconstruct(fusion_id, form)
        return unless fusion

        prim_sd = fusion.primary_species
        sec_sd  = fusion.secondary_species

        # Load component sprite files using the _without_fusions aliases to
        # avoid triggering our own overrides for the component species.
        file_fn = back ? :_back_sprite_filename_without_fusions \
                       : :_front_sprite_filename_without_fusions
        prim_file = GameData::Species.send(file_fn, prim_sd.species, prim_sd.form, 0, shiny)
        sec_file  = GameData::Species.send(file_fn, sec_sd.species,  sec_sd.form,  0, shiny)
        return unless prim_file && sec_file

        prim_anim = AnimatedBitmap.new(prim_file)
        sec_anim  = AnimatedBitmap.new(sec_file)

        result = compose_halves(prim_anim.bitmap, sec_anim.bitmap)

        dir       = back ? BACK_DIR : FRONT_DIR
        ensure_dir(dir)
        full_path = cache_path(fusion_id, form, dir, shiny) + ".png"
        result.to_file(full_path)
        prime_session_cache(full_path, result)
        # result is now owned by RPG::Cache; do not dispose it.

        prim_anim.dispose
        sec_anim.dispose
    end

    # Generates and caches the party/box icon for the fusion.
    # Icons are not shiny-variant aware (icons rarely differ by shininess).
    def self.generate_icon(fusion_id, form)
        fusion = GameData::FusedSpecies.try_reconstruct(fusion_id, form)
        return unless fusion

        prim_sd = fusion.primary_species
        sec_sd  = fusion.secondary_species

        prim_file = GameData::Species._icon_filename_without_fusions(prim_sd.species, prim_sd.form)
        sec_file  = GameData::Species._icon_filename_without_fusions(sec_sd.species,  sec_sd.form)
        return unless prim_file && sec_file

        # Icons are static; use AnimatedBitmap for loading consistency then
        # grab the raw Bitmap.
        prim_anim = AnimatedBitmap.new(prim_file)
        sec_anim  = AnimatedBitmap.new(sec_file)

        # No metric offsets for icons — they're small and pre-centred.
        result = compose_halves(prim_anim.bitmap, sec_anim.bitmap)

        ensure_dir(ICONS_DIR)
        full_path = cache_path(fusion_id, form, ICONS_DIR) + ".png"
        result.to_file(full_path)
        prime_session_cache(full_path, result)
        # result is now owned by RPG::Cache; do not dispose it.

        prim_anim.dispose
        sec_anim.dispose
    end

    # Generates and caches the overworld follower sprite for the fusion.
    # Follower sprites are spritesheets with FOLLOWER_ROW_COUNT rows (one per
    # facing direction) and multiple animation frames per row.  Each row is
    # split independently so all facing directions show the correct halves.
    def self.generate_follower(fusion_id, form)
        fusion = GameData::FusedSpecies.try_reconstruct(fusion_id, form)
        return unless fusion

        prim_sd = fusion.primary_species
        sec_sd  = fusion.secondary_species

        prim_file = GameData::Species._ow_sprite_filename_without_fusions(prim_sd.species, prim_sd.form)
        sec_file  = GameData::Species._ow_sprite_filename_without_fusions(sec_sd.species,  sec_sd.form)
        return unless prim_file && sec_file

        prim_anim = AnimatedBitmap.new(prim_file)
        sec_anim  = AnimatedBitmap.new(sec_file)

        result = compose_follower_halves(prim_anim.bitmap, sec_anim.bitmap)

        ensure_dir(FOLLOWER_DIR)
        full_path = cache_path(fusion_id, form, FOLLOWER_DIR) + ".png"
        result.to_file(full_path)
        prime_session_cache(full_path, result)
        # result is now owned by RPG::Cache; do not dispose it.

        prim_anim.dispose
        sec_anim.dispose
    end
end

# ── Hooks into GameData::Species filename resolution ─────────────────────────
# Each override intercepts calls for fused species (not in DATA), checks the
# cache, generates if needed, and returns the resolved path.  Regular species
# fall through to the original method immediately.
module GameData
    class Species
        class << self
            # ── Front battle sprite ─────────────────────────────────────────
            unless method_defined?(:_front_sprite_filename_without_fusions)
                alias_method :_front_sprite_filename_without_fusions, :front_sprite_filename
            end
            def front_sprite_filename(species, form = 0, gender = 0, shiny = false, shadow = false)
                return _front_sprite_filename_without_fusions(species, form, gender, shiny, shadow) if DATA.key?(species)
                path     = FusionSprites.cache_path(species, form, FusionSprites::FRONT_DIR, shiny)
                resolved = pbResolveBitmap(path)
                return resolved if resolved
                FusionSprites.generate_battle(species, form, shiny, false)
                pbResolveBitmap(path)
            end

            # ── Back battle sprite ──────────────────────────────────────────
            unless method_defined?(:_back_sprite_filename_without_fusions)
                alias_method :_back_sprite_filename_without_fusions, :back_sprite_filename
            end
            def back_sprite_filename(species, form = 0, gender = 0, shiny = false, shadow = false)
                return _back_sprite_filename_without_fusions(species, form, gender, shiny, shadow) if DATA.key?(species)
                path     = FusionSprites.cache_path(species, form, FusionSprites::BACK_DIR, shiny)
                resolved = pbResolveBitmap(path)
                return resolved if resolved
                FusionSprites.generate_battle(species, form, shiny, true)
                pbResolveBitmap(path)
            end

            # ── Party / box icon ────────────────────────────────────────────
            unless method_defined?(:_icon_filename_without_fusions)
                alias_method :_icon_filename_without_fusions, :icon_filename
            end
            def icon_filename(species, form = 0, gender = 0, shiny = false, shadow = false, egg = false)
                return _icon_filename_without_fusions(species, form, gender, shiny, shadow, egg) if DATA.key?(species) || egg
                path     = FusionSprites.cache_path(species, form, FusionSprites::ICONS_DIR)
                resolved = pbResolveBitmap(path)
                return resolved if resolved
                FusionSprites.generate_icon(species, form)
                pbResolveBitmap(path)
            end

            # ── Overworld follower sprite ───────────────────────────────────
            unless method_defined?(:_ow_sprite_filename_without_fusions)
                alias_method :_ow_sprite_filename_without_fusions, :ow_sprite_filename
            end
            def ow_sprite_filename(species, form = 0, gender = 0, shiny = false, shadow = false)
                return _ow_sprite_filename_without_fusions(species, form, gender, shiny, shadow) if DATA.key?(species)
                path     = FusionSprites.cache_path(species, form, FusionSprites::FOLLOWER_DIR)
                resolved = pbResolveBitmap(path)
                return resolved if resolved
                FusionSprites.generate_follower(species, form)
                resolved = pbResolveBitmap(path)
                return resolved if resolved
                # Fallback to the generic 000 follower if generation failed.
                _ow_sprite_filename_without_fusions(species, form, gender, shiny, shadow)
            end
        end
    end
end

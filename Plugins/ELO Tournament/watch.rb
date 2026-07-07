#==============================================================================
# ELO Tournament — replay watcher
#
# Plays back a .dat already staged into ./VSRecorder/<save name>/ (by the
# viewer app, or previously saved by saveReplay!) through the engine's own
# playRecordedBattle -- the same function behind the in-game VS Recorder's
# "Watch battle" menu item -- so it renders normally instead of through the
# no-UI benchmark scene. autoTesting/controlPlayer are restored from the
# .dat itself (PokeBattle_BattleReplayer#initialize) and deliberately left
# alone; replay doesn't re-decide anything (recorded_choices/random are
# replayed verbatim), so this is unrelated to AI/battle logic.
#
# headless_boot.rb's dispatch skips straight from SaveData.load_new_game_values
# to here, so unlike a normal title-screen boot, $game_map/$game_player/
# $MapFactory were never set up by Game.start_new/Game.load. Several spots on
# the battle-starting path (Overworld_BattleStarting.rb's time-of-day check,
# PokeBattle_Scene_Initialize.rb's backdrop day/night lookup) read $game_map
# unconditionally and crash on nil -- confirmed via errorlog.txt during
# testing. Rather than nil-guard every read site, set up just enough map
# identity for those .map_id lookups to resolve, based on the pattern in
# Game.start_new -- but deliberately skip $scene = Scene_Map.new/
# $game_map.autoplay/$game_map.update. Those are what actually run a live
# map's autorun/parallel-process events (confirmed: watching a replay this
# way played a snippet of the intro cutscene's music before crashing --
# Scene_Map#spriteset was nil, since Scene_Map#main, which normally creates
# it, is never called here). pbUpdateSceneMap/pbSceneStandby's
# `$scene.is_a?(Scene_Map)` guards skip cleanly as long as $scene is left
# alone (nil in headless mode), which is all this actually needs.
#==============================================================================
module EloTournament
    def self.ensureOverworldState!
        return if $game_map
        SaveData.load_new_game_values
        $MapFactory = PokemonMapFactory.new($data_system.start_map_id)
        $game_player.moveto($data_system.start_x, $data_system.start_y)
        $game_player.refresh
        $PokemonEncounters = PokemonEncounters.new
        $PokemonEncounters.setup($game_map.map_id)
    end

    def self.applyWatchDisplayOverrides!
        # Also read directly (not just via showAnims) by a few animations for
        # Fast-mode timing (PokeballThrowCaptureAnimation.rb,
        # BattlerDamageAnimation.rb, PokeBattle_Scene_Animations.rb), so it's
        # still worth setting even though it alone can't fix showAnims itself
        # -- see force_show_anims in watchReplay! below for why.
        $Options.battlescene = ENV["ELO_WATCH_BATTLESCENE"].to_i if ENV["ELO_WATCH_BATTLESCENE"]
        $Options.textspeed = ENV["ELO_WATCH_TEXTSPEED"].to_i if ENV["ELO_WATCH_TEXTSPEED"]
        $Options.battle_transitions = ENV["ELO_WATCH_TRANSITIONS"].to_i if ENV["ELO_WATCH_TRANSITIONS"]
        # Muting is just the volume sliders, same in-memory-only pattern as
        # the above -- no need to touch the engine's BGM-selection logic.
        $Options.bgmvolume = ENV["ELO_WATCH_BGMVOLUME"].to_i if ENV["ELO_WATCH_BGMVOLUME"]
        $Options.mevolume = ENV["ELO_WATCH_MEVOLUME"].to_i if ENV["ELO_WATCH_MEVOLUME"]
        $Options.sevolume = ENV["ELO_WATCH_SEVOLUME"].to_i if ENV["ELO_WATCH_SEVOLUME"]
        # A specific BGM track (e.g. Audio/BGM/Battle wild.ogg -> "Battle wild")
        # to play instead of whatever pbGetTrainerBattleBGM would normally
        # derive from the recorded opponent -- pbGetTrainerBattleBGM already
        # checks $PokemonGlobal.nextBattleBGM first, so this is a plain
        # existing hook (pbSetNextBattleBGM), not a new mechanism.
        pbSetNextBattleBGM(ENV["ELO_WATCH_BGM"]) if ENV["ELO_WATCH_BGM"]
    end

    def self.watchReplay!
        $current_save_file_name ||= REPLAY_SAVE_FILE_NAME
        ensureOverworldState!
        applyWatchDisplayOverrides!

        # A move/effect-level error is caught and logged by the engine's own
        # logonerr/pbCriticalCode recovery (Battle_StartAndEnd.rb) and the
        # battle then just continues/ends normally -- the same failure mode
        # tournament.rb's errorLogSize diffing already exists to catch for
        # tournament stats. Reuse it here so a swallowed crash still shows up
        # as more than an ordinary win/loss/draw.
        error_log_before = errorLogSize
        result = begin
            # AI-vs-AI recordings always carry a baked-in "noanims" rule
            # (AI_Benchmark.rb sets showAnims=false for simulation speed),
            # which otherwise permanently clobbers whatever
            # $Options.battlescene would have produced (see
            # PokeBattle_Recording.rb's playRecordedBattle). Force the
            # boolean directly rather than relying on $Options.battlescene
            # alone -- that's still set above for its separate role in a
            # few animations' Fast-mode timing, but can't survive the
            # baked-in rule clobber on its own.
            force_show_anims = ENV["ELO_WATCH_BATTLESCENE"] ? (ENV["ELO_WATCH_BATTLESCENE"].to_i != 2) : nil
            decision = playRecordedBattle(ENV["ELO_WATCH_REPLAY_NAME"], force_show_anims: force_show_anims, action_log_path: ENV["ELO_WATCH_ACTION_LOG"])
            error_log_entry = nil
            if errorLogSize > error_log_before && File.exist?(errorLogPath)
                File.open(errorLogPath, "rb") do |f|
                    f.seek(error_log_before)
                    error_log_entry = f.read
                end
            end
            { ok: true, result: decision, had_error: !error_log_entry.nil?, error_log_entry: error_log_entry }
        rescue => e
            { ok: false, error_class: e.class.name, error_message: e.message, backtrace: e.backtrace&.first(20) }
        end

        File.open("Analysis/watch_result.txt", "w") { |f| f.write(json_encode(result)) }
    end
end

#==============================================================================
# ELO Tournament — replay saver
#
# Re-runs one specific (trainer1, trainer2, format, seed) -- e.g. a row
# pulled out of results/elo_results_*.jsonl -- with recording enabled,
# producing a .dat watchable in-game via the engine's existing VS
# Recorder ("Watch battle" off the VSRECORDER item, or directly via
# playRecordedBattle("<name>")). Same seed -> same battle (the whole
# tournament already depends on this for reproducibility), so this
# doesn't need to be run during the tournament itself -- any time after,
# pointed at whichever battle turned out to be worth watching.
#
# saveBattle writes to ./VSRecorder/<save name>/, keyed off
# $current_save_file_name, which is only ever set by the real save/load
# UI -- nil in headless mode, same as everywhere else in this harness.
# Set it here so the recording actually persists instead of silently
# no-op'ing (PokeBattle_BattleRecorder#saveBattle returns early if nil).
#==============================================================================
module EloTournament
    REPLAY_SAVE_FILE_NAME = "Saves/ELOReplay.rxdata"

    def self.saveReplay!
        heuristic = AIBenchmark::HEURISTICS[AI_HEURISTIC_KEY]
        t1 = GameData::Trainer.get(ENV["ELO_REPLAY_T1_TYPE"].to_sym, ENV["ELO_REPLAY_T1_NAME"], (ENV["ELO_REPLAY_T1_VERSION"] || "0").to_i)
        t2 = GameData::Trainer.get(ENV["ELO_REPLAY_T2_TYPE"].to_sym, ENV["ELO_REPLAY_T2_NAME"], (ENV["ELO_REPLAY_T2_VERSION"] || "0").to_i)
        seed = ENV["ELO_REPLAY_SEED"].to_i
        format = ENV["ELO_REPLAY_FORMAT"] || "single"
        # Substring match, same convention as tournament.rb's BATTLE_MODE/
        # UNCURSED_RUN -- lets format carry both axes (e.g. "double_uncursed")
        # without its own dedicated branch per combination.
        battleMode = format.include?("double") ? "double" : "single"
        uncursed = format.include?("uncursed")
        outputName = (ENV["ELO_REPLAY_NAME"] || "#{trainerLabel(t1)}_vs_#{trainerLabel(t2)}_#{format}_#{seed}")
            .gsub(/[^A-Za-z0-9_.-]/, "_")

        $current_save_file_name ||= REPLAY_SAVE_FILE_NAME

        if uncursed
            applyCurseStripping!(t1)
            applyCurseStripping!(t2)
        end

        result = begin
            srand(seed)
            r = AIBenchmark.runBattle(t1, t2, heuristic, heuristic, battleMode: battleMode, saveBattle: true, backdrop: ENV["ELO_REPLAY_BACKDROP"])

            saveFileName = $current_save_file_name.split("/")[1].delete_suffix(".rxdata")
            recordsPath = "./VSRecorder/#{saveFileName}"
            lastBattlePath = "#{recordsPath}/Last battle.dat"
            destPath = "#{recordsPath}/#{outputName}.dat"
            raise "save_battle didn't produce #{lastBattlePath} -- battle may not have completed normally" unless File.exist?(lastBattlePath)
            File.rename(lastBattlePath, destPath)

            { ok: true, result: r[:result], rounds: r[:rounds], time_s: r[:time_s], saved_to: destPath, watch_with: outputName }
        rescue => e
            { ok: false, error_class: e.class.name, error_message: e.message, backtrace: e.backtrace&.first(20) }
        end

        File.open("Analysis/replay_result.txt", "w") { |f| f.write(json_encode(result)) }
    end
end

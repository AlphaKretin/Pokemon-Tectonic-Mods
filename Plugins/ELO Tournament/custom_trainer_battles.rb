#==============================================================================
# ELO Tournament — custom trainer vs. pool
#
# Loads one custom trainer (see custom_trainer.rb) and battles it against
# every eligible pool trainer (same eligibility as tournament.rb's own
# run!: buildTrainerPool's exclusions, MIN_PARTY_SIZE for the chosen
# FORMAT), reusing tournament.rb's existing FORMAT/BATTLE_MODE/
# MIN_PARTY_SIZE/UNCURSED_RUN/SHARD_INDEX/SHARD_COUNT constants and seeding
# scheme so results stay reproducible for save_replay.ps1 afterward.
#
# Identity-based resume, same principle as tournament.rb's run!: a pairing
# already present in CUSTOM_TRAINER_RESULTS_PATH is skipped rather than
# re-fought, so killing/relaunching (or a genuine crash) only loses
# whichever single battle was in flight, not everything already done in
# this shard. Unlike run!, there's no ATTEMPTING_PATH/crash-streak
# machinery -- a one-off ~70-battles-per-shard job doesn't need it, and a
# double-run of the one battle in flight when a process was killed isn't
# worth guarding against.
#==============================================================================
module EloTournament
    CUSTOM_TRAINER_RESULTS_PATH = ENV["ELO_CUSTOM_TRAINER_RESULTS_PATH"] || "Analysis/custom_trainer_results.jsonl"
    CUSTOM_TRAINER_STATUS_PATH  = ENV["ELO_CUSTOM_TRAINER_STATUS_PATH"]  || "Analysis/custom_trainer_status.json"

    def self.readCompletedCustomTrainerKeys
        keys = {}
        return keys unless File.exist?(CUSTOM_TRAINER_RESULTS_PATH)
        File.foreach(CUSTOM_TRAINER_RESULTS_PATH) do |line|
            m = line.match(/"custom":"((?:[^"\\]|\\.)*)","opponent":"((?:[^"\\]|\\.)*)","format":"([^"]*)"/)
            keys["#{m[1]}|#{m[2]}|#{m[3]}"] = true if m
        end
        keys
    end

    def self.writeCustomTrainerStatus(done, total, t_start, finished: false, error: nil)
        elapsed = Time.now - t_start
        rate = done > 0 && elapsed > 0 ? done / elapsed : nil
        remaining = total - done
        eta_s = rate && rate > 0 ? (remaining / rate).round : nil
        File.open(CUSTOM_TRAINER_STATUS_PATH, "w") { |f| f.write(json_encode({
            done: done,
            total: total,
            percent: total > 0 ? (done * 100.0 / total).round(2) : 0,
            elapsed_s: elapsed.round(1),
            rate_per_s: rate&.round(3),
            eta_s: eta_s,
            finished: finished,
            error: error,
            updated_at: Time.now.to_s,
        })) }
    end

    def self.runCustomTrainerBattles!
        heuristic = AIBenchmark::HEURISTICS[AI_HEURISTIC_KEY]
        customTd = registerCustomTrainerFromPBS!(ENV["ELO_CUSTOM_TRAINER_PBS"])
        customLabel = trainerLabel(customTd)

        pool = buildTrainerPool.select { |e| e.party_size >= MIN_PARTY_SIZE }
        # Matches tournament.rb's uncursedEdges pool-prep: stripping is a
        # confirmed no-op for cursed entries it doesn't apply to, so it's
        # safe to apply uniformly rather than re-deriving classifyCursedTrainer's
        # identical_to_base/no_change_from_original distinction here -- that
        # distinction only matters for avoiding double-counted *pairings*
        # within the full round robin, not for a custom trainer's own
        # opponent list.
        pool.each { |e| applyCurseStripping!(e.trainer_data) if e.curse } if UNCURSED_RUN

        opponents = []
        pool.each_with_index { |e, i| opponents << e if i % SHARD_COUNT == SHARD_INDEX }
        total = opponents.length

        completed = readCompletedCustomTrainerKeys
        t_start = Time.now
        # Not completed.length: see tournament.rb's run! for why this must be
        # scoped to this shard's current opponents rather than every row ever
        # written to CUSTOM_TRAINER_RESULTS_PATH.
        done = opponents.count { |entry| completed.key?("#{customLabel}|#{trainerLabel(entry.trainer_data)}|#{FORMAT}") }
        writeCustomTrainerStatus(done, total, t_start)

        opponents.each do |entry|
            opponentTd = entry.trainer_data
            key = "#{customLabel}|#{trainerLabel(opponentTd)}|#{FORMAT}"
            next if completed.key?(key)
            seed = battleSeedFromKey(key)

            error_log_before = errorLogSize
            srand(seed)
            result = AIBenchmark.runBattle(customTd, opponentTd, heuristic, heuristic, battleMode: BATTLE_MODE)
            had_error = errorLogSize > error_log_before

            File.open(CUSTOM_TRAINER_RESULTS_PATH, "a") { |f| f.puts(json_encode({
                custom: customLabel,
                opponent: trainerLabel(opponentTd),
                format: FORMAT.to_s,
                seed: seed,
                result: result[:result],
                rounds: result[:rounds],
                time_s: result[:time_s],
                had_error: had_error,
            })) }
            completed[key] = true
            done += 1
            writeCustomTrainerStatus(done, total, t_start, finished: (done >= total))
        end
    rescue => e
        pbPrintException(e) rescue nil
        File.open(CUSTOM_TRAINER_RESULTS_PATH, "a") { |f| f.puts(json_encode({
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace&.first(20),
        })) }
        writeCustomTrainerStatus(0, 0, Time.now, error: { error_class: e.class.name, error_message: e.message })
    end
end

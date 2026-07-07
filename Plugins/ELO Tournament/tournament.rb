#==============================================================================
# ELO Tournament — orchestration
#
# Runs every ordered pair from the trainer pool through AIBenchmark.runBattle,
# streaming one JSON line per battle to disk. Designed to survive being
# interrupted (or crashing) and re-run: resumption is identity-based (skip
# any pairing that already has a result row), not position-based, so it's
# robust to the pairing list or pool changing between runs.
#
# Two distinct failure modes were found in practice and are both handled:
#  - A move effect can hit a recoverable error (engine's logonerr/
#    pbCriticalCode machinery logs it to errorlog.txt and lets the battle
#    continue) -- the battle "succeeds" but its outcome may be corrupted.
#    Detected per-battle by diffing errorlog.txt's size around the call.
#  - A small minority of battles trigger a SystemStackError (likely
#    unbounded-depth recursion somewhere in AI evaluation, not yet root-
#    caused) that unwinds straight out of this method, past any rescue here,
#    aborting the whole process. Not reliably reproducible per pairing
#    (observed both crashing and succeeding for what should be the same
#    seeded battle), so retried on resume rather than assumed permanent --
#    but to avoid an infinite crash loop if a specific pairing genuinely
#    always crashes, repeated failures on the same pairing get skipped
#    (recorded, not silently dropped) after a threshold.
#==============================================================================
module EloTournament
    RESULTS_PATH       = ENV["ELO_RESULTS_PATH"]       || "Analysis/elo_results.jsonl"
    STATUS_PATH         = ENV["ELO_STATUS_PATH"]         || "Analysis/elo_status.json"
    ATTEMPTING_PATH     = ENV["ELO_ATTEMPTING_PATH"]     || "Analysis/elo_attempting.json"
    CRASH_STREAK_PATH   = ENV["ELO_CRASH_STREAK_PATH"]   || "Analysis/elo_crash_streaks.txt"
    AI_HEURISTIC_KEY    = (ENV["ELO_AI_HEURISTIC"] || "baseline").to_sym
    PROGRESS_INTERVAL   = (ENV["ELO_PROGRESS_INTERVAL"] || "25").to_i
    FORMAT               = (ENV["ELO_FORMAT"] || "singles").to_sym
    BATTLE_LIMIT         = ENV["ELO_BATTLE_LIMIT"] ? ENV["ELO_BATTLE_LIMIT"].to_i : nil
    CRASH_THRESHOLD      = (ENV["ELO_CRASH_THRESHOLD"] || "3").to_i

    # Maps our FORMAT token to the string PokeBattle_Battle#setBattleMode
    # expects. Anything not recognized there (including "singles") falls
    # through to its own default of 1v1, which is what we want anyway.
    # Substring match (not exact :doubles) so any doubles-flavored format
    # (e.g. :doubles_uncursed) gets 2v2 without needing its own branch.
    BATTLE_MODE = FORMAT.to_s.include?("double") ? "double" : "single"
    MIN_PARTY_SIZE = FORMAT.to_s.include?("double") ? 2 : 1

    # The curse-stripped tournament format: every cursed trainer (except
    # those excluded by curse_stripping.rb's classifyCursedTrainer -- see
    # uncursedEdges below) battles with curse effects removed, but genuine
    # non-curse team differences from their ExtendsVersion base kept.
    UNCURSED_RUN = FORMAT.to_s.include?("uncursed")

    # Sharding splits the full pairing list across multiple concurrent
    # Game.exe processes (one per shard), each with its own RESULTS_PATH/
    # STATUS_PATH/etc set by the launcher, so they never write to the same
    # files. The modulo split is a deterministic, exhaustive partition --
    # no two shards (run with the same SHARD_COUNT) ever attempt the same
    # pairing, so there's no need to cross-check other shards' results.
    SHARD_INDEX = (ENV["ELO_SHARD_INDEX"] || "0").to_i
    SHARD_COUNT = (ENV["ELO_SHARD_COUNT"] || "1").to_i

    # Restricts buildPairs' edges to only pairings touching at least one of
    # these trainer labels (e.g. "POKEMONMASTER_Vanya:Vanya#3") -- for
    # rerunning just the pairings affected by a specific trainer/behavior
    # fix across this format's full pool, without re-fighting everything.
    # Applied as a filter *after* each format's own normal pool-prep (curse
    # stripping, identical_to_base exclusion, sampling, etc. -- see
    # buildPairs), so it works identically regardless of format, and the
    # launcher is expected to point RESULTS_PATH/etc at a distinctly-named
    # file (not the format's own full-round-robin file) since this produces
    # a small partial result set, not a complete one -- see
    # analysis/apply_subset_rerun.py, which splices these results back into
    # the real per-format files afterward.
    SUBSET_TRAINER_LABELS = ENV["ELO_SUBSET_TRAINER_LABELS"] ? ENV["ELO_SUBSET_TRAINER_LABELS"].split(",").map(&:strip) : nil

    def self.run!
        heuristic = AIBenchmark::HEURISTICS[AI_HEURISTIC_KEY]
        raise "Unknown heuristic #{AI_HEURISTIC_KEY.inspect}" unless heuristic

        pool = buildTrainerPool
        all_pairs = buildPairs(pool)
        # The full pre-shard-split count, for watch scripts to use as a
        # stable denominator -- unlike `total` (this shard's own slice),
        # global_total is the same value across every shard/chunk of this
        # format, so it's known as soon as any one of them checkpoints,
        # instead of only being inferable once every shard has started.
        global_total = all_pairs.length
        pairs = []
        all_pairs.each_with_index { |pair, i| pairs << pair if i % SHARD_COUNT == SHARD_INDEX }
        total = pairs.length

        completed = readCompletedKeys
        recordDanglingCrashIfAny(completed)

        t_start = Time.now
        ran     = 0
        # Not completed.length: RESULTS_PATH accumulates indefinitely across
        # sessions (see module comment), so it can hold rows for pairings no
        # longer in this shard's current `pairs` (pool/pairing composition
        # changed between runs). done must be scoped to this run's own pairs,
        # or it silently drifts from total.
        done    = pairs.count { |(e1, e2)| completed.key?(pairKey(e1.trainer_data, e2.trainer_data)) }

        pairs.each do |(e1, e2)|
            break if BATTLE_LIMIT && ran >= BATTLE_LIMIT

            t1, t2 = e1.trainer_data, e2.trainer_data
            key    = pairKey(t1, t2)
            next if completed.key?(key)

            seed = battleSeedFromKey(key)
            writeAttempting(t1, t2, key, seed)

            error_log_before = errorLogSize
            srand(seed)
            result = AIBenchmark.runBattle(t1, t2, heuristic, heuristic, battleMode: BATTLE_MODE)
            had_error = errorLogSize > error_log_before

            appendResult({
                trainer1: trainerLabel(t1),
                trainer2: trainerLabel(t2),
                format: FORMAT.to_s,
                seed: seed,
                result: result[:result],
                rounds: result[:rounds],
                time_s: result[:time_s],
                had_error: had_error,
                curse: e1.curse || e2.curse,
            })
            clearCrashStreak(key)

            completed[key] = true
            done += 1
            ran  += 1
            writeStatus(done, total, t_start, ran, global_total: global_total) if ran % PROGRESS_INTERVAL == 0
        end

        writeStatus(done, total, t_start, ran, finished: (done >= total), global_total: global_total)
    rescue => e
        pbPrintException(e) rescue nil
        writeStatus(done || 0, total || 0, t_start || Time.now, ran || 0, global_total: global_total || 0, error: {
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace&.first(20),
        })
    end

    # Set to sample sparse, roughly-even-degree matchups instead of a full
    # round robin -- e.g. for a fast prototype pass across the whole
    # roster while a full round robin's cost is evaluated separately. nil
    # (default) keeps the full round robin.
    SAMPLE_GAMES_PER_TRAINER = ENV["ELO_SAMPLE_GAMES_PER_TRAINER"] ? ENV["ELO_SAMPLE_GAMES_PER_TRAINER"].to_i : nil
    SAMPLE_SEED = (ENV["ELO_SAMPLE_SEED"] || "1").to_i

    def self.buildPairs(pool)
        eligible = pool.select { |e| e.party_size >= MIN_PARTY_SIZE }
        edges = if UNCURSED_RUN
            uncursedEdges(eligible)
        elsif SAMPLE_GAMES_PER_TRAINER
            sampledEdges(eligible, SAMPLE_GAMES_PER_TRAINER, SAMPLE_SEED)
        else
            allEdges(eligible)
        end
        edges = filterToSubsetTrainers(edges) if SUBSET_TRAINER_LABELS
        edges.flat_map { |e1, e2| pairsForEdge(e1, e2) }
    end

    # See SUBSET_TRAINER_LABELS above. Applied after the format-specific
    # edge builder above, not folded into each of them, so a subset rerun
    # always sees exactly the same pool/edges a full run of that format
    # would have produced, just narrowed down afterward.
    def self.filterToSubsetTrainers(edges)
        labels = {}
        SUBSET_TRAINER_LABELS.each { |l| labels[l] = true }
        edges.select { |e1, e2| labels[trainerLabel(e1.trainer_data)] || labels[trainerLabel(e2.trainer_data)] }
    end

    # Pairing for the curse-stripped format. Classifies every cursed pool
    # entry (curse_stripping.rb's classifyCursedTrainer):
    # - identical_to_base: excluded from the pool entirely -- not a
    #   combatant, not an opponent. Their stripped team duplicates an
    #   already-complete pool member (their base), so including them would
    #   just double-count that opponent for everyone else.
    # - no_change_from_original: stays in the pool as a valid opponent (curse
    #   stripping is a no-op for them, so their existing curse-flagged
    #   battles are already correct), but doesn't by itself trigger a new
    #   pairing -- a pairing is only fresh if the OTHER side's team actually
    #   changed too.
    # - everything else: needs fresh battles against the whole (excluded-
    #   trimmed) pool, since their stripped team genuinely differs.
    # A pairing is included here only if at least one side is in that last
    # "needs fresh battles" group -- pairs where neither side's team changed
    # are left out entirely; the existing result row already covers them
    # (see analysis-side composite-format assembly).
    def self.uncursedEdges(eligible)
        classifications = {}
        eligible.each do |e|
            next unless e.curse
            classifications[e] = classifyCursedTrainer(e.trainer_data)
        end

        pool = eligible.reject { |e| classifications[e] && classifications[e][:identical_to_base] }
        needsFresh = {}
        pool.each do |e|
            c = classifications[e]
            needsFresh[e] = true if c && !c[:identical_to_base] && !c[:no_change_from_original]
        end

        # Stripping is applied once per unique trainer here (not per-pair --
        # the same GameData::Trainer instance is shared across every pairing
        # it appears in, so redefining its singleton to_trainer repeatedly
        # would just be redundant work). Safe to apply uniformly to every
        # non-excluded cursed entry, including no_change_from_original ones,
        # since stripping is a confirmed no-op for those.
        pool.each { |e| applyCurseStripping!(e.trainer_data) if e.curse }

        edges = []
        pool.each_with_index do |e1, i|
            pool.each_with_index do |e2, j|
                next if j <= i
                next unless needsFresh[e1] || needsFresh[e2]
                edges << [e1, e2]
            end
        end
        edges
    end

    # Curses (CURSE_* policies) now apply to whichever side actually holds
    # the policy, not just whichever trainer is passed as the battle's
    # "opponent" slot (see Battle_StartAndEnd.rb's curse-application loop,
    # which walks both @player and @opponent) -- so direction no longer
    # matters for any pairing, cursed or not: one battle now exercises
    # every curse present regardless of which trainer is e1 vs e2.
    def self.pairsForEdge(e1, e2)
        [[e1, e2]]
    end

    def self.allEdges(eligible)
        edges = []
        eligible.each_with_index do |e1, i|
            eligible.each_with_index do |e2, j|
                next if j <= i
                edges << [e1, e2]
            end
        end
        edges
    end

    # Configuration-model-style random graph: give every trainer
    # gamesPerTrainer "stubs", shuffle all stubs together, pair up
    # consecutive stubs into edges. Self-pairs and repeats of an already-
    # sampled pair are dropped rather than retried, which costs a small
    # amount of degree from whoever's involved rather than introducing
    # any systematic bias toward a particular trainer. Deterministic for
    # a given (pool order, gamesPerTrainer, seed), matching the rest of
    # this file's identity-based resumability.
    def self.sampledEdges(eligible, gamesPerTrainer, seed)
        rng = Random.new(seed)
        stubs = []
        eligible.each_index { |i| gamesPerTrainer.times { stubs << i } }
        stubs.shuffle!(random: rng)

        seenPairs = {}
        edges = []
        (0...(stubs.length - 1)).step(2) do |i|
            a, b = stubs[i], stubs[i + 1]
            next if a == b
            key = a < b ? [a, b] : [b, a]
            next if seenPairs[key]
            seenPairs[key] = true
            edges << [eligible[a], eligible[b]]
        end
        edges
    end

    def self.pairKey(t1, t2)
        "#{trainerLabel(t1)}|#{trainerLabel(t2)}|#{FORMAT}"
    end

    # Deterministic, content-derived (not list-position-derived) so it stays
    # stable for a given matchup even if the pool/pairing order shifts later,
    # and so a battle can be exactly replayed later from just its identifiers.
    def self.battleSeedFromKey(key)
        key.bytes.reduce(5381) { |h, b| ((h << 5) + h) ^ b } & 0xFFFFFFFF
    end

    # Identity-based resume: every key that already has a result row is done,
    # regardless of where it sits in the (re-derivable) pairing order.
    def self.readCompletedKeys
        keys = {}
        return keys unless File.exist?(RESULTS_PATH)
        File.foreach(RESULTS_PATH) do |line|
            m = line.match(/"trainer1":"((?:[^"\\]|\\.)*)","trainer2":"((?:[^"\\]|\\.)*)","format":"([^"]*)"/)
            keys["#{m[1]}|#{m[2]}|#{m[3]}"] = true if m
        end
        keys
    end

    # If the previous process died mid-battle, ATTEMPTING_PATH names a pairing
    # that never got a result row. Track consecutive failures per pairing and
    # give up on (but still record) one that keeps taking the whole process
    # down with it, instead of retrying it forever.
    def self.recordDanglingCrashIfAny(completed)
        return unless File.exist?(ATTEMPTING_PATH)
        content = File.read(ATTEMPTING_PATH)
        m = content.match(/"trainer1":"((?:[^"\\]|\\.)*)","trainer2":"((?:[^"\\]|\\.)*)","format":"([^"]*)","seed":(\d+)/)
        return unless m
        key  = "#{m[1]}|#{m[2]}|#{m[3]}"
        seed = m[4].to_i
        return if completed.key?(key)

        streaks = readCrashStreaks
        streaks[key] = (streaks[key] || 0) + 1
        if streaks[key] >= CRASH_THRESHOLD
            appendResult({
                trainer1: m[1], trainer2: m[2], format: m[3], seed: seed,
                result: nil, rounds: nil, time_s: nil,
                had_error: true, skipped: true,
                skip_reason: "process crashed on this pairing #{streaks[key]} times in a row",
            })
            completed[key] = true
            streaks.delete(key)
        end
        writeCrashStreaks(streaks)
    end

    def self.readCrashStreaks
        streaks = {}
        return streaks unless File.exist?(CRASH_STREAK_PATH)
        File.foreach(CRASH_STREAK_PATH) do |line|
            key, count = line.strip.split("\t")
            streaks[key] = count.to_i if key
        end
        streaks
    end

    def self.writeCrashStreaks(streaks)
        File.open(CRASH_STREAK_PATH, "w") do |f|
            streaks.each { |key, count| f.puts("#{key}\t#{count}") }
        end
    end

    def self.clearCrashStreak(key)
        streaks = readCrashStreaks
        return unless streaks.delete(key)
        writeCrashStreaks(streaks)
    end

    def self.errorLogPath
        return @error_log_path if @error_log_path
        @error_log_path = (defined?(RTP) ? RTP.getSaveFileName("errorlog.txt") : "errorlog.txt")
    end

    def self.errorLogSize
        File.exist?(errorLogPath) ? File.size(errorLogPath) : 0
    end

    def self.appendResult(data)
        File.open(RESULTS_PATH, "a") { |f| f.puts(json_encode(data)) }
    end

    # Written immediately before each battle and never explicitly cleared, so
    # if the process dies mid-battle without raising a catchable exception,
    # this file says exactly which pairing was in flight.
    def self.writeAttempting(t1, t2, key, seed)
        File.open(ATTEMPTING_PATH, "w") { |f| f.write(json_encode({
            trainer1: trainerLabel(t1),
            trainer2: trainerLabel(t2),
            format: FORMAT.to_s,
            seed: seed,
        })) }
    end

    def self.writeStatus(done, total, t_start, ran, finished: false, error: nil, global_total: nil)
        elapsed = Time.now - t_start
        rate = ran > 0 && elapsed > 0 ? ran / elapsed : nil
        remaining = total - done
        eta_s = rate && rate > 0 ? (remaining / rate).round : nil

        File.open(STATUS_PATH, "w") { |f| f.write(json_encode({
            done: done,
            total: total,
            # Same value across every shard/chunk of this format (the full
            # pairing count before the SHARD_COUNT split) -- watch scripts
            # should use this, not a sum of every shard's own `total`, as
            # the denominator for a format's real progress.
            global_total: global_total || total,
            percent: total > 0 ? (done * 100.0 / total).round(2) : 0,
            elapsed_s: elapsed.round(1),
            rate_per_s: rate&.round(3),
            eta_s: eta_s,
            finished: finished,
            error: error,
            updated_at: Time.now.to_s,
        })) }
    end

    # mkxp-z's embedded Ruby doesn't ship the json stdlib, so this is a small
    # hand-rolled encoder for the flat-ish data (strings/numbers/bools/nil,
    # arrays, hashes) the tournament actually needs to serialize.
    def self.json_encode(obj)
        case obj
        when Hash
            "{" + obj.map { |k, v| "#{json_encode(k.to_s)}:#{json_encode(v)}" }.join(",") + "}"
        when Array
            "[" + obj.map { |v| json_encode(v) }.join(",") + "]"
        when Symbol
            json_encode(obj.to_s)
        when String
            '"' + obj.gsub('\\', '\\\\').gsub('"', '\"').gsub("\n", '\n').gsub("\r", '\r').gsub("\t", '\t') + '"'
        when Integer, Float
            obj.to_s
        when true, false
            obj.to_s
        when nil
            "null"
        else
            json_encode(obj.to_s)
        end
    end

    # Bisection helper for testSinglePairing! (ELO_TEST_T*_PARTY_INDICES):
    # overrides this *specific* GameData::Trainer record's to_trainer to
    # trim the resolved party down to just the given 0-based indices.
    # AIBenchmark.runBattle takes the raw GameData::Trainer and calls
    # to_trainer internally, so trimming has to happen at that level, not
    # by pre-converting and passing an NPCTrainer in (it wants the raw
    # record, see feedback-elo-tournament-test-harness). A singleton method
    # on just this td instance, not a class-level patch, so it can't affect
    # any other lookup of the same trainer within the process.
    def self.trimPartyByIndices!(td, indices_env)
        return unless indices_env
        indices = indices_env.split(",").map(&:to_i)
        td.define_singleton_method(:to_trainer) do
            trainer = super()
            trainer.party = trainer.party.values_at(*indices)
            trainer
        end
    end

    # Temporary, one-off diagnostic: run exactly one specific pairing by
    # explicit identity (no pool scanning, so no risk of accidentally
    # running more than one battle) and record whatever happens. Identity
    # and seed come from env vars so this can be pointed at whichever
    # pairing is currently under investigation without editing code.
    # Not part of the regular tournament flow -- remove once done.
    def self.testSinglePairing!
        heuristic = AIBenchmark::HEURISTICS[AI_HEURISTIC_KEY]
        t1 = GameData::Trainer.get(ENV["ELO_TEST_T1_TYPE"].to_sym, ENV["ELO_TEST_T1_NAME"], (ENV["ELO_TEST_T1_VERSION"] || "0").to_i)
        t2 = GameData::Trainer.get(ENV["ELO_TEST_T2_TYPE"].to_sym, ENV["ELO_TEST_T2_NAME"], (ENV["ELO_TEST_T2_VERSION"] || "0").to_i)
        trimPartyByIndices!(t1, ENV["ELO_TEST_T1_PARTY_INDICES"])
        trimPartyByIndices!(t2, ENV["ELO_TEST_T2_PARTY_INDICES"])
        seed = ENV["ELO_TEST_SEED"].to_i

        if ENV["ELO_TEST_PREBATTLE_ONLY"]
            srand(seed)
            File.open("Analysis/single_pairing_test.txt", "w") { |f| f.write(json_encode({
                pre_battle_t1_species: t1.to_trainer.party.map { |p| p.species.to_s },
                pre_battle_t2_species: t2.to_trainer.party.map { |p| p.species.to_s },
            })) }
            return
        end

        result = begin
            error_log_before = errorLogSize
            srand(seed)
            r = AIBenchmark.runBattle(t1, t2, heuristic, heuristic, battleMode: ENV["ELO_TEST_FORMAT"] || "single")
            { ok: true, had_error: errorLogSize > error_log_before, result: r[:result], rounds: r[:rounds], time_s: r[:time_s] }
        rescue => e
            { ok: false, error_class: e.class.name, error_message: e.message, backtrace: e.backtrace&.first(60) }
        end

        File.open("Analysis/single_pairing_test.txt", "w") { |f| f.write(json_encode(result)) }
    end

    # Same diagnostic purpose as testSinglePairing!, but for running many
    # pairings without paying a fresh Game.exe boot + Plugin recompile per
    # pairing -- that per-launch overhead dominated wall-clock time once
    # ad hoc calibration/regression batches grew past a handful of battles.
    # Manifest is a tab-separated file (one pairing per line: t1Type, t1Name,
    # t1Version, t2Type, t2Name, t2Version, seed, format), path given via
    # ELO_TEST_BATCH_PAIRINGS. Results stream to
    # Analysis/batch_pairing_results.jsonl (truncated at the start of the
    # run, then appended one line per pairing so partial progress survives
    # if a later pairing hangs or crashes the process).
    def self.testBatchPairings!
        heuristic = AIBenchmark::HEURISTICS[AI_HEURISTIC_KEY]
        outputPath = "Analysis/batch_pairing_results.jsonl"
        File.open(outputPath, "w") {}

        File.readlines(ENV["ELO_TEST_BATCH_PAIRINGS"]).each do |line|
            line = line.strip
            next if line.empty? || line.start_with?("#")
            t1Type, t1Name, t1Version, t2Type, t2Name, t2Version, seed, format = line.split("\t")
            t1Label = "#{t1Type}:#{t1Name}##{t1Version}"
            t2Label = "#{t2Type}:#{t2Name}##{t2Version}"

            # GameData::Trainer.get (a bad/missing name+version in the
            # manifest) belongs in the same rescue as the battle itself --
            # it's a per-row failure, not a reason to abort every remaining
            # pairing in the batch.
            row = begin
                t1 = GameData::Trainer.get(t1Type.to_sym, t1Name, t1Version.to_i)
                t2 = GameData::Trainer.get(t2Type.to_sym, t2Name, t2Version.to_i)
                error_log_before = errorLogSize
                srand(seed.to_i)
                r = AIBenchmark.runBattle(t1, t2, heuristic, heuristic, battleMode: format)
                { ok: true, t1: t1Label, t2: t2Label, seed: seed.to_i, format: format,
                  had_error: errorLogSize > error_log_before, result: r[:result], rounds: r[:rounds], time_s: r[:time_s] }
            rescue => e
                { ok: false, t1: t1Label, t2: t2Label, seed: seed.to_i, format: format,
                  error_class: e.class.name, error_message: e.message }
            end
            File.open(outputPath, "a") { |f| f.puts(json_encode(row)) }
        end
    end
end

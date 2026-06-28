#==============================================================================
# ELO Tournament — top-16 seeded elimination bracket
#
# Exhibition feature, separate from the rating data itself: takes the top 16
# trainers out of a finished (or in-progress) ratings_<format>.json --
# converted to a plain seed list by analysis/bracket_seeds.py, since this
# runs inside mkxp-z's embedded Ruby, which doesn't ship a JSON parser (see
# tournament.rb) -- and plays a standard seeded single-elimination bracket
# over them, saving a replay (.dat) of every match.
#
# Every match is a *fresh* battle, even if that exact pairing already has a
# row in the sparse round-robin results: the bracket is a showcase, not more
# rating data, and most top-16 pairs won't have met anyway (sparse sampling
# covers a small fraction of all pairs).
#
# Resumable the same way as tournament.rb: each decided match is appended to
# BRACKET_RESULTS_PATH as soon as it's decided, keyed by (round, match), so a
# crash/restart resumes mid-bracket instead of re-fighting earlier rounds.
# Plain tab-separated rows rather than hand-rolled JSON, for the same reason
# CRASH_STREAK_PATH (tournament.rb) is TSV: trivial to parse back out
# without writing a real JSON parser.
#==============================================================================
module EloTournament
    BRACKET_SEEDS_PATH   = ENV["ELO_BRACKET_SEEDS_PATH"]   || "Analysis/bracket_seeds.txt"
    BRACKET_RESULTS_PATH = ENV["ELO_BRACKET_RESULTS_PATH"] || "Analysis/bracket_results.tsv"
    BRACKET_STATUS_PATH  = ENV["ELO_BRACKET_STATUS_PATH"]  || "Analysis/bracket_status.json"
    BRACKET_SAVE_FILE_NAME = "Saves/EloBracket.rxdata"
    # Anything other than a clean win/loss (draw, or every reroll attempt
    # erroring out) gets this many extra attempts with a different seed
    # before falling back to a tiebreak -- see runBracketMatch.
    BRACKET_MAX_REROLLS  = (ENV["ELO_BRACKET_MAX_REROLLS"] || "5").to_i
    # "single"/"double", matching PokeBattle_Battle#setBattleMode -- separate
    # from tournament.rb's FORMAT/BATTLE_MODE since a bracket run never
    # touches the round-robin pairing logic those drive.
    BRACKET_FORMAT       = ENV["ELO_BRACKET_FORMAT"] || "single"

    # Standard 16-slot single-elimination seeding order (NCAA-style: 1v16,
    # 8v9, 5v12, 4v13, 3v14, 6v11, 7v10, 2v15) -- keeps the top seeds apart
    # for as long as possible. Pairing consecutive slots each round and
    # advancing the winner into the same slot naturally reproduces the full
    # bracket (quarterfinals get 1/16's winner vs 8/9's winner, etc.)
    # without needing to special-case later rounds.
    SEED_ORDER_16 = [1, 16, 8, 9, 5, 12, 4, 13, 3, 14, 6, 11, 7, 10, 2, 15].freeze
    ROUND_NAMES   = ["Round of 16", "Quarterfinals", "Semifinals", "Final"].freeze

    BracketSlot = Struct.new(:seed, :trainer_label)

    BRACKET_RESULT_FIELDS = [
        :round, :round_name, :match,
        :seed1, :trainer1, :seed2, :trainer2,
        :winner_seed, :winner, :loser_seed, :loser,
        :result, :rounds, :time_s, :had_error, :attempts, :decided_by, :replay_path,
    ].freeze

    def self.runBracket!
        seeds = readBracketSeeds
        expected = SEED_ORDER_16.length
        raise "Need exactly #{expected} seeds in #{BRACKET_SEEDS_PATH}, got #{seeds.length}" unless seeds.length == expected

        bySeed = {}
        seeds.each { |s| bySeed[s.seed] = s }
        roundEntries = SEED_ORDER_16.map { |n| bySeed[n] or raise "Missing seed ##{n} in #{BRACKET_SEEDS_PATH}" }

        decided = readDecidedMatches
        totalMatches = expected - 1
        doneCount = decided.length
        t_start = Time.now

        roundIndex = 0
        while roundEntries.length > 1
            roundName = ROUND_NAMES[roundIndex] || "Round #{roundIndex + 1}"
            winners = []
            roundEntries.each_slice(2).to_a.each_with_index do |(a, b), matchIndex|
                row = decided[[roundIndex, matchIndex]]
                if row
                    winners << BracketSlot.new(row[:winner_seed].to_i, row[:winner])
                    next
                end
                winnerEntry = runBracketMatch(roundIndex, roundName, matchIndex, a, b)
                winners << winnerEntry
                doneCount += 1
                writeBracketStatus(doneCount, totalMatches, t_start, roundName)
            end
            roundEntries = winners
            roundIndex += 1
        end

        champion = roundEntries.first
        writeBracketStatus(doneCount, totalMatches, t_start, "Final", finished: true, champion: champion.trainer_label)
    rescue => e
        pbPrintException(e) rescue nil
        writeBracketStatus(doneCount || 0, totalMatches || (SEED_ORDER_16.length - 1), t_start || Time.now, "error", error: {
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace&.first(20),
        })
    end

    # Runs one bracket match, rerolling the seed on a non-decisive outcome
    # (draw, or a battle that ended some other way) up to BRACKET_MAX_REROLLS
    # times. If it's still not decisive after that -- plain Bradley-Terry
    # doesn't even model draws, so this should be rare -- the better seed
    # advances rather than stalling the bracket indefinitely; decided_by in
    # the result row records which happened.
    def self.runBracketMatch(roundIndex, roundName, matchIndex, a, b)
        t1 = parseTrainerLabel(a.trainer_label)
        t2 = parseTrainerLabel(b.trainer_label)
        matchKey = "bracket|r#{roundIndex}|m#{matchIndex}|#{a.trainer_label}|#{b.trainer_label}"

        attempt = 0
        battle = nil
        loop do
            seed = battleSeedFromKey("#{matchKey}|attempt#{attempt}")
            slug = bracketReplaySlug(roundIndex, matchIndex, a, b, attempt)
            battle = runBracketBattle(t1, t2, seed, slug)
            break if [1, 2].include?(battle[:result]) || attempt >= BRACKET_MAX_REROLLS
            attempt += 1
        end

        decisive = [1, 2].include?(battle[:result])
        winnerEntry, loserEntry =
            if !decisive
                a.seed < b.seed ? [a, b] : [b, a]
            elsif battle[:result] == 1
                [a, b]
            else
                [b, a]
            end

        appendBracketResult({
            round: roundIndex + 1, round_name: roundName, match: matchIndex + 1,
            seed1: a.seed, trainer1: a.trainer_label,
            seed2: b.seed, trainer2: b.trainer_label,
            winner_seed: winnerEntry.seed, winner: winnerEntry.trainer_label,
            loser_seed: loserEntry.seed, loser: loserEntry.trainer_label,
            result: battle[:result], rounds: battle[:rounds], time_s: battle[:time_s],
            had_error: battle[:had_error], attempts: attempt + 1,
            decided_by: decisive ? "battle" : "seed_tiebreak",
            replay_path: battle[:replay_path],
        })

        winnerEntry
    end

    # Same save/rename dance as replay.rb's saveReplay!, just looped over
    # many matches in one process instead of one-off from env vars, and
    # always with saveBattle: true since the whole point is the replay.
    def self.runBracketBattle(t1, t2, seed, slug)
        heuristic = AIBenchmark::HEURISTICS[AI_HEURISTIC_KEY]
        $current_save_file_name ||= BRACKET_SAVE_FILE_NAME

        writeAttempting(t1, t2, "bracket:#{slug}", seed)
        error_log_before = errorLogSize
        srand(seed)
        r = AIBenchmark.runBattle(t1, t2, heuristic, heuristic, battleMode: BRACKET_FORMAT, saveBattle: true)
        had_error = errorLogSize > error_log_before

        saveFileName   = $current_save_file_name.split("/")[1].delete_suffix(".rxdata")
        recordsPath    = "./VSRecorder/#{saveFileName}"
        lastBattlePath = "#{recordsPath}/Last battle.dat"
        replay_path    = nil
        if File.exist?(lastBattlePath)
            destPath = "#{recordsPath}/#{slug}.dat"
            File.rename(lastBattlePath, destPath)
            replay_path = destPath
        end

        { result: r[:result], rounds: r[:rounds], time_s: r[:time_s], had_error: had_error, replay_path: replay_path }
    end

    def self.bracketReplaySlug(roundIndex, matchIndex, a, b, attempt)
        slug = "r#{roundIndex + 1}m#{matchIndex + 1}_seed#{a.seed}-#{slugifyLabel(a.trainer_label)}" \
               "_vs_seed#{b.seed}-#{slugifyLabel(b.trainer_label)}"
        slug += "_attempt#{attempt}" if attempt > 0
        slug
    end

    def self.slugifyLabel(label)
        label.gsub(/[^A-Za-z0-9_.-]/, "_")
    end

    # Inverse of trainer_pool.rb's trainerLabel: "TYPE:Name" or
    # "TYPE:Name#version" (version omitted entirely when 0).
    def self.parseTrainerLabel(label)
        type_str, rest = label.split(":", 2)
        if rest =~ /\A(.*)#(\d+)\z/
            name, version = $1, $2.to_i
        else
            name, version = rest, 0
        end
        GameData::Trainer.get(type_str.to_sym, name, version)
    end

    # seed<TAB>trainer_label<TAB>rating(ignored), one line per entrant, blank
    # lines and #-comments skipped. Written by analysis/bracket_seeds.py.
    def self.readBracketSeeds
        raise "Bracket seeds file not found: #{BRACKET_SEEDS_PATH} (run analysis/bracket_seeds.py first)" unless File.exist?(BRACKET_SEEDS_PATH)
        seeds = []
        File.foreach(BRACKET_SEEDS_PATH) do |line|
            line = line.strip
            next if line.empty? || line.start_with?("#")
            seedNum, label = line.split("\t", 3)
            seeds << BracketSlot.new(seedNum.to_i, label)
        end
        seeds
    end

    def self.appendBracketResult(row)
        line = BRACKET_RESULT_FIELDS.map { |f| row[f].to_s }.join("\t")
        File.open(BRACKET_RESULTS_PATH, "a") { |f| f.puts(line) }
    end

    def self.readBracketResults
        return [] unless File.exist?(BRACKET_RESULTS_PATH)
        rows = []
        File.foreach(BRACKET_RESULTS_PATH) do |line|
            next if line.strip.empty?
            values = line.chomp.split("\t", -1)
            next if values.length != BRACKET_RESULT_FIELDS.length
            row = {}
            BRACKET_RESULT_FIELDS.each_with_index { |f, i| row[f] = values[i] }
            rows << row
        end
        rows
    end

    # Identity-based resume: every (round, match) that already has a result
    # row is decided, regardless of how far the rest of the bracket got.
    def self.readDecidedMatches
        decided = {}
        readBracketResults.each do |row|
            decided[[row[:round].to_i - 1, row[:match].to_i - 1]] = row
        end
        decided
    end

    def self.writeBracketStatus(done, total, t_start, round_name, finished: false, champion: nil, error: nil)
        elapsed = Time.now - t_start
        File.open(BRACKET_STATUS_PATH, "w") { |f| f.write(json_encode({
            done: done,
            total: total,
            percent: total > 0 ? (done * 100.0 / total).round(2) : 0,
            round: round_name,
            elapsed_s: elapsed.round(1),
            finished: finished,
            champion: champion,
            error: error,
            updated_at: Time.now.to_s,
        })) }
    end
end

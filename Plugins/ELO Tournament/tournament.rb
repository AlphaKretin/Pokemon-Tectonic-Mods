#==============================================================================
# ELO Tournament — Phase 1 spike
#
# Hardcoded single battle to prove the headless path works end to end:
# boot -> $Trainer stub -> AIBenchmark.runBattle -> result written to disk.
# Will be replaced by real pairing/orchestration in later phases.
#==============================================================================
module EloTournament
    RESULTS_PATH = ENV["ELO_RESULTS_PATH"] || "Analysis/elo_phase1_result.json"

    def self.run!
        heuristic = AIBenchmark::HEURISTICS[:baseline]
        t1 = GameData::Trainer.get(:LEADER_Lambert, "Lambert")
        t2 = GameData::Trainer.get(:YOUNGSTER, "Joey")

        srand(12345)
        result = AIBenchmark.runBattle(t1, t2, heuristic, heuristic)

        write_result({
            ok: true,
            trainer1: "#{t1.trainer_type}:#{t1.name}",
            trainer2: "#{t2.trainer_type}:#{t2.name}",
            result: result[:result],
            rounds: result[:rounds],
            time_s: result[:time_s],
        })
    rescue => e
        write_result({
            ok: false,
            error_class: e.class.name,
            error_message: e.message,
            backtrace: e.backtrace&.first(20),
        })
    end

    def self.write_result(data)
        File.open(RESULTS_PATH, "w") { |f| f.write(json_encode(data)) }
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
end

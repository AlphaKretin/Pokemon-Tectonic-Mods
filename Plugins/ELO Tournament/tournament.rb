#==============================================================================
# ELO Tournament — Phase 2 spike
#
# Builds the real trainer pool and reports stats, so the pool can be sanity
# checked before any real orchestration is built on top of it.
#==============================================================================
module EloTournament
    RESULTS_PATH = ENV["ELO_RESULTS_PATH"] || "Analysis/elo_phase2_result.json"

    def self.run!
        pool = buildTrainerPool

        size_counts = Hash.new(0)
        pool.each { |entry| size_counts[entry.party_size] += 1 }

        rematch = GameData::Trainer.try_get(:LEADER_Lambert, "Lambert", 1)
        rematch_info = nil
        if rematch
            trainer = rematch.to_trainer
            rematch_info = {
                label: trainerLabel(rematch),
                party: trainer.party.map { |p| "#{p.species}:#{p.level}" },
            }
        end

        write_result({
            ok: true,
            pool_size: pool.length,
            party_size_histogram: size_counts,
            sample_trainers: pool.first(5).map { |e| "#{trainerLabel(e.trainer_data)} (#{e.party_size})" },
            rematch_spot_check: rematch_info,
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

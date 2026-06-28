#==============================================================================
# ELO Tournament — trainer pool
#
# The real, full-roster trainer pool (as opposed to AIBenchmark's own
# buildTrainerPool, which is hardcoded to 6-mon level-70 squads for
# heuristic testing). Battle Tower trainers aren't excluded here by choice —
# they simply don't exist in GameData::Trainer at all; they're compiled into
# a separate Battle Frontier data structure (PBS/bttrainers.txt + a
# pokemon-index pool, no fixed roster), so GameData::Trainer.each never
# yields them in the first place.
#==============================================================================
module EloTournament
    PoolEntry = Struct.new(:trainer_data, :party_size, :curse)

    # CURSE_AVATAR_GUARD previously failed "Unknown avatar" lookups against
    # a stale Data/avatars.dat (PBS data only recompiles on a "debug
    # compile" launch, which non-debug tournament runs never trigger).
    # Fixed by a one-time PBS recompile; confirmed via two isolated
    # single-battle runs of Yezera#9 (different opponents/seeds), both
    # completing cleanly with no quarantine needed.
    QUARANTINED_POLICIES = []

    # Monument trainers (PBS/trainers_monument.txt) are real content but
    # intentionally out of scope (disjoint rematch/gauntlet roster, per
    # design). Everything else with a non-empty resolved party is included —
    # no further curation (legendary "trainer" wrappers, joke/dev battles,
    # etc. all stay in).
    def self.buildTrainerPool
        pool = []
        GameData::Trainer.each do |td|
            next if td.monumentTrainer
            trainer = td.to_trainer
            party_size = trainer.party.length
            next if party_size == 0
            next if trainer.policies.any? { |p| QUARANTINED_POLICIES.include?(p) }
            curse = trainer.policies.any? { |p| p.to_s.start_with?("CURSE_") }
            pool.push(PoolEntry.new(td, party_size, curse))
        end
        pool
    end

    def self.trainerLabel(td)
        label = "#{td.trainer_type}:#{td.real_name}"
        label += "##{td.version}" if td.version > 0
        label
    end
end

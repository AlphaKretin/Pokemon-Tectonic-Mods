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

    # CURSE_AVATAR_GUARD inserts a generated avatar Pokemon into the
    # trainer's party (AvatarGuard.rb) whose species the AI's switch-rating
    # evaluation then fails to resolve ("Unknown avatar X 0" for X != the
    # hardcoded LINOONE species -- still not understood why), which seems
    # to make that evaluation degrade badly enough that some matchups grind
    # to the engine's 100-round cap (result: 0/undecided, ~175-230s) instead
    # of resolving normally. Two earlier isolated test seeds happened not to
    # trigger this and were wrongly taken as proof it was fixed; un-
    # quarantining needs much more than 2 lucky seeds next time. See
    # Plugins/Chasm Battle/AI/AI_Switch.rb getSwitchRatingForPartyMember and
    # Plugins/Chasm Battle/AI/AI_Boss.rb from_boss_battler.
    QUARANTINED_POLICIES = [:CURSE_AVATAR_GUARD]

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

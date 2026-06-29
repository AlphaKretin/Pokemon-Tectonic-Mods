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

    # CURSE_AVATAR_GUARD's "Unknown avatar X" crash is fixed (real root
    # cause: autoTesting's built-in randomization reassigning the active
    # avatar's species, not anything specific to the avatar mechanic --
    # see battle.autoTestingRandomization in AIBenchmark.runBattle).
    # Confirmed via the test harness against multiple seeds, not just one
    # or two -- the earlier two "confirmed fixed" calls this session were
    # both wrong because the real bug was never reproduced standalone
    # *correctly* until this fix actually addressed it.
    #
    # ALLOW_RANDOM_MOVES (only ROLLERSKATER_F:Attea as of 2026-06-28) is
    # quarantined because its strategy is genuinely chaotic (forced
    # random move selection), not because dev/joke trainers as a category
    # are out of scope -- most DEVELOPER-type trainers are real curated
    # teams worth ranking and stay in the pool.
    #
    # Left empty for now: changing pool composition reshuffles the entire
    # sampledEdges() pairing list (Fisher-Yates is sensitive to array
    # length from the first draw), not just Attea's own pairs, which would
    # orphan ~16k already-completed results on resume instead of cleanly
    # skipping them. Attea is excluded at analysis time (ratings.py)
    # instead, until a fresh full resample is worth doing.
    QUARANTINED_POLICIES = [:ALLOW_RANDOM_MOVES]

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

    # One-off diagnostic dump (ELO_DUMP_TRAINER_CARD_DATA) for the trainer
    # card generator: every pool trainer's fully-resolved (ExtendsVersion-
    # merged) policies and party, by way of td.to_trainer -- the same
    # resolution real battles use -- rather than re-deriving PBS inheritance
    # rules in Python, which would be easy to get subtly wrong.
    def self.dumpTrainerCardData!
        data = buildTrainerPool.map do |entry|
            td = entry.trainer_data
            trainer = td.to_trainer
            {
                label: trainerLabel(td),
                trainer_type: td.trainer_type.to_s,
                trainer_type_label: td.trainer_type_label&.to_s,
                trainer_type_display: trainer.trainer_type_name,
                gender: trainer.gender,
                real_name: td.real_name,
                name_for_hashing: td.name_for_hashing,
                version: td.version,
                policies: trainer.policies.map(&:to_s),
                party: trainer.party.map { |p| { species: p.species.to_s, species_display: p.speciesName, level: p.level, nickname: (p.nicknamed? ? p.name : nil), shiny: p.shiny?, held_items: p.items.map(&:to_s) } },
            }
        end
        File.open("Analysis/trainer_card_data.json", "w") { |f| f.write(EloTournament.json_encode(data)) }
    end
end

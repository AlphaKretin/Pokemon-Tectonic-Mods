#==============================================================================
# ELO Tournament — curse stripping
#
# Produces a curse-free resolved trainer for the "uncursed" tournament
# format: every cursed trainer battling with their curse effects removed,
# but genuine (non-curse) team differences from their ExtendsVersion base
# kept intact (e.g. a Gym Leader's held-item upgrades that ride along with
# a curse policy bump but aren't part of the curse mechanic itself).
#
# Per-curse-type scope, confirmed with Luna 2026-07-03:
# - All CURSE_* policies are removed from trainer.policies. This alone
#   fully and correctly reverts every purely code-level curse (25 of the
#   36 CURSE_* types -- see PBS/policies.txt), since their entire mechanic
#   is gated on curseHolder?/curseVictim?/curseActive? checks against this
#   list at battle time.
# - ExtraMoves/ExtraTypes are cleared unconditionally on every party member
#   of a cursed trainer. In practice these PBS fields are only ever
#   populated alongside CURSE_EXTRA_MOVES/CURSE_EXTRA_TYPES, so this is
#   equivalent to a scoped strip but simpler; clearing an empty array is a
#   no-op for any other cursed trainer.
# - ExtraAbilities is cleared only for CURSE_DOUBLE_ABILITIES/
#   CURSE_SAND_ABILITIES holders -- unlike Extra{Moves,Types}, this field
#   riding along with an unrelated curse would be a real (if currently
#   unobserved) possibility, and clearing it is specifically because it
#   reinforces those two curses' ability-granting effect.
# - CURSE_NO_MERCY/_2/_3/_4: no action. The extra battlers aren't unfair
#   1v1/2v2 (the real-play unfairness is from multi-battles exceeding 6
#   opponents, which doesn't apply here), so the party is left untouched.
#   This makes stripping a complete no-op for a trainer whose only curse
#   is a NO_MERCY variant -- see dumpCurseStripDiff!'s no_change_from_original.
# - CURSE_FIGHT_EXTENDED: no action, for the same reason -- confirmed
#   inert in this project's headless battle path (battle.turnsToSurvive
#   is only ever set via the overworld's pbPrepareBattle, which AI_Benchmark
#   never calls), so there's nothing to strip.
# - CURSE_EXTRA_ITEMS/CURSE_SUPER_ITEMS: items merge irreversibly into
#   Pokemon#items during to_trainer (Item= replaces the array wholesale,
#   ExtraItems= appends), so provenance doesn't survive on the resolved
#   object. Handled separately below via the raw TrainerData#pokemon hash,
#   which still has distinct :item/:extra_items keys.
#==============================================================================
module EloTournament
    CURSE_ABILITY_STRIP_TYPES = [:CURSE_DOUBLE_ABILITIES, :CURSE_SAND_ABILITIES]

    # Curse types confirmed to have zero effect on either party data or
    # in-battle mechanics in this project (CURSE_NO_MERCY family: flavor-only
    # handler, party deliberately left untouched by design; CURSE_FIGHT_EXTENDED:
    # the timer it cancels is never live in the headless battle path to begin
    # with). A trainer whose curses are drawn entirely from this set produces
    # mechanically identical battles whether or not the policy is stripped.
    CURSE_INERT_TYPES = [:CURSE_NO_MERCY, :CURSE_NO_MERCY_2, :CURSE_NO_MERCY_3,
                          :CURSE_NO_MERCY_4, :CURSE_FIGHT_EXTENDED]

    # Fixed seed so repeated to_trainer resolutions of the same TrainerData
    # within a single diagnostic run are directly comparable -- Pokemon#personalID
    # (and anything derived from it, e.g. a default ability_index when no
    # AbilityIndex is authored) is seeded from the global RNG, which would
    # otherwise differ between two independent to_trainer calls and produce
    # spurious diffs unrelated to curse-stripping.
    DIAGNOSTIC_SEED = 20260703

    # @param td [GameData::Trainer]
    # @return [NPCTrainer] a resolved trainer with curse effects removed
    def self.stripCurses(td)
        applyCurseStripMutations!(td, td.to_trainer)
    end

    # Real interception point for battles: singleton-overrides this specific
    # TrainerData instance's to_trainer, following the same pattern as
    # tournament.rb's trimPartyByIndices! (calls super() to get the normal
    # resolution, since AIBenchmark.runBattle needs to keep calling to_trainer
    # itself rather than receive an already-resolved object). Deliberately
    # NOT implemented as `define_singleton_method { stripCurses(self) }` --
    # stripCurses calls td.to_trainer itself, which would recurse into this
    # same override infinitely once installed.
    def self.applyCurseStripping!(td)
        td.define_singleton_method(:to_trainer) do
            EloTournament.applyCurseStripMutations!(self, super())
        end
    end

    # Mutates an already-resolved `trainer` (from td.to_trainer) in place per
    # the curse-type scope documented above, and returns it.
    def self.applyCurseStripMutations!(td, trainer)
        curses = trainer.policies.select { |p| p.to_s.start_with?("CURSE_") }
        trainer.policies.reject! { |p| p.to_s.start_with?("CURSE_") }
        return trainer if curses.empty?

        strip_abilities = curses.any? { |c| CURSE_ABILITY_STRIP_TYPES.include?(c) }
        trainer.party.each do |pkmn|
            pkmn.extraMoves.clear
            pkmn.extraTypes.clear
            pkmn.extraAbilities.clear if strip_abilities
        end

        has_extra_items = curses.include?(:CURSE_EXTRA_ITEMS)
        has_super_items = curses.include?(:CURSE_SUPER_ITEMS)
        if has_extra_items || has_super_items
            base = td.getParentTrainer
            td.pokemon.each do |pkmn_data|
                needs_extra_items_strip = has_extra_items && pkmn_data[:extra_items]
                needs_super_items_strip = has_super_items && pkmn_data[:item] && base
                next unless needs_extra_items_strip || needs_super_items_strip

                species = GameData::Species.get(pkmn_data[:species]).species
                level = pkmn_data[:level]
                nickname = (pkmn_data[:name] && !pkmn_data[:name].empty?) ? pkmn_data[:name] : nil

                pkmn = findPartyMatch(trainer.party, species, level, nickname)
                next if pkmn.nil?

                if needs_extra_items_strip
                    pkmn_data[:extra_items].each { |item_id| pkmn.items.delete(item_id) }
                end

                if needs_super_items_strip
                    basePkmn = findPartyMatch(base.party, species, level, nickname)
                    pkmn.setItems(basePkmn.items.clone) if basePkmn
                end
            end
        end

        trainer
    end

    # Replicates to_trainer's own inheritance-matching rule (species+level,
    # falling back to species+nickname) so raw per-version PBS declarations
    # can be matched back to their resolved Pokemon object.
    def self.findPartyMatch(party, species, level, nickname)
        party.each do |pkmn|
            next if pkmn.species != species
            return pkmn if pkmn.level == level
            return pkmn if nickname && nickname == pkmn.name
        end
        nil
    end

    # Field-by-field comparison of two resolved parties, matched the same
    # way to_trainer matches inherited party members. Returns true only if
    # every Pokemon in `party` has an exact match in `otherParty` and there
    # are no unmatched extras on either side.
    def self.partiesIdentical?(party, otherParty)
        return false if party.length != otherParty.length
        party.each do |pkmn|
            match = findPartyMatch(otherParty, pkmn.species, pkmn.level, pkmn.name)
            return false if match.nil?
            return false if !pokemonFieldsIdentical?(pkmn, match)
        end
        true
    end

    def self.mainStatIds
        return @mainStatIds if @mainStatIds
        ids = []
        GameData::Stat.each_main { |s| ids.push(s.id) }
        @mainStatIds = ids
    end

    def self.pokemonFieldsIdentical?(a, b)
        return false if a.moves.map(&:id).sort != b.moves.map(&:id).sort
        return false if a.extraMoves.sort != b.extraMoves.sort
        return false if a.items.sort_by(&:to_s) != b.items.sort_by(&:to_s)
        return false if a.ability_id != b.ability_id
        return false if a.extraAbilities.sort != b.extraAbilities.sort
        return false if a.types.sort != b.types.sort
        return false if mainStatIds.map { |id| a.ev[id] } != mainStatIds.map { |id| b.ev[id] }
        true
    end

    def self.diffParty(party, otherParty)
        diffs = []
        party.each do |pkmn|
            match = findPartyMatch(otherParty, pkmn.species, pkmn.level, pkmn.name)
            if match.nil?
                diffs.push({ species: pkmn.species.to_s, level: pkmn.level, diff: "no_match_in_other_party" })
                next
            end
            next if pokemonFieldsIdentical?(pkmn, match)
            diffs.push({
                species: pkmn.species.to_s,
                level: pkmn.level,
                moves: [pkmn.moves.map(&:id), match.moves.map(&:id)],
                extraMoves: [pkmn.extraMoves, match.extraMoves],
                items: [pkmn.items, match.items],
                ability: [pkmn.ability_id, match.ability_id],
                extraAbilities: [pkmn.extraAbilities, match.extraAbilities],
                types: [pkmn.types, match.types],
            })
        end
        diffs
    end

    # Classifies a single cursed TrainerData into the three buckets that
    # drive both the diagnostic report and the real "uncursed" format's pool
    # selection (tournament.rb): identical_to_base (-> exclude entirely) /
    # no_change_from_original (-> no fresh simulation, reuse existing rows) /
    # neither (-> needs fresh battles). See dumpCurseStripDiff! for the
    # fuller diagnostic (adds base label + field diffs) built on top of this.
    # @return [Hash] { identical_to_base:, no_change_from_original:, base_label:, stripped:, original:, base: }
    def self.classifyCursedTrainer(td)
        srand(DIAGNOSTIC_SEED)
        stripped = stripCurses(td)
        srand(DIAGNOSTIC_SEED)
        original = td.to_trainer
        curses = original.policies.select { |p| p.to_s.start_with?("CURSE_") }
        baseTd = td.getParentTrainer(true)

        no_change_from_original = curses.all? { |c| CURSE_INERT_TYPES.include?(c) } &&
                                   partiesIdentical?(stripped.party, original.party)

        if baseTd.nil?
            identical_to_base = false
            base = nil
            base_label = nil
        else
            srand(DIAGNOSTIC_SEED)
            base = td.getParentTrainer
            identical_to_base = partiesIdentical?(stripped.party, base.party)
            base_label = trainerLabel(baseTd)
        end

        {
            curses: curses,
            identical_to_base: identical_to_base,
            no_change_from_original: no_change_from_original,
            base_label: base_label,
            stripped: stripped,
            original: original,
            base: base,
        }
    end

    # One-off diagnostic dump (ELO_DUMP_CURSE_STRIP_DIFF): for every cursed
    # pool trainer, classifies whether the curse-stripped party is identical
    # to the trainer's ExtendsVersion base (-> exclude from the new format
    # entirely, redundant with the base's already-complete results) or
    # identical to the original unstripped party (-> no fresh simulation
    # needed, reuse the existing curse-flagged rows).
    def self.dumpCurseStripDiff!
        report = {}
        buildTrainerPool.each do |entry|
            next unless entry.curse
            td = entry.trainer_data
            label = trainerLabel(td)
            c = classifyCursedTrainer(td)
            diffs = (!c[:identical_to_base] && c[:base]) ? diffParty(c[:stripped].party, c[:base].party) : []

            report[label] = {
                curses: c[:curses].map(&:to_s),
                base: c[:base_label],
                identical_to_base: c[:identical_to_base],
                no_change_from_original: c[:no_change_from_original],
                diffs_vs_base: diffs,
            }
        end
        File.open("Analysis/curse_strip_diff.json", "w") { |f| f.write(EloTournament.json_encode(report)) }
    end
end

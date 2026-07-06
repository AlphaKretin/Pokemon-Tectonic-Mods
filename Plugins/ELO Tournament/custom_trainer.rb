#==============================================================================
# ELO Tournament — custom trainer loader
#
# Registers exactly one trainer into GameData::Trainer's in-memory DATA at
# runtime, straight from a standalone PBS-formatted snippet (same syntax as
# one [TrainerType,Name(,Version)] section of PBS/trainers.txt), without
# touching trainers.dat or requiring a PBS recompile.
#
# GameData::Trainer.register (GameData.rb's generic ClassMethods#register)
# is just `DATA[id] = DATA[id_number] = self.new(hash)` -- pure write, no
# reset of existing entries -- and Compiler.compile_trainers itself never
# clears DATA before compiling either (it's meant to be additive across
# PBS/trainers.txt + PBS/trainers_monument.txt + extension files already).
# So the real pool loaded from trainers.dat at boot survives untouched;
# this only ever adds one more entry.
#
# The parsing logic below is a deliberate near-duplicate of
# Compiler.compile_trainers's per-line block (Compiled Data/Trainer.rb) --
# that method inlines its schema-driven parsing rather than factoring out a
# reusable "compile one trainer" helper, so there's nothing to call into
# directly. Kept as close to the original as possible (same SCHEMA, same
# pbGetCsvRecord/property handling) so a snippet that's valid in
# PBS/trainers.txt parses identically here.
#==============================================================================
module EloTournament
    class CustomTrainerError < StandardError; end

    # Picks an id_number that can't collide with any trainer already loaded
    # from trainers.dat (which is what GameData::Trainer.each/.get key off).
    def self.nextCustomTrainerIdNumber
        max_existing = GameData::Trainer::DATA.keys.select { |k| k.is_a?(Integer) }.max || -1
        max_existing + 1
    end

    # Reads a single-trainer PBS snippet from path and registers it into
    # GameData::Trainer, returning the resulting GameData::Trainer record
    # (the same kind of object buildTrainerPool/GameData::Trainer.get deal
    # in). Raises CustomTrainerError if the file defines zero or more than
    # one trainer section, or if its (type, name, version) collides with an
    # already-registered trainer (real or a previous custom-trainer load in
    # this same process).
    def self.registerCustomTrainerFromPBS!(path)
        raise CustomTrainerError, "Custom trainer PBS file not found: #{path}" unless File.exist?(path)

        schema = GameData::Trainer::SCHEMA
        max_level = GameData::GrowthRate.max_level
        trainer_hash = nil
        trainer_id = nextCustomTrainerIdNumber - 1
        current_pkmn = nil
        isExtending = false
        registered_hash = nil

        Compiler.pbCompilerEachPreppedLine(path) { |line, line_no|
            if line[/^\s*\[\s*(.+)\s*\]\s*$/]
                if trainer_hash
                    raise CustomTrainerError, "Custom trainer PBS file must define exactly one trainer section (found a second one).\n#{FileLineData.linereport}"
                end
                trainer_id += 1
                line_data = Compiler.pbGetCsvRecord($~[1], line_no, [0, "esU", :TrainerType])
                trainer_hash = {
                    :id_number          => trainer_id,
                    :trainer_type       => line_data[0],
                    :name               => line_data[1],
                    :version            => line_data[2] || 0,
                    :pokemon            => [],
                    :policies           => [],
                    :flags              => [],
                    :extends            => -1,
                    :removed_pokemon    => [],
                    :monument_trainer   => false,
                    :defined_in_extension => false,
                }
                isExtending = false
                current_pkmn = nil
            elsif line[/^\s*(\w+)\s*=\s*(.*)$/]
                raise CustomTrainerError, "Expected a [TrainerType,Name] section at the start of the file.\n#{FileLineData.linereport}" unless trainer_hash
                property_name = $~[1]
                line_schema = schema[property_name]
                next unless line_schema
                property_value = Compiler.pbGetCsvRecord($~[2], line_no, line_schema)
                case property_name
                when "Items"
                    property_value = [property_value] if !property_value.is_a?(Array)
                    property_value.compact!
                when "Pokemon", "RemovePokemon"
                    if property_value[1] > max_level
                        raise CustomTrainerError, "Bad level: #{property_value[1]} (must be 1-#{max_level}).\n#{FileLineData.linereport}"
                    end
                when "Name"
                    if property_value.length > Pokemon::MAX_NAME_SIZE
                        raise CustomTrainerError, "Bad nickname: #{property_value} (must be 1-#{Pokemon::MAX_NAME_SIZE} characters).\n#{FileLineData.linereport}"
                    end
                when "Moves", "Item"
                    property_value = [property_value] if !property_value.is_a?(Array)
                    property_value.uniq!
                    property_value.compact!
                when "Happiness"
                    if property_value > 255
                        raise CustomTrainerError, "Bad happiness: #{property_value} (must be 0-255).\n#{FileLineData.linereport}"
                    end
                when "Position"
                    if property_value < 0 || property_value >= Settings::MAX_PARTY_SIZE
                        raise CustomTrainerError, "Bad party position: #{property_value} (must be 0-#{Settings::MAX_PARTY_SIZE - 1}).\n#{FileLineData.linereport}"
                    end
                end
                case property_name
                when "Items", "LoseText", "Policies", "NameForHashing", "Flags", "TrainerTypeLabel"
                    trainer_hash[line_schema[0]] = property_value
                when "Extends"
                    trainer_hash[:extends_class] = property_value[0]
                    trainer_hash[:extends_name] = property_value[1]
                    trainer_hash[:extends_version] = property_value[2]
                    isExtending = true
                when "ExtendsVersion"
                    trainer_hash[:extends_version] = property_value
                    isExtending = true
                when "Pokemon", "RemovePokemon"
                    current_pkmn = { :species => property_value[0], :level => property_value[1] }
                    if !isExtending
                        current_pkmn[:ability_index] = (trainer_hash[:name] + current_pkmn[:species].to_s).hash % 2
                    end
                    trainer_hash[line_schema[0]].push(current_pkmn)
                else
                    raise CustomTrainerError, "Pokémon hasn't been defined yet!\n#{FileLineData.linereport}" unless current_pkmn
                    case property_name
                    when "Ability"
                        if property_value[/^\d+$/]
                            current_pkmn[:ability_index] = property_value.to_i
                        elsif !GameData::Ability.exists?(property_value.to_sym)
                            raise CustomTrainerError, "Value #{property_value} isn't a defined Ability.\n#{FileLineData.linereport}"
                        else
                            current_pkmn[line_schema[0]] = property_value.to_sym
                        end
                    when "ExtraAbilities"
                        current_pkmn[line_schema[0]] = property_value.map { |v| v.to_sym }
                    when "ExtraMoves"
                        current_pkmn[line_schema[0]] = property_value.map { |v| v.to_sym }
                    when "EV"
                        value_hash = {}
                        GameData::Stat.each_main do |s|
                            next if s.pbs_order < 0
                            value_hash[s.id] = property_value[s.pbs_order] || property_value[0]
                        end
                        current_pkmn[line_schema[0]] = value_hash
                    when "Ball"
                        if property_value[/^\d+$/]
                            current_pkmn[line_schema[0]] = pbBallTypeToItem(property_value.to_i).id
                        elsif !GameData::Item.exists?(property_value.to_sym) || !GameData::Item.get(property_value.to_sym).is_poke_ball?
                            raise CustomTrainerError, "Value #{property_value} isn't a defined Poké Ball.\n#{FileLineData.linereport}"
                        else
                            current_pkmn[line_schema[0]] = property_value.to_sym
                        end
                    else
                        current_pkmn[line_schema[0]] = property_value
                    end
                end
            end
        }

        raise CustomTrainerError, "Custom trainer PBS file defined no trainer section." unless trainer_hash
        raise CustomTrainerError, "Custom trainer has no Pokémon." if trainer_hash[:pokemon].empty? && !isExtending

        trainer_hash[:id] = [trainer_hash[:trainer_type], trainer_hash[:name], trainer_hash[:version]]
        if GameData::Trainer::DATA.key?(trainer_hash[:id])
            raise CustomTrainerError, "A trainer already exists with the same (type, name, version) as the custom trainer: #{trainer_hash[:id].inspect} -- pick a different Name/Version in the PBS snippet."
        end

        GameData::Trainer.register(trainer_hash)
        GameData::Trainer.get(*trainer_hash[:id])
    end
end

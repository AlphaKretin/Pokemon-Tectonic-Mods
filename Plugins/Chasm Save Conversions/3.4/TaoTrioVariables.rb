SaveData.register_conversion(:tao_trio_quest_variables) do
  game_version '3.4.0'
  display_title 'Initializing variables related to the Tao Trio Quest'
  to_all do |save_data|
    globalSwitches = save_data[:switches]
    globalVariables = save_data[:variables]
    selfSwitches = save_data[:self_switches]

    vanyaInteractions = 0
    vanyaInteractions += 1 if selfSwitches[[56,75,'B']] # novo vanya
    vanyaInteractions += 1 if selfSwitches[[6,23,'B']] # luxtech vanya
    vanyaInteractions += 1 if selfSwitches[[8,53,'B']] # velenz vanya
    vanyaInteractions += 1 if selfSwitches[[155,61,'B']] # prizca west vanya
    vanyaInteractions += 1 if selfSwitches[[187,32,'B']] # prizca east vanya
    vanyaInteractions += 1 if selfSwitches[[217,36,'B']] # sweetrock harbor vanya
    vanyaInteractions += 1 if selfSwitches[[214,40,'B']] # team chasm hq vanya

    globalVariables[48] = vanyaInteractions
  end
end
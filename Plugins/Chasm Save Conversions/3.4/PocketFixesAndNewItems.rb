SaveData.register_conversion(:item_repocketing_340) do
  game_version '3.4.0'
  display_title 'Reassigning bag pockets for 3.4.0 changes'
  to_all do |save_data|
    save_data[:bag].reassignPockets()
  end
end

SaveData.register_conversion(:pokemon_lure_3_4_0) do
  game_version '3.4.0'
  display_title 'Adding the Pokemon Lure 3.4.0'
  to_all do |save_data|
      globalSwitches = save_data[:switches]
      globalVariables = save_data[:variables]
      selfSwitches = save_data[:self_switches]
      itemBag = save_data[:bag]

      if selfSwitches[[32,14,'C']] # Completed Lost Growlithe quest
          itemBag.pbStoreItem(:POKEMONLURE, 1, false)
      end
  end
end

SaveData.register_conversion(:primal_beads_3_4_0) do
  game_version '3.4.0'
  display_title 'Adding Primal Beads 3.4.0'
  to_all do |save_data|
      globalSwitches = save_data[:switches]
      globalVariables = save_data[:variables]
      selfSwitches = save_data[:self_switches]
      itemBag = save_data[:bag]
  
      itemBag.pbStoreItem(:PRIMALBEAD, 1, false) if selfSwitches[[258,17,'C']] # defeated whitebloom yezera
      itemBag.pbStoreItem(:PRIMALBEAD, 1, false) if selfSwitches[[215,3,'A']] # defeated rayquaza avatar
  end
end

SaveData.register_conversion(:technique_booster_3_4_0) do
  game_version '3.4.0'
  display_title 'Adding technique booster 3.4.0'
  to_all do |save_data|
      globalSwitches = save_data[:switches]
      globalVariables = save_data[:variables]
      selfSwitches = save_data[:self_switches]
      itemBag = save_data[:bag]
  
      itemBag.pbStoreItem(:TECHNIQUEBOOSTER, 1, false) if selfSwitches[[5,1,'A']] # defeated avatar of genesect
  end
end

SaveData.register_conversion(:vs_recorder_3_4_0) do
  game_version '3.4.0'
  display_title 'Adding the VS Recorder 3.4.0'
  to_all do |save_data|
      globalSwitches = save_data[:switches]
      globalVariables = save_data[:variables]
      selfSwitches = save_data[:self_switches]
      itemBag = save_data[:bag]
  
      itemBag.pbStoreItem(:VSRECORDER, 1, false)
  end
end

SaveData.register_conversion(:styling_kit_3_4_0) do
  game_version '3.4.0'
  display_title 'Adding styling kit 3.4.0'
  to_all do |save_data|
      globalSwitches = save_data[:switches]
      globalVariables = save_data[:variables]
      selfSwitches = save_data[:self_switches]
      itemBag = save_data[:bag]
  
      itemBag.pbStoreItem(:STYLINGKIT, 1, false) if globalVariables[52] > 2 # Alessa quest past stage 2
  end
end

SaveData.register_conversion(:tm_fixing_340) do
  game_version '3.4.0'
  display_title 'Fixing illegal TMs'
  to_all do |save_data|
    save_data[:bag].pbChangeItem(:TMDISSIPATION,:TMSHIVERDANCE)
    save_data[:bag].pbChangeItem(:TMCLOUDBREAK,:TMQUIVERDANCE)
    save_data[:bag].pbChangeItem(:TMAURASPHERE,:TMADRENALASH)
    save_data[:bag].pbChangeItem(:TMSCREECH,:TMBARETEETH)
    save_data[:bag].pbChangeItem(:TMCOSMICPOWER,:TMRAPIDSPIN)
    save_data[:bag].pbChangeItem(:TMTRICK,:TMSWITCHEROO)
    save_data[:bag].pbChangeItem(:TMBULLETTRAIN,:TMMETEORMASH)
    save_data[:bag].pbChangeItem(:TMSEERSTRIKE,:TMPSYCHOSCISSION)
    save_data[:bag].pbChangeItem(:TMPSYCHIC,:TMNEURALPULSE)
    save_data[:bag].pbChangeItem(:TMSLEEPTALK,:TMPLAYDEAD)
    save_data[:bag].pbChangeItem(:TMREND,:TMDRAGONHAMMER)
  end
end

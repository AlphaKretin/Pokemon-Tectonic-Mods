Events.onWildPokemonCreate += proc {|sender,e|\
    next unless [333, 430].include?($game_map.map_id) # Floral Maze or Amber Hills
    next unless rand(100) < 35
    pokemon = e[0]
    pokemon.setItems([:NOBLEFEATHER])
    echoln("Inserting a Noble Feather as the held item of wild Pokemon: #{pokemon.name}")
}
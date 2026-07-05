SaveData.register_conversion(:missing_trainer_policies) do
  game_version '3.4.0'
  display_title 'Fixing missing trainer data.'
  to_all do |save_data|
    save_data[:player].policies = [] if save_data[:player].policies.nil?
  end
end
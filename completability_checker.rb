
require 'yaml'

class CompletabilityChecker
  attr_reader :game,
              :current_items,
              
              :defs,
              :preferences,
              
              :inaccessible_doors,
              
              :all_progression_pickups,
              
              :enemy_locations,
              :event_locations,
              :easter_egg_locations,
              :villager_locations,
              :hidden_locations,
              :mirror_locations,
              :no_soul_locations,
              :no_glyph_locations,
              :no_progression_locations,
              :portrait_locations
  
  def initialize(game, options)
    @game = game
    @options = options
    
    load_room_reqs()
    @current_items = []
    @debug = false
  end
  
  def load_room_reqs
    yaml = YAML::load_file("./dsvrandom/progressreqs/#{GAME}_pickup_requirements.txt")
    @room_reqs = {}
    
    defs = yaml["Defs"]
    @defs = {}
    defs.each do |name, reqs|
      name = name.strip.tr(" ", "_").to_sym
      reqs = parse_reqs(reqs)
      @defs[name] = reqs
    end
    
    glitch_defs = yaml["Glitch defs"]
    @glitch_defs = {}
    if glitch_defs
      glitch_defs.each do |name, reqs|
        name = name.strip.tr(" ", "_").to_sym
        reqs = parse_reqs(reqs)
        @glitch_defs[name] = reqs
      end
    end
    
    if @options[:enable_glitch_reqs]
      @defs.merge!(@glitch_defs)
    end
    
    @inaccessible_doors = []
    
    @preferences = {}
    if yaml["Preferences"]
      yaml["Preferences"].each do |pickup_name, weight|
        pickup_id = @defs[pickup_name.strip.tr(" ", "_").to_sym]
        @preferences[pickup_id] = weight
      end
    end
    
    rooms = yaml["Rooms"]
    
    @enemy_locations = []
    @event_locations = []
    @easter_egg_locations = []
    @villager_locations = []
    @hidden_locations = []
    @mirror_locations = []
    @no_soul_locations = []
    @no_glyph_locations = []
    @no_progression_locations = []
    @portrait_locations = []
    
    rooms.each do |room_str, yaml_reqs|
      @room_reqs[room_str] ||= {}
      @room_reqs[room_str][:room] = nil
      @room_reqs[room_str][:entities] = {}
      
      yaml_reqs.each do |applies_to, reqs|
        parsed_reqs = parse_reqs(reqs)
        
        if applies_to == "room"
          @room_reqs[room_str][:room] = parsed_reqs
        else
          entity_index = applies_to.to_i(16)
          @room_reqs[room_str][:entities][entity_index] = parsed_reqs
          
          entity_str = "#{room_str}_%02X" % entity_index
          if applies_to.include?(" (Enemy)")
            @enemy_locations << entity_str
          end
          if applies_to.include?(" (Event)")
            @event_locations << entity_str
          end
          if applies_to.include?(" (Easter egg)")
            @easter_egg_locations << entity_str
          end
          if applies_to.include?(" (Villager)")
            @villager_locations << entity_str
          end
          if applies_to.include?(" (Hidden)")
            @hidden_locations << entity_str
          end
          if applies_to.include?(" (Mirror)")
            @mirror_locations << entity_str
          end
          if applies_to.include?(" (No souls)")
            @no_soul_locations << entity_str
          end
          if applies_to.include?(" (No glyphs)")
            @no_glyph_locations << entity_str
          end
          if applies_to.include?(" (No progression)")
            @no_progression_locations << entity_str
          end
          if applies_to.include?(" (Portrait)")
            @portrait_locations << entity_str
          end
        end
      end
    end
  end
  
  def parse_reqs(reqs)
    if reqs.is_a?(Integer) || reqs.nil?
      return reqs
    elsif reqs == true
      return true
    elsif reqs == false
      return false
    elsif PickupRandomizer::RANDOMIZABLE_VILLAGER_NAMES.include?(reqs.tr(" ", "_").to_sym)
      return reqs.tr(" ", "_").to_sym
    elsif PickupRandomizer::PORTRAIT_NAMES.include?(reqs.tr(" ", "_").to_sym)
      return reqs.tr(" ", "_").to_sym
    end
    
    or_reqs = reqs.split("|")
    or_reqs.map! do |or_req|
      and_reqs = or_req.split("&")
      and_reqs.map! do |and_req|
        and_req = and_req.strip.tr(" ", "_").to_sym
        and_req = nil if and_req.empty?
        and_req
      end
    end
  end
  
  def game_beatable?
    check_reqs([[:beat_game]])
  end
  
  def albus_fight_accessible?
    check_reqs([[:bossalbus]])
  end
  
  def wind_accessible?
    check_reqs([[:wind]])
  end
  
  def vincent_accessible?
    check_reqs([[:vincent]])
  end
  
  def check_reqs(reqs)
    if reqs == true
      return true
    elsif reqs == false
      return false
    end
    
    @cached_checked_reqs = {}
    check_multiple_reqs_recursive(reqs)
  end
  
  def check_req_recursive(req)
    puts "Checking req: #{req}" if @debug
    
    if req == :nonlinear && GAME == "ooe"
      return @options[:open_world_map]
    end
    
    if !@defs[req].nil?
      if @defs[req].is_a?(Integer)
        item_global_id = @defs[req]
        has_item = @current_items.include?(item_global_id)
        @cached_checked_reqs[@defs[req]] = has_item
        return has_item
      elsif PickupRandomizer::RANDOMIZABLE_VILLAGER_NAMES.include?(@defs[req])
        has_villager = @current_items.include?(@defs[req])
        @cached_checked_reqs[@defs[req]] = has_villager
        return has_villager
      elsif PickupRandomizer::PORTRAIT_NAMES.include?(@defs[req])
        has_access_to_portrait = @current_items.include?(@defs[req])
        @cached_checked_reqs[@defs[req]] = has_access_to_portrait
        return has_access_to_portrait
      elsif @defs[req] == true
        return true
      elsif @defs[req] == false
        return false
      end
      
      if @cached_checked_reqs[req] == :currently_checking
        # Don't recurse infinitely checking the same two interdependent requirements.
        return false
      elsif @cached_checked_reqs[req] == true || @cached_checked_reqs[req] == false
        return @cached_checked_reqs[req]
      end
      @cached_checked_reqs[req] = :currently_checking
      
      req_met = check_multiple_reqs_recursive(@defs[req])
      puts "Req #{req} is true" if @debug && req_met
      puts "Req #{req} is false" if @debug && !req_met
      @cached_checked_reqs[req] = req_met
      return req_met
    else
      if !@options[:enable_glitch_reqs] && @glitch_defs.include?(req)
        # When glitches are disabled, always consider a glitch requirement false.
        return false
      end
      raise "Invalid requirement: #{req}"
    end
  end
  
  def check_multiple_reqs_recursive(or_reqs)
    return true if or_reqs.nil?
    
    or_reqs.each do |and_reqs|
      or_req_met = and_reqs.all? do |and_req|
        check_req_recursive(and_req)
      end
      
      puts "Req #{or_reqs} is true (AND req: #{and_reqs})" if @debug && or_req_met
      return true if or_req_met
    end
    
    puts "Req #{or_reqs} is false" if @debug
    return false
  end
  
  def all_locations
    @all_locations ||= begin
      all_locations = {}
      
      @room_reqs.each do |room_str, room_req|
        room_access_reqs = room_req[:room]
        room_entities_reqs = room_req[:entities]
        
        room_entities_reqs.each do |entity_index, entity_reqs|
          entity_str = "#{room_str}_%02X" % entity_index
          all_locations[entity_str] = {room_reqs: room_access_reqs, entity_reqs: entity_reqs}
        end
      end
      
      all_locations
    end
  end
  
  def get_accessible_locations(locations_to_check: all_locations.keys)
    accessible_locations = []
    
    locations_to_check.each do |entity_str|
      room_reqs = all_locations[entity_str][:room_reqs]
      entity_reqs = all_locations[entity_str][:entity_reqs]
      
      if check_reqs(room_reqs) && check_reqs(entity_reqs)
        accessible_locations << entity_str
      end
    end
    
    return accessible_locations
  end
  
  def initialize_all_progression_pickups
    if !@all_progression_pickups.nil?
      raise "all_progression_pickups was initialized too early."
    end
    
    @all_progression_pickups = begin
      pickups = []
      
      @defs.each do |name, req|
        pickups << req if req.is_a?(Integer)
      end
      if GAME == "ooe"
        pickups += PickupRandomizer::RANDOMIZABLE_VILLAGER_NAMES
      end
      if GAME == "por"
        pickups += PickupRandomizer::PORTRAIT_NAMES
        pickups -= @removed_portraits
      end
      
      pickups
    end
  end
  
  def pickups_by_current_num_locations_they_access
    orig_current_items = @current_items
    
    possibly_useful_pickups = all_progression_pickups - @current_items
    
    # Subtract no_progression_locations since we don't want those messing up the numbers.
    currently_accessible_locations = get_accessible_locations() - no_progression_locations
    
    pickups_by_locations = {}
    
    possibly_useful_pickups.each do |pickup_global_id|
      @current_items = orig_current_items + [pickup_global_id]
      new_accessible_locations = get_accessible_locations() - no_progression_locations
      next_accessible_pickups = new_accessible_locations - currently_accessible_locations
      
      pickups_by_locations[pickup_global_id] = next_accessible_pickups.length
    end
    
    return pickups_by_locations
  ensure
    @current_items = orig_current_items
  end
  
  def add_item(new_item_global_id)
    @current_items << new_item_global_id
  end
  
  def restore_current_items(prev_current_items)
    @current_items = prev_current_items.dup
  end
  
  def set_red_wall_souls(red_wall_souls)
    @defs[:red_wall_soul_0] = red_wall_souls[0]
    @defs[:red_wall_soul_1] = red_wall_souls[1]
    @defs[:red_wall_soul_2] = red_wall_souls[2]
    @defs[:red_wall_soul_3] = red_wall_souls[3]
  end
  
  def set_removed_portraits(removed_portraits)
    if GAME != "por"
      raise "Cannot set removed portraits in any game but PoR"
    end
    
    @removed_portraits = removed_portraits
    
    if removed_portraits.empty?
      @defs[:four_seal_bosses_killed] = [[:bosswerewolf, :bossmummy, :bossmedusa, :bosscreature]]
    else
      portraits_needed = PickupRandomizer::PORTRAIT_NAMES - [:portrait_nest_of_evil] - removed_portraits
      
      bosses_needed = portraits_needed.map do |portrait_name|
        case portrait_name
        when :portrait_city_of_haze
          :bossdullahan
        when :portrait_sandy_grave
          :bossastarte
        when :portrait_nation_of_fools
          :bosslegion
        when :portrait_forest_of_doom
          :bossdagon
        when :portrait_dark_academy
          :bosscreature
        when :portrait_burnt_paradise
          :bossmedusa
        when :portrait_forgotten_city
          :bossmummy
        when :portrait_13th_street
          :bosswerewolf
        else
          raise "Invalid portrait name: #{portrait_name}"
        end
      end
      
      @defs[:four_seal_bosses_killed] = [bosses_needed]
      
      # Update the requirements for completing the Nest of Evil quest to only require the portraits that weren't removed.
      nest_of_evil_quest_reqs = portraits_needed.map do |portrait_name|
        case portrait_name
        when :portrait_city_of_haze
          :cityofhaze
        when :portrait_sandy_grave
          :sandygrave
        when :portrait_nation_of_fools
          :nationoffools
        when :portrait_forest_of_doom
          :forestofdoom
        when :portrait_dark_academy
          :darkacademy
        when :portrait_burnt_paradise
          :burntparadise
        when :portrait_forgotten_city
          :forgottencity
        when :portrait_13th_street
          :"13thstreet"
        else
          raise "Invalid portrait name: #{portrait_name}"
        end
      end
      @defs[:can_complete_nest_of_evil_quest] = [nest_of_evil_quest_reqs]
      
      # Now update the actual game code that checks the map percentage for teh quest.
      num_area_maps_required = 1 + portraits_needed.size
      total_percent_required = ((num_area_maps_required-1)*100) + ((num_area_maps_required-1)*10) + (num_area_maps_required-1)
      if total_percent_required > 888
        total_percent_required = 888
      end
      game.fs.write(0x02041458, [total_percent_required*10].pack("V"))
      
      # Also update the description of the quest to reflect the new percentage.
      text = game.text_database.text_list[0x65C]
      File.write("tmp.txt", text.decoded_string)
      text.decoded_string = ("When %d%% of the map is filled,\n" % total_percent_required) +
        "the path to the \"Nest of Evil\"\n"
        "will open at the castle gates."
    end
  end
  
  def remove_13th_street_and_burnt_paradise_boss_death_prerequisites
    # Remove 13th street's mummy requirement.
    game.fs.write(0x02078FC4+3, [0xEA].pack("C")) # Change conditional branch to unconditional branch.
    @defs[:"13thstreet"] = [[:portrait_13th_street]] # Update the pickup requirement for the logic.
    
    # Remove burnt paradise's creature requirement.
    game.fs.write(0x02079008+3, [0xEA].pack("C")) # Change conditional branch to unconditional branch.
    @defs[:burntparadise] = [[:portrait_burnt_paradise]] # Update the pickup requirement for the logic.
  end
  
  def remove_aguni_paranoia_requirement
    # Remove the logic that you need the Paranoia soul to defeat Aguni since this is not true in boss randomizer.
    @defs[:can_kill_aguni] = true
  end
  
  def generate_empty_item_requirements_file
    File.open("./dsvrandom/#{GAME}_pickup_requirements.txt", "w+") do |f|
      prev_area_name = nil
      prev_sector_name = nil
      game.each_room do |room|
        pickups = room.entities.select{|e| e.is_pickup? || e.is_item_chest? || e.is_money_chest? || e.is_glyph_statue?}
        next if pickups.empty?
        
        area_name = AREA_INDEX_TO_AREA_NAME[room.area_index]
        if area_name != prev_area_name
          f.puts "#%s:" % area_name
          prev_area_name = area_name
        end
        
        if SECTOR_INDEX_TO_SECTOR_NAME[room.area_index]
          sector_name = SECTOR_INDEX_TO_SECTOR_NAME[room.area_index][room.sector_index]
          if sector_name != prev_sector_name
            f.puts "#%s:" % sector_name
            prev_sector_name = sector_name
          end
        end
        
        f.puts "  %02X-%02X-%02X:" % [room.area_index, room.sector_index, room.room_index]
        f.puts "    room: "
        pickups.each do |e|
          i = room.entities.index(e)
          
          name = get_item_name_for_generated_reqs_file(e)
          hidden_string = ""
          hidden_string = " (Hidden)" if e.is_hidden_pickup?
          f.puts "    %02X (%s)#{hidden_string}: " % [i, name]
        end
      end
    end
  end
  
  def get_item_name_for_generated_reqs_file(pickup)
    if pickup.is_heart?
      return "Heart"
    end
    if pickup.is_money_bag?
      return "Money"
    end
    if pickup.is_item?
      if GAME == "ooe"
        item_id = pickup.var_b - 1
        item = game.items[item_id]
        return item.name
      else
        item_type_index = pickup.subtype
        item_index = pickup.var_b
        item = game.get_item_by_type_and_index(item_type_index, item_index)
        return item.name
      end
    end
    if pickup.is_glyph?
      item_id = pickup.var_b - 1
      item = game.items[item_id]
      return item.name
    end
    if pickup.is_skill?
      item_type_index = PICKUP_SUBTYPES_FOR_SKILLS.begin
      item_index = pickup.var_b
      item = game.get_item_by_type_and_index(item_type_index, item_index)
      return item.name
    end
    if pickup.is_item_chest?
      item_id = pickup.var_a - 1
      item = game.items[item_id]
      return item.name
    end
    if pickup.is_glyph_statue?
      item_id = pickup.var_b - 1
      item = game.items[item_id]
      return item.name
    end
    if pickup.is_money_chest?
      return "Money Chest"
    end
  end
end

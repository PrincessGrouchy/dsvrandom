
module StartingRoomRandomizer
  def randomize_starting_room
    if GAME == "por"
      game.apply_armips_patch("por_fix_top_screen_on_new_game")
    end
    if GAME == "ooe"
      game.apply_armips_patch("ooe_fix_top_screen_on_new_game")
    end
    
    rooms = []
    if GAME == "por"
      area_indexes_of_removed_portraits = @portraits_to_remove.map do |portrait_name|
        PickupRandomizer::PORTRAIT_NAME_TO_AREA_INDEX[portrait_name]
      end
    end
    game.each_room do |room|
      next if room.layers.length == 0
      
      room_doors = filter_valid_doors_for_starting_door(room.doors)
      next if room_doors.empty?
      
      if GAME == "dos"
        # Limit to save rooms.
        next unless room.entities.find{|e| e.is_save_point?}
      else
        # Limit to warp rooms.
        next unless room.entities.find{|e| e.is_warp_point?}
      end
      
      next if room.area.name.include?("Boss Rush")
      next if room.sector.name.include?("Boss Rush")
      
      next if room.sector.name == "The Abyss"
      next if room.sector.name == "Condemned Tower & Mine of Judgment" && room.room_ypos_on_map >= 0x17
      
      next if room.area.name == "Nest of Evil"
      next if room.sector.name == "The Throne Room"
      next if room.sector.name == "Master's Keep" && room.sector_index == 0xC # Cutscene where Dracula dies
      if GAME == "por" && area_indexes_of_removed_portraits.include?(room.area_index)
        # Don't allow starting inside a portrait that was removed by Short Mode.
        next
      end
      
      next if room.area.name == "Training Hall"
      next if room.area.name == "Large Cavern"
      next if room.sector.name == "Final Approach"
      if GAME == "ooe" && room.area_index == 0
        # Don't allow starting in Dracula's Castle in OoE.
        next
      end
      
      next if room.entities.find{|e| e.is_boss?}
      
      next if @unused_rooms.include?(room)
      
      rooms << room
    end
    
    rooms_with_access_to_progress = rooms.select do |room|
      # Limit to rooms where the player can access at least 3 item locations. Otherwise the player could be stuck right at the start with no items.
      room_doors = filter_valid_doors_for_starting_door(room.doors)
      door = room_doors[0]
      door_index = room.doors.index(door)
      checker.set_starting_room(room, door_index)
      accessible_locations, accessible_doors = checker.get_accessible_locations_and_doors()
      accessible_locations.size > 3
    end
    if rooms_with_access_to_progress.any? # Only limit to rooms with access to progress if there actually are any like that.
      rooms = rooms_with_access_to_progress
    end
    
    # Limit potential starting rooms by how powerful common enemies in their subsector are on average (in the base game, not after enemies are randomized).
    subsector_difficulty_for_each_room = {}
    @enemy_difficulty_by_subsector.each do |rooms_in_subsector, difficulty|
      (rooms & rooms_in_subsector).each do |room|
        subsector_difficulty_for_each_room[room] = difficulty
      end
    end
    #subsector_difficulty_for_each_room.sort_by{|k,v| p v; v}.each do |room, difficulty|
    #  puts "#{room.room_str}: #{difficulty.round(4)}"
    #end
    possible_rooms = subsector_difficulty_for_each_room.select do |room, difficulty|
      difficulty <= @difficulty_settings[:starting_room_max_difficulty]
    end.keys
    if possible_rooms.empty?
      # If no rooms meet the difficulty threshold just use rooms with the lowest threshold.
      min_difficulty = subsector_difficulty_for_each_room.values.min
      possible_rooms = subsector_difficulty_for_each_room.select{|room, difficulty| difficulty == min_difficulty}.keys
    end
    
    room = possible_rooms.sample(random: rng)
    
    room_doors = filter_valid_doors_for_starting_door(room.doors)
    door = room_doors[0] # .sample(random: rng)
    x_pos, y_pos = get_start_pos_for_door(door)
    
    if GAME == "dos"
      # In DoS we don't want to actually change the starting room, we instead change where the prologue cutscene teleports you to, so you still go through the tutorial.
      
      game.fs.write(0x021C74CC, [0xE3A00000].pack("V")) # Change this to a constant mov first
      # Then replace the sector and room indexes.
      game.fs.write(0x021C74CC, [room.sector_index].pack("C"))
      game.fs.write(0x021C74D0, [room.room_index].pack("C"))
      # And the x/y position in the room.
      # The x/y are going to be arm shifted immediates, so they need to be rounded down to the nearest 0x10 to make sure they don't use too many bits.
      if x_pos > 0x100
        x_pos = x_pos/0x10*0x10
      end
      if y_pos > 0x100
        y_pos = y_pos/0x10*0x10
      end
      game.fs.replace_arm_shifted_immediate_integer(0x021C74D4, x_pos)
      game.fs.replace_arm_shifted_immediate_integer(0x021C74D8, y_pos)
      
      # And then we do that all again for the code that runs if the player skips the prologue cutscene by pressing start.
      game.fs.write(0x021C77E4, [0xE3A00000].pack("V"))
      game.fs.write(0x021C77E4, [room.sector_index].pack("C"))
      game.fs.write(0x021C77E8, [room.room_index].pack("C"))
      game.fs.replace_arm_shifted_immediate_integer(0x021C77EC, x_pos)
      game.fs.replace_arm_shifted_immediate_integer(0x021C77F0, y_pos)
    else
      game.set_starting_room(room.area_index, room.sector_index, room.room_index)
      game.set_starting_position(x_pos, y_pos)
    end
    
    if GAME != "dos"
      add_save_or_warp_to_room(room, :save)
    end
    
    @starting_room = room
    @starting_room_door_index = room.doors.index(door)
    @starting_x_pos = x_pos
    @starting_y_pos = y_pos
    
    log_str = "Starting room: #{@starting_room.room_str}"
    puts log_str
    spoiler_log.puts log_str
  end
  
  def filter_valid_doors_for_starting_door(doors)
    room_doors = doors.reject{|door| checker.inaccessible_doors.include?(door.door_str)}
    room_doors.select!{|door| door.direction == :left || door.direction == :right}
    room_doors.reject!{|door| check_door_underwater(door)}
    return room_doors
  end
  
  def get_start_pos_for_door(door)
    gap_start_index, gap_end_index, tiles_in_biggest_gap = get_biggest_door_gap(door)
    
    case door.direction
    when :left
      x_pos = 0x10
      y_pos = door.y_pos*SCREEN_HEIGHT_IN_PIXELS
      y_pos += gap_end_index*0x10 + 0x10
    when :right
      x_pos = door.x_pos*SCREEN_WIDTH_IN_PIXELS-0x10
      y_pos = door.y_pos*SCREEN_HEIGHT_IN_PIXELS
      y_pos += gap_end_index*0x10 + 0x10
    when :up
      y_pos = 0
      x_pos = door.x_pos*SCREEN_WIDTH_IN_PIXELS
      x_pos += gap_end_index*0x10
    when :down
      y_pos = door.y_pos*SCREEN_HEIGHT_IN_PIXELS-1
      x_pos = door.x_pos*SCREEN_WIDTH_IN_PIXELS
      x_pos += gap_end_index*0x10
    end
    
    return x_pos, y_pos
  end
  
  def check_door_underwater(door)
    x_pos, y_pos = get_start_pos_for_door(door)
    coll = get_room_collision(door.room)
    
    starting_tile = coll[x_pos, y_pos-0x10]
    if starting_tile.is_water
      return true
    end
    
    return false
  end
  
  def update_game_end_default_save_rooms
    # If you get an ending without saving the game once, the save file created by the ending will default you to the first save room accessible in the vanilla game.
    # That's not desirable in room rando, so update the save room used in this case.
    case GAME
    when "dos"
      # This one set of addresses affects both bad endings and the good ending.
      game.fs.replace_arm_shifted_immediate_integer(0x02010E60, @starting_room.sector_index)
      game.fs.replace_arm_shifted_immediate_integer(0x02010E6C, @starting_room.room_index)
      
      # Don't update the X and Y pos, since this is used even for non-default save rooms (the last save the player used before beating the game).
      # If the starting save room has a door on the right but the last used save has one on the left, the player will be thrown out of bounds when reloading after beating the game.
      #game.fs.replace_arm_shifted_immediate_integer(0x02010E90, @starting_x_pos*0x1000)
      #game.fs.replace_arm_shifted_immediate_integer(0x02010E98, @starting_y_pos*0x1000)
    when "por"
      # This one set of addresses affects both the bad ending and the good ending.
      game.fs.replace_arm_shifted_immediate_integer(0x020117E8, @starting_room.area_index)
      game.fs.replace_arm_shifted_immediate_integer(0x020117F4, @starting_room.sector_index)
      game.fs.replace_arm_shifted_immediate_integer(0x02011804, @starting_room.room_index)
      
      # Don't update the X and Y pos for the save reason as DoS.
      #game.fs.replace_arm_shifted_immediate_integer(0x02011814, @starting_x_pos*0x1000)
      #game.fs.replace_arm_shifted_immediate_integer(0x0201181C, @starting_y_pos*0x1000)
    end
  end
end


module StartingItemsRandomizer
  def randomize_starting_items
    non_progress_items = all_non_progression_pickups & ITEM_GLOBAL_ID_RANGE.to_a
    non_progress_skills = all_non_progression_pickups & SKILL_GLOBAL_ID_RANGE.to_a
    if GAME == "ooe"
      # Need to give the player at least one free glyph, or they may not be able to open the glyph statue and get a weapon.
      free_glyph_attack_glyph_ids = [0x1D, 0x1F, 0x20, 0x22, 0x24, 0x26, 0x27, 0x2A, 0x2B, 0x2F, 0x30, 0x31, 0x32]
      starting_pickups = [free_glyph_attack_glyph_ids.sample(random: rng)]
      non_progress_skills -= starting_pickups
      starting_pickups += non_progress_items.sample(3, random: rng) + non_progress_skills.sample(2, random: rng)
    else
      starting_pickups = non_progress_items.sample(3, random: rng) + non_progress_skills.sample(3, random: rng)
    end
    
    room = @starting_room
    @coll = RoomCollision.new(room, game.fs)
    room_str = "%02X-%02X-%02X" % [room.area_index, room.sector_index, room.room_index]
    starting_pickups.each do |pickup_global_id|
      puts "%03X" % pickup_global_id
      entity = Entity.new(room, room.fs)
      
      entity.x_pos = 0x80 - 0x10
      entity.y_pos = 0x60
      
      y = coll.get_floor_y(entity, allow_jumpthrough: true)
      unless y.nil?
        entity.y_pos = y
      end
      
      room.entities << entity
      room.write_entities_to_rom()
      
      location = "#{room_str}_%02X" % (room.entities.length-1)
      change_entity_location_to_pickup_global_id(location, pickup_global_id)
    end
  end
end
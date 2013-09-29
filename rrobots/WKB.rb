require 'robot'

class WKB
  include Robot

  # Constants
  if !self.const_defined?(:FIRE_MIN)
    FIRE_MIN, FIRE_MAX = 0, 3
    TURN_MIN, TURN_MAX = -10, 10
    TURN_GUN_MIN, TURN_GUN_MAX = -30, 30
    TURN_RADAR_MIN, TURN_RADAR_MAX = -60, 60
    ACCELERATE_MIN, ACCELERATE_MAX = -1, 1
    BULLET_TIME_ENERGY_RATIO = 0.3
    WALL_PROXIMITY = 200
  end

  # Heading class - Holds an angle value to modulo 360
  class Heading
    attr_reader :value
    def initialize(value); self.value = value; end
    def value=(new_value); @value = new_value % 360; end
    def to_f; self.value; end
    def to_s; self.value.to_s; end
    def to_rad; self.value.to_rad; end
    def +(other); Heading.new(self.value + other.to_f); end
    def -(other); Heading.new(self.value - other.to_f); end
    def ==(other); (self.value - other.value) < 0.001; end
    def delta_to(other); (179 + other.value - self.value) % 360 - 179; end
  end

  # Sector class - Hold a pair of headings indicating a sector to scan
  class Sector
    attr_accessor :left, :right
    def initialize(left,right); self.left = left; self.right = right; end
    def [](index); index == 1 ? self.right : self.left; end
    def []=(index,value)
      if index == 1
        self.right = value
      else
        self.left = value
      end
    end
    def delta; self.left.delta_to(self.right); end
    def split; self.left + self.delta / 2; end
  end

  # Scan class - Holds a single scan of a target
  class Scan
    attr_reader :time,:x,:y
    def initialize(time,x,y); @time,@x,@y = time,x,y; end
    def range(my_x,my_y); Math::hypot(my_x - @x,my_y - @y); end
  end

  # Targets class - Holds a history of scanned targets
  class Targets
    if !self.const_defined?(:MAX_TICKS)
      MAX_TICKS = 10
      BULLET_SPEED = 30
    end
    def initialize; @list = []; end
    def tick(current_time)
      @list.delete_if { |target| target.time < current_time - MAX_TICKS}
    end
    def add(current_time,my_x,my_y,heading,range)
      @list << Scan.new(
        current_time,
        my_x + Math::cos(heading.to_rad) * range,
        my_y + Math::sin(heading.to_rad) * range
      )
    end
    def aim(current_time,my_x,my_y)
      return nil if @list.length < 2
      delta_time = (@list[-1].time - @list[-2].time).to_f
      v_x = (@list[-1].x - @list[-2].x) / delta_time
      v_y = (@list[-1].y - @list[-2].y) / delta_time
      estimated_time = (@list[-1].range(my_x,my_y) / BULLET_SPEED) + 
                       current_time + 2 - @list[-1].time
      estimated_x = @list[-1].x + v_x * estimated_time
      estimated_y = @list[-1].y + v_y * estimated_time
      Heading.new(
        Math::atan2(estimated_y - my_y, estimated_x - my_x) * 180.0 / Math::PI
      )
    end
  end

  # Movement class - Responsible for moving the robot
  class Movement
    if !self.const_defined?(:ANGLE_TOWARDS)
      ANGLE_TOWARDS = 75
      ANGLE_AWAY = 105
      WAIT_TIME = 30
    end
    def initialize
      @angle = ANGLE_TOWARDS
      @direction = 1
      @dodge_time = nil
      @reverse_hold_time = 0
    end
    def move_towards; @angle = ANGLE_TOWARDS; end
    def move_away; @angle = ANGLE_AWAY; end
    def direction; @direction; end
    def angle; @angle * @direction; end
    def tick(current_time,range,time_to_next_bullet,near_wall)
      need_to_reverse = time_to_next_bullet > 0 || near_wall
      if time_to_next_bullet > WAIT_TIME / 2
        @dodge_time = current_time + time_to_next_bullet - WAIT_TIME / 2
        @reverse_hold_time = 0
      elsif (@dodge_time && current_time >= @dodge_time) ||
          (need_to_reverse && current_time >= @reverse_hold_time)
        @dodge_time = nil
        @reverse_hold_time = current_time + WAIT_TIME
        @direction = -@direction
      end
      if range
        @angle = (range > 500) ? ANGLE_TOWARDS : ANGLE_AWAY
      end
    end
  end

  # Utilities
  def heading; Heading.new(state[:heading]); end
  def gun_heading; Heading.new(state[:gun_heading]); end
  def radar_heading; Heading.new(state[:radar_heading]); end
  def bound_value(value,min,max)
    return min if value < min
    return max if value > max
    value
  end
  def change_mode(mode,events)
    @search_mode = mode
    send(@search_mode,events)
  end

  # Startup
  def startup
    @targets = Targets.new
    @movement = Movement.new
    @last_energy = energy
    @predicted = nil
    start_search
  end

  # Aim
  def aim(new_radar_heading)
    @predicted = new_gun_heading = @targets.aim(time,x,y) 
    new_gun_heading = new_radar_heading unless new_gun_heading
    new_turn =
      bound_value(
        heading.delta_to(new_gun_heading + @movement.angle),
        TURN_MIN,TURN_MAX
      )
    new_turn_gun =
      bound_value(
        gun_heading.delta_to(new_gun_heading) - new_turn,
        TURN_GUN_MIN,TURN_GUN_MAX
      )
    new_turn_radar =
      bound_value(
        radar_heading.delta_to(new_radar_heading) - (new_turn + new_turn_gun),
        TURN_RADAR_MIN, TURN_RADAR_MAX
      )
    turn(new_turn)
    turn_gun(new_turn_gun)
    turn_radar(new_turn_radar)
  end

  # Search modes
  def start_search
    @search_mode = :search_acquire_target
    @search_direction = 1
    @search_sector = Sector.new(radar_heading,radar_heading)
  end

  def search_acquire_target(events)
    unless events['robot_scanned'].empty?
      return change_mode(:narrow_search,events)
    end
    @search_sector[-@search_direction] = radar_heading
    turn(@search_direction < 0 ? TURN_MIN : TURN_MAX)
    turn_gun(@search_direction < 0 ? TURN_GUN_MIN : TURN_GUN_MAX)
    turn_radar(@search_direction < 0 ? TURN_RADAR_MIN : TURN_RADAR_MAX)
  end

  def narrow_search(events)
    if @search_sector.delta <= 1.0 && events['robot_scanned'].empty?
      @search_direction = -@movement.direction
      return change_mode(:broaden_search,events)
    end
    if events['robot_scanned'].empty?
      @search_sector[-@search_direction] = radar_heading
    else
      @search_sector[@search_direction] = radar_heading
      @search_direction = -@search_direction
      if @search_sector.delta <= 2
        @targets.add(
          time,
          x,
          y,
          @search_sector.split,
          events['robot_scanned'].flatten.min
        )
      end
    end
    aim(@search_sector.split)
  end

  def broaden_search(events)
    unless events['robot_scanned'].empty?
      return change_mode(:narrow_search,events)
    end
    if @search_sector.delta > (TURN_MAX + TURN_GUN_MAX + TURN_RADAR_MAX) / 2
      return change_mode(:search_acquire_target,events)
    end
    @search_direction = -@search_direction
    @search_sector[@search_direction] +=
      @search_sector[-@search_direction].delta_to(
        @search_sector[@search_direction]
      ) * 2
    aim(@search_sector[@search_direction])
  end

  def tick events
    startup if time == 0
    accelerate(1)
    fire(@predicted ? 3.0 : 0.1)
    @targets.tick(time)
    range = events['robot_scanned'].empty? ?
            nil :
            events['robot_scanned'].flatten.min 
    time_to_next_bullet = (@last_energy - energy) / BULLET_TIME_ENERGY_RATIO
    near_wall = x                                   < WALL_PROXIMITY ||
                battlefield_width  - WALL_PROXIMITY < x              ||
                y                                   < WALL_PROXIMITY ||
                battlefield_height - WALL_PROXIMITY < y
    @movement.tick(time,range,time_to_next_bullet,near_wall)
    send(@search_mode,events)
    @last_energy = energy
  end
end

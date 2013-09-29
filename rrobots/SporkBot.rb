require 'robot'
require 'matrix'

class Numeric
  def to_rad
    self * 0.0174532925199433
  end
  
  def to_deg
    self * 57.2957795130823
  end
  
  def round_f(degrees=3)
    return (self * (10 ** degrees)).round / (10 ** degrees).to_f
  end
end

class SporkBot
  class Configuration
    attr_accessor :midpoint_grav_force
    attr_accessor :enemy_grav_force
    attr_accessor :min_scan_width
    attr_accessor :max_scan_width
    attr_accessor :target_change_frequency
    attr_accessor :oldest_target_allowed
    attr_accessor :targetting_angle_threshold
    attr_accessor :targetting_distance_threshold
    attr_accessor :target_history_size
    
    def initialize
      @midpoint_grav_force = 600
      @enemy_grav_force = 1000
      @min_scan_width = 3
      @max_scan_width = 25
      @target_change_frequency = 30
      @oldest_target_allowed = 10
      @targetting_angle_threshold = 30
      @targetting_distance_threshold = 200
      @target_history_size = 8
    end
  end
  
  module Calculations
    # Universal distance algorithm
    def distance(x1, y1, x2, y2 )
      return Math.hypot((x2 - x1), (y2 - y1))
    end
  
    # Gets the bearing from point 1 to point 2
    def bearing(x1, y1, x2, y2 )
  		dx, dy = x2 - x1, y2 - y1
  		magnitude = distance( x1, y1, x2, y2 )
  		if( dx >= 0 && dy >= 0 ) || ( dx <= 0 && dy >= 0 )
    		theta = Math.acos(-dx / magnitude) + Math::PI
  		elsif ( dx >= 0 && dy <= 0 ) || ( dx <= 0 && dy <= 0 )
    		theta = Math.acos(dx / magnitude)
  		end
  		return 0 if magnitude == 0
  		theta = theta - (Math::PI * 2) if theta >= (Math::PI * 2)
  		return theta
  	end
  	
  	# Gets the location of an object given the heading and distance
  	def location(x, y, theta, distance)
  	  return [
  	    x + distance * Math.cos(theta),
  	    y - distance * Math.sin(theta)
  	  ]
  	end
  	
  	# Normalizes a bearing to -PI to PI range
  	def normalize_bearing(angle)
  	  return ((angle + Math::PI) % (2 * Math::PI)) - Math::PI
  	end

  	# Normalizes a bearing to 0 to 2*PI range
  	def normalize_heading(angle)
  	  return angle % (2 * Math::PI)
  	end
  	
  	# Returns the shortest angle between the two angles
  	def angle_delta(angle1, angle2)
  	  delta = (angle1 - angle2).abs
  	  if delta >= Math::PI
  	    delta = (((2 * Math::PI) - angle1) + angle2).abs
  	  end
  	  return delta
  	end

  	# Returns the angle bisector of the two angles
  	def angle_bisect(angle1, angle2)
  	  bisector = (2 * Math::PI + angle1 + angle2).abs / 2.0
  	  if angle_delta(bisector, angle1) >= (Math::PI / 2.0)
  	    bisector = (angle1 + angle2).abs / 2.0
  	  end
  	  return bisector
  	end
  end
    
  class Enemy
    include SporkBot::Calculations

    def Enemy.history_size
      return @@history_size
    end

    def Enemy.history_size=(new_history_size)
      @@history_size = new_history_size
    end
    
    def initialize
      @x_history = []
      @y_history = []
      @scan_time_history = []
    end
    
    def x
      return @x_history.last
    end

    def y
      return @y_history.last
    end
    
    def scan_time
      return @scan_time_history.last
    end
    
    def x=(new_x)
      @x_history << new_x
      @x_history.shift if @x_history.size > Enemy.history_size
    end

    def y=(new_y)
      @y_history << new_y
      @y_history.shift if @y_history.size > Enemy.history_size
    end

    def scan_time=(new_scan_time)
      @scan_time_history << new_scan_time
      @scan_time_history.shift if @scan_time_history.size > Enemy.history_size
    end
    
    def heading
      if @x_history.size > 1 || @y_history.size > 1 ||
          @scan_time_history.size > 1
        position1 = [@x_history[-1], @y_history[-1]]
        position2 = [@x_history[-2], @y_history[-2]]
        return bearing(position2[0], position2[1],
          position1[0], position1[1]).to_deg
      else
        return 0
      end
    end
    
    def speed
      if @x_history.size > 1 || @y_history.size > 1 ||
          @scan_time_history.size > 1
        position1 = [@x_history[-1], @y_history[-1]]
        position2 = [@x_history[-2], @y_history[-2]]
        scan_time_delta =
          (@scan_time_history[-1] - @scan_time_history[-2]).abs
        return [distance(position1[0], position1[1],
          position2[0], position1[1]) /
          scan_time_delta, 8].min
      else
        return 0
      end
    end
    
    def average_position
  	  x_total, y_total, count = 0.0, 0.0, 0.0
  	  for i in 0...@scan_time_history.size
  	    x_total += @x_history[i] * (i + 1)
  	    y_total += @y_history[i] * (i + 1)
  	    count += (i + 1)
  	  end
  	  x_avg = x_total / count
  	  y_avg = y_total / count
  	  return [x_avg, y_avg]
    end
	
  	def guess_position(time)
  	  time_delta = time - self.scan_time
  	  distance = self.speed * time_delta
  	  new_position = location(self.x, self.y, self.heading.to_rad, distance)
  	  conservative_position = self.average_position
  	  conservative_position[0] =
  	    (2 * conservative_position[0] + new_position[0]) / 3
  	  conservative_position[1] =
  	    (2 * conservative_position[1] + new_position[1]) / 3
  	  return self.average_position
  	end
  end

  class GravityPoint
    attr_accessor :x
    attr_accessor :y
    attr_accessor :power
  
    def initialize(x, y, power)
      @x = x
      @y = y
      @power = power
    end
  end

  include Robot
  include SporkBot::Calculations
  
  def initialize
    @sequences = {
      :hull => nil,
      :gun => nil,
      :radar => nil
    }
    @all_targets = []
    @current_target = nil
    @last_target_change = nil
    @previous_radar_heading = radar_heading
    @midpoint_strength = 0
    @midpoint_count = 0
    @destination = nil
    @target_locked = false
    @mode = :free_for_all
    @config = Configuration.new
    Enemy.history_size = @config.target_history_size
  end

  def tick events
    handle_modes
		handle_target_selection
    handle_move
    handle_throttle
		handle_scanner
		handle_scanned_robot
    handle_target_pruning
		handle_aim
		handle_fire_power
		handle_firing
    handle_sequences
  end
  
  def handle_modes
    @target_count_total = 0 if @target_count_total.nil?
    @target_count_total += @all_targets.size
    if @target_count_total / (time + 1) <= 0.35
      @mode = :one_vs_one
    else
      @mode = :free_for_all
    end
  end
  
  def handle_target_selection
    if @all_targets.size == 0
      @current_target = nil
    elsif @all_targets.size == 1
      @current_target = @all_targets.first
      @last_target_change = time
    elsif @last_target_change.nil? ||
        @last_target_change + @config.target_change_frequency < time
      theta = angle_bisect(
        radar_heading.to_rad, @previous_radar_heading.to_rad).to_deg
      best_target_by_angle = nil
      best_theta_diff = nil
      best_target_by_scan_time = nil
      best_scan_time = nil
      best_target_by_distance = nil
      best_distance = nil
      for enemy in @all_targets
        required_theta = bearing(x, y, enemy.x, enemy.y)
        if best_theta_diff.nil? ||
            (theta - required_theta).abs < best_theta_diff
          best_theta_diff = (theta - required_theta).abs
          best_target_by_angle = enemy
        end
        if best_scan_time.nil? ||
            enemy.scan_time >= best_scan_time
          best_scan_time = enemy.scan_time
          best_target_by_scan_time = enemy
        end
        if best_distance.nil? ||
            distance(x, y, enemy.x, enemy.y) < best_distance
          best_distance = distance(x, y, enemy.x, enemy.y)
          best_target_by_distance = enemy
        end
      end
      if best_target_by_angle == best_target_by_distance &&
          best_target_by_angle == best_target_by_scan_time
        @current_target = best_target_by_angle
      elsif best_target_by_distance == best_target_by_angle &&
          best_target_by_distance == best_target_by_scan_time
        @current_target = best_target_by_distance
      end
      if best_distance < 50 && best_theta_diff > 40.to_rad
        @current_target = best_target_by_distance
      elsif time - best_target_by_angle.scan_time < 3
        @current_target = best_target_by_angle
      else
        @current_target = best_target_by_scan_time
      end
      @last_target_change = time
    end
  end

  def handle_move
 		xforce, yforce, force = 0, 0, 0
    angle = 0
	  for enemy in @all_targets
			point = GravityPoint.new(enemy.x, enemy.y, -@config.enemy_grav_force)

	    force = point.power / (distance(x, y, point.x, point.y) ** 2)
	    angle = normalize_bearing(
	      Math::PI / 2 - Math.atan2(y - point.y, x - point.x))

	    xforce += Math.cos(angle) * force
	    yforce += Math.sin(angle) * force
	  end

		@midpoint_count += 1
		if (@midpoint_count > 5)
			@midpoint_count = 0;
			@midpoint_strength =
			  rand(@config.midpoint_grav_force * 2) - @config.midpoint_grav_force
		end

		point = GravityPoint.new(
		  battlefield_width / 2,
		  battlefield_height / 2,
		  @midpoint_strength)

		force = point.power / (distance(x, y, point.x, point.y) ** 1.5)
	  angle = normalize_bearing(
	    Math::PI / 2 - Math.atan2(y - point.y, x - point.x))

	  xforce += Math.cos(angle) * force
	  yforce += Math.sin(angle) * force

    xforce += battlefield_width / (distance(x, y, battlefield_width, y) ** 3)
    xforce += 1.0 if distance(x, y, battlefield_width, y) < size * 2
    xforce -= battlefield_width / (distance(x, y, 0, y) ** 3)
    xforce -= 1.0 if distance(x, y, 0, y) < size * 2
    yforce += battlefield_height / (distance(x, y, x, battlefield_height) ** 3)
    yforce += 1.0 if distance(x, y, x, battlefield_height) < size * 2
    yforce -= battlefield_height / (distance(x, y, x, 0) ** 3)
    yforce -= 1.0 if distance(x, y, x, 0) < size * 2

	  turn_towards(x - xforce, y - yforce)
  end
  
  def handle_throttle
    if distance(x, y, battlefield_width, y) < size * 4
      accelerate 1
    elsif distance(x, y, 0, y) < size * 4
      accelerate 1
    elsif distance(x, y, x, battlefield_height) < size * 4
      accelerate 1
    elsif distance(x, y, x, 0) < size * 4
      accelerate 1
    else
      accelerate(Math.sin(time * 0.1) * 2.0 + 0.8)
    end
  end
  
  def turn_towards(new_x, new_y)
    angle = bearing(x, y, new_x, new_y).to_deg
    @sequences[:hull] = angle
  end
  
  def handle_scanner
    if @current_target == nil
      turn_radar 20
    elsif @sequences[:radar].nil?
      enemy_guess = @current_target.guess_position(time)
      enemy_point = [@current_target.x, @current_target.y]
      bearing_to_target_guess =
        bearing(x, y, enemy_guess[0], enemy_guess[1]).to_deg
      bearing_to_target_point =
        bearing(x, y, enemy_point[0], enemy_point[1]).to_deg
      if angle_delta(radar_heading.to_rad,
          bearing_to_target_guess.to_rad) > 40 &&
          (time - @current_target.scan_time) < 3
        @sequences[:radar] = bearing_to_target_guess
      elsif angle_delta(radar_heading.to_rad,
          bearing_to_target_point.to_rad) > 40 &&
          (time - @current_target.scan_time) < 2
        @sequences[:radar] = bearing_to_target_point
      else
        unless events['robot_scanned'].empty?
          new_angle = angle_bisect(angle_bisect(
            radar_heading.to_rad, @previous_radar_heading.to_rad),
            @previous_radar_heading.to_rad).to_deg
          distance = distance(x, y, enemy_guess[0], enemy_guess[1])
          ideal_scan_width =
            [[@config.min_scan_width,
            @config.max_scan_width - distance ** 2 / 108000].max,
            @config.max_scan_width].min
          if angle_delta(radar_heading.to_rad, new_angle.to_rad).to_deg < 
              ideal_scan_width
            # Scan width is smaller than ideal, pull it up to ideal
            if new_angle >= radar_heading
              new_angle = radar_heading + ideal_scan_width + (rand * 10) - 5
            else
              new_angle = radar_heading - ideal_scan_width + (rand * 10) - 5
            end
          end
          @sequences[:radar] = new_angle % 360
        else
          if @previous_radar_heading > radar_heading
            @sequences[:radar] = (@previous_radar_heading + 15) % 360
          else
            @sequences[:radar] = (@previous_radar_heading - 15) % 360
          end
        end
      end
    end
  end
  
  def handle_scanned_robot
    unless events['robot_scanned'].empty?
      theta = angle_bisect(
        radar_heading.to_rad, @previous_radar_heading.to_rad).to_deg
      for distance in events['robot_scanned'].flatten.sort
        scan = [time, x, y, theta, distance]
        location = location(x, y, theta.to_rad, distance)
        updated = false
        for enemy in @all_targets
          enemy_point = [enemy.x, enemy.y]
          enemy_guess = enemy.guess_position(time)
          
          if distance(enemy_guess[0], enemy_guess[1],
              location[0], location[1]) <
              @config.targetting_distance_threshold &&
              time - enemy.scan_time <= 6
            enemy.x = location[0]
            enemy.y = location[1]
            enemy.scan_time = time
            updated = true
          elsif @mode == :one_vs_one &&
              distance(enemy_guess[0], enemy_guess[1], location[0],
              location[1]) < (2.0 * @config.targetting_distance_threshold) &&
              time - enemy.scan_time <= 8
            enemy.x = location[0]
            enemy.y = location[1]
            enemy.scan_time = time
            updated = true
          end
        end
        unless updated
          new_enemy = Enemy.new
          new_enemy.x = location[0]
          new_enemy.y = location[1]
          new_enemy.scan_time = time
          @all_targets << new_enemy
        end
      end
    end
  end
  
  def scanned_degrees
    if @previous_radar_heading.nil? || radar_heading.nil?
      return 0.0
    else
      return angle_delta(
        @previous_radar_heading.to_rad, radar_heading.to_rad).to_deg.round_f
    end
  end
  
  def handle_target_pruning
    @all_targets.each do |enemy|
      if time - enemy.scan_time > @config.oldest_target_allowed
        @all_targets.delete enemy
      end
    end
  end
  
  def handle_aim
    unless @current_target == nil
      unless @previous_radar_heading.nil? || radar_heading.nil?
        theta = angle_bisect(
          radar_heading.to_rad, @previous_radar_heading.to_rad).to_deg
        distance_to_target =
          distance(x, y, @current_target.x, @current_target.y)
        enemy_guess = @current_target.guess_position(
          time + (distance_to_target / 30))
        theta = bearing(x, y, enemy_guess[0], enemy_guess[1]).to_deg
        @sequences[:gun] = (theta + rand * 2.0 - 1) % 360
      end
    end
  end
  
  def handle_fire_power
  end
  
  def handle_firing
    if @current_target != nil && !(events['robot_scanned'].empty?)
      fire 3
    end
  end
  
  def handle_sequences
    @previous_radar_heading = radar_heading
    
    hull_degrees_remaining = 0.0
    gun_degrees_remaining = 0.0
    radar_degrees_remaining = 0.0
    if @sequences[:hull] != nil && @sequences[:hull] >= 360
      raise "Hull sequence value out of valid range."
    end
    if @sequences[:gun] != nil && @sequences[:gun] >= 360
      raise "Gun sequence value out of valid range."
    end
    if @sequences[:radar] != nil && @sequences[:radar] >= 360
      raise "Radar sequence value out of valid range."
    end
    if @sequences[:hull] != nil
      hull_degrees_remaining =
        normalize_bearing((heading - @sequences[:hull]).to_rad).to_deg
    end
    if @sequences[:gun] != nil
      gun_degrees_remaining =
        normalize_bearing((gun_heading - @sequences[:gun]).to_rad).to_deg
    end
    if @sequences[:radar] != nil
      radar_degrees_remaining =
        normalize_bearing((radar_heading - @sequences[:radar]).to_rad).to_deg
    end
    if @sequences[:hull] != nil && hull_degrees_remaining != 0.0
      hull_degrees_turning = [-10.0, [hull_degrees_remaining, 10.0].min].max
      turn -hull_degrees_turning

      hull_degrees_remaining -= hull_degrees_turning
      gun_degrees_remaining -= hull_degrees_turning
      radar_degrees_remaining -= hull_degrees_turning
    end
    if @sequences[:gun] != nil && gun_degrees_remaining != 0.0
      gun_degrees_turning = [-30.0, [gun_degrees_remaining, 30.0].min].max
      turn_gun -gun_degrees_turning

      gun_degrees_remaining -= gun_degrees_turning
      radar_degrees_remaining -= gun_degrees_turning
    end
    if @sequences[:radar] != nil && radar_degrees_remaining != 0.0
      radar_degrees_turning = [-60.0, [radar_degrees_remaining, 60.0].min].max
      turn_radar -radar_degrees_turning

      radar_degrees_remaining -= radar_degrees_turning
    end
    if hull_degrees_remaining == 0.0
      @sequences[:hull] = nil
    end
    if gun_degrees_remaining == 0.0
      @sequences[:gun] = nil
    end
    if radar_degrees_remaining == 0.0
      @sequences[:radar] = nil
    end
  end
end

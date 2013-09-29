require 'robot'
require 'matrix'

BOT_MAX_SPEED = 8
BULLET_SPEED = 30

class NotEnoughData < RuntimeError; end

class PredictiveTracker
  def initialize(size = 4)
    @size = size || 4

    @x = Array.new(@size,0) 
    @y = Array.new(@size,0)
    @t = Array.new(@size,0)

    @most_recent = 0
    @solution = nil
  end

  def mark(x,y,time)
    @most_recent = (@most_recent + 1) % @size
    @x[@most_recent] = x
    @y[@most_recent] = y
    @t[@most_recent] = time

    # Update solution, if possible
    @solution = solve
  rescue
  end
  
  def solve
    xoff, vx = linfit(@t, @x)
    yoff, vy = linfit(@t, @y)
    [vx,vy,xoff,yoff]
  end

  # predicts target location at the given time
  def predict(time)
    raise NotEnoughData unless @solution
    vx, vy, xoff, yoff = @solution
    [xoff + vx*time, yoff + vy*time]
  end


  def aim_point(my_x, my_y, time)
    raise NotEnoughData unless @solution
    t = 0
    loop do
      x,y = predict(time+t)
      break if vs(vd([x,y],[my_x,my_y])) < BULLET_SPEED*BULLET_SPEED*t*t
      t += 1
      raise NotEnoughData if t > 100
    end
    predict(time+t)
  end

  def firing_angle(my_x,my_y,time)
    x,y = aim_point(my_x,my_y,time)
    Math.atan2(my_y-y,x-my_x).to_deg
  end


  # returns [a,b] such that a + bx = y is least squares linear fit
  def linfit(x,y)
    sum_x = 0.0
    sum_y = 0.0
    sum_prod = 0.0
    sum_x2 = 0.0
    n = x.size
    n.times {|i| 
      sum_x += x[i]
      sum_y += y[i]
      sum_prod += x[i]*y[i]
      sum_x2 += x[i]*x[i]
    }
    b = (n*sum_prod - sum_x*sum_y) / (n*sum_x2 - sum_x*sum_x)
    a = (sum_y - b*sum_x) / n
    raise NotEnoughData if a.nan? or b.nan?
    [a,b]
  end

  # Vector difference
  def vd(a,b)
    a.zip(b).map{|a,b| a - b}
  end

  # Vector square
  def vs(a)
    dp(a,a)
  end

  # Dot product
  def dp(a,b)
    a.zip(b).map{|a,b| a*b}.inject(0){|a,b| a+b}
  end

end


class EdBot
   include Robot

  def tick events
    startup if time == 0
    update_radar(events)
    update_gun
    update_heading

    accelerate 1

    turn_radar(radar_velocity - @gun_velocity - @angular_velocity)
    turn_gun(@gun_velocity - @angular_velocity)
    turn(@angular_velocity)
  end

  def update_radar(events)
    if events['robot_scanned'].empty?
      if @saw_target
        high_low
      else
        low_low
      end
      @saw_target = false
    else
      td = events['robot_scanned'].min.first
      if @saw_target
        high_high(td)
      else
        low_high(td)
      end
      @saw_target = true
    end
    @older_radar_heading = @old_radar_heading
    @old_radar_heading = radar_heading
  end

  def low_low
    @radar_speed = clamp(@radar_speed + target_angular_speed, 0, 60)

    if @downticks > 0
      @downticks -= 1
      if @downticks == 0
        @radar_direction *= -1
      end
    end
  end

  def low_high(dist)
    @uptick_heading = beam_center
    @uptick_dist = dist
  end

  def high_high(dist)
    @uptick_dist = dist
  end

  def high_low
    @radar_direction *= -1
    @radar_speed = clamp(@radar_speed * 0.5, target_angular_speed, 60)
    plot_target(angle_average(angle_average(@old_radar_heading,@older_radar_heading),@uptick_heading),@uptick_dist)
    @downticks = 8
  end

  def beam_center
    angle_average(radar_heading, @old_radar_heading)
  end

  def trigger(spread)
    if spread < 1
      fire 3
    end
  end

  def update_gun
    diff = angle_direction(gun_heading, @tracker.firing_angle(x,y,time))
    @gun_velocity = clamp(diff,-30,30)
    trigger(diff)
  rescue NotEnoughData
  end

  def wall_force(range)
    (2**((battlefield_width - range)/50.0))/(2**(battlefield_width/50.0))
  end

  def update_heading
    ranges = [x-size, battlefield_height-size-y, battlefield_width-size-x, y-size]
    normals = [0, 90, 180, 270]
    forces = ranges.map {|r| wall_force(r)}

    @xforce = forces[0] - forces[2]
    @yforce = forces[3] - forces[1]
    fa = Math.atan2(-@yforce,@xforce).to_deg

    goal = target_heading + 90
    unless angle_difference(heading, goal) < 90
      goal = (goal + 180) % 360
    end

    diff = angle_direction(goal, fa)
    goal += diff*(forces.max)
    @angular_velocity = clamp(angle_direction(heading, goal),-10,10)
  end


  def startup
    @saw_target = false
    @uptick_heading = 0

    @target_x = @target_y = 0

    @radar_speed = 60
    @radar_direction = 1
    @old_radar_heading = 0
    @older_radar_heading = 0
    @downticks = 0

    @gun_velocity = 0
    @angular_velocity = 0
    
    @tracker = PredictiveTracker.new

    @log = File.open("edbot.log","a")
    @log.write "Starting up!\n"

  end

  def angle_difference(a,b)
    d = (a % 360 - b % 360).abs
    d > 180 ? 360 - d : d
  end

  # To turn from a toward b, how should you turn?
  def angle_direction(a,b)
    magnitude = angle_difference(a,b)
    if angle_difference(a + 1, b) < magnitude
      magnitude
    else
      -magnitude
    end
  end

  def radar_velocity
    @radar_speed * @radar_direction
  end

  def angle_average(a,b)
    (angle_direction(a,b) / 2 + a) % 360
  end

  # How much can the angle to the target change in one tick?
  def target_angular_speed
    360 * BOT_MAX_SPEED / (2 * Math::PI * target_distance)
  end

  def target_heading
    Math.atan2(y- @target_y, @target_x - x).to_deg
  end

  def target_distance
    Math.sqrt((@target_x - x)**2 + (@target_y - y)**2)
  end

  def plot_target(heading, distance)
    rads = heading.to_rad
    @target_y = y - distance * Math.sin(rads)
    @target_x = x + distance * Math.cos(rads)
    @tracker.mark(@target_x,@target_y,time)
    @log.write("#{@target_x}\t#{@target_y}\t#{time}\n")
  end

  def clamp(var, min, max)
    val = 0 + var # to guard against poisoned vars
    if val > max
      max
    elsif val < min
      min
    else
      val
    end
  end

end
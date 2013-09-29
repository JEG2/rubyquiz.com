require 'robot'
require 'ostruct'
#same as 
module RubberRobotLinear
  MEMO_SIZE = 250
  GUN_POWER = 0.1
  ACC_WHILE_MOVING = true
  class Memo # (forgetting old values) {{{
    def initialize(n)
      @array = []
      @n = n
    end
    def << (arg)
      @array.unshift arg
      @array = @array.first(@n)
    end
    def [](arg)
      @array[arg]
    end
    def to_a
      @array
    end
    def nearest_non_nil(idx)
      0.upto(51) do |offs|
        next if @array[idx + ((offs % 2 == 0) ? -1 : 1)*offs].nil?
        return idx + ((offs % 2 == 0) ? -1 : 1)*offs
      end
      nil
    end
  end # }}}
  class Brain # {{{
    include Math # This robot knows Math!
    def time
      @robot.time
    end
    def battlefield_width
      @robot.battlefield_width
    end
    def battlefield_height
      @robot.battlefield_height
    end
    def size
      @robot.size
    end
    def say(string)
      @robot.say(string)
    end
    def trim(min, val, max) # {{{
      return min if val < min
      return max if val > max
      return val
    end # }}}
    def strim(val, border) # {{{
      return -border if val < -border
      return border if val > border
      return val
    end # }}}
    def initialize(robot) # {{{
      @memory = OpenStruct.new
      @memory.rheading    = Memo.new(MEMO_SIZE)
      @memory.pos         = Memo.new(MEMO_SIZE)
      @memory.enemypos    = Memo.new(MEMO_SIZE*4)
      @memory.enemyrange  = Memo.new(MEMO_SIZE)
      @memory.enemyangle  = Memo.new(MEMO_SIZE)
      @memory.lastseen = nil
      @robot = robot
      @tlock = 0
      @lasthit = 0
      @looking_since = 0
      @aim_mode = :linear
    end # }}}
#   def method_missing(name, *args) # {{{
#     @robot.__send__(name, *args)
#   end # }}}
    def refresh # {{{
      @x = @robot.x
      @y = @robot.y
      @turn_body = 0
      @turn_turret = 0
      @turn_radar = 0
      @power = GUN_POWER
      @accelerate = 0
      @body_heading = @robot.heading
      @turret_heading = @robot.gun_heading
      @radar_heading = @robot.radar_heading
    end # }}}
    def tick(events) # {{{
      refresh
      save_memory
      if events.has_key? 'robot_scanned' 
        r = events['robot_scanned'][0][0]
        phi0 = @memory.rheading[0]
        phi1 = @memory.rheading[1]
        if (phi0 < 90 and phi1 > 270) or (phi0 > 270 and phi1 < 90)
          phim = (phi0 + phi1 + 90) % 360 - 90
        else
          phim = (phi0 + phi1)/2
        end
        phi0, phi1, phim = phi0.to_rad, phi1.to_rad, phim.to_rad
        dx = r*(cos(phi0) - cos(phi1)).abs/2
        dy = r*(sin(phi0) - sin(phi1)).abs/2
        x = @x + r * cos(phim)
        y = @y - r * sin(phim)
        @memory.lastseen = 0
        @memory.enemypos << [x,dx,y,dy]
        @memory.enemyrange << r
        @memory.enemyangle << phim
        @memory.enemy
      else
        @memory.lastseen += 1 if @memory.lastseen
        @memory.enemypos << nil
        @memory.enemyrange << nil
        @memory.enemyangle << nil
      end
      if events.has_key? 'got_hit'
        @lasthit = 0
      else
        @lasthit += 1
      end
      if time == 50
        say "<Patrician|Away> what does your robot do, sam"
      elsif time == 100
        say "<bovril> it collects data about the surrounding environment, ..."
      elsif time == 150
        say "... then discards it and drives into walls"
      end
      do_radar_aiming
      do_turret_aiming
      do_movement
      execute
    end # }}}
    def do_turret_aiming # {{{
      @turn_turret = 1
      dist = 800
      i = 0
      angle = nil
      x, y = nil, nil
      catch :tads do
        loop do
          x,y = predict(dist/30.0 + 1) # TODO ???
          throw :tads unless x and y
          angle, distn = get_angle_and_dist(x,y)
          break if (distn - dist).abs < 15 or (i += 1) > 20
          dist = distn
        end
        @turn_turret = deg_diff(angle, @turret_heading)
      end
      @angle = angle
    end # }}}
    def do_radar_aiming # {{{
      @turn_radar = 10 and return unless @memory.lastseen
      @radar_turn_speed ||= 60
      if @memory.lastseen == 0
        @radar_turn_speed *= -0.5 
      else @memory.lastseen != 2
        @radar_turn_speed *= -2 if @radar_turn_speed.abs < 60
      end
      @turn_radar = @radar_turn_speed
    end # }}}
    def do_movement # {{{
=begin
http://bash.org/?240849
<Patrician|Away> what does your robot do, sam
<bovril> it collects data about the surrounding environment, then discards it 
         and drives into walls
=end
      @accelerate = 1 # Energie!
      @move_dur ||= 0
      @turn_dur ||= 0
      @acc_dur  ||= 0
      if @move_dur == 0
        wangle, wdist = get_revangle_and_dist_wall
        if wdist < 100
          @turn_dir = strim(deg_diff(wangle, @body_heading), 10)
        else
          @turn_dir = (rand > 0.5) ? 10 : -10
        end
        @turn_dur = 7 + (rand 12)
        @move_dur = @turn_dur + 5 + (rand 10)
        @turn_body = @turn_dir
        if ACC_WHILE_MOVING
          @acc_dur = rand 7
        end
      elsif @turn_dur == 0
        @move_dur -= 1
      elsif @acc_dur == 0
        @move_dur -= 1
        @turn_dur -= 1
        @turn_body = @turn_dir
      else
        @acc_dur  -= 1
        @move_dur -= 1
        @turn_dur -= 1
        @accelerate = -1
        @turn_body = @turn_dir
      end
    end # }}}
    def sign(x) # {{{
      return 0 if x == 0
      return 1 if x > 1
      return -1
    end # }}}
    def dist_to_center # {{{
      hypot(battlefield_height/2 - @y, battlefield_width/2 - @x)
    end # }}}
    def angle_to_center
    end
    def get_revangle_and_dist_wall
      return [[@x,0], [@y,270], [battlefield_width - @x, 180],  [battlefield_height - @y, 90]].min.reverse
    end
    def approaching_center # {{{
      angle = (atan2(@x, @y).to_deg + 90) % 360
      diff = deg_diff(angle, @body_heading).abs
      diff < 80
    end # }}}
    def deg_diff(ang1, ang2) # {{{
      (ang1 - ang2 + 180) % 360 - 180
    end # }}}
    def get_angle_and_dist(x,y) # {{{
      dx = x - @x
      dy = y - @y
      return [(atan2(dx, dy).to_deg - 90) % 360, hypot(dx, dy)]
    end # }}}
    def predict(ticks, maxhist = 70) # {{{
      i = 0
      lx = 0.0
      mx = 0.0
      nx = 0.0
      ox = 0.0
      px = 0.0
      ly = 0.0
      my = 0.0
      ny = 0.0
      oy = 0.0
      py = 0.0
      @memory.enemypos.to_a.each_with_index do |ev, idx|
        next unless ev
        break if idx > maxhist
        break if i > 5
        x, dx, y, dy = ev
        dx *= 1 + (idx / 50.to_f) ** 2
        dy *= 1 + (idx / 50.to_f) ** 2
        dx = 1.0 if dx < 1.0
        dy = 1.0 if dy < 1.0
        t = -idx-1
        i += 1
        sx = dx**2
        lx += t**2/sx
        mx += t/sx
        nx += t*x/sx
        ox += x/sx
        px += 1/sx
        sy = dy**2
        ly += t**2/sy
        my += t/sy
        ny += t*y/sy
        oy += y/sy
        py += 1/sy
      end
      return unless i >= 2

      ax = (px*nx - mx*ox)/(px*lx - mx**2)
      bx = 1/px*(mx*ax-ox)
      ay = (py*ny - my*oy)/(py*ly - my**2)
      by = 1/py*(my*ay-oy)

      bx *= -1
      by *= -1

      factor = hypot(ax, ay)/8.0
      if factor > 1
        ax /= factor
        ay /= factor
      end

      bx = battlefield_width - size if bx > battlefield_width - size
      by = battlefield_width - size if by > battlefield_width - size
      bx = size if bx < size
      by = size if by < size
       
      px = bx+ax*ticks
      py = by+ay*ticks
      return if px.infinite? or px.nan? or py.infinite? or py.nan?
      px = [battlefield_width - size, [size, px].max].min
      py = [battlefield_height - size, [size, py].max].min
      [px, py]
    end # }}}
    def execute # {{{
      @turn_turret -= @turn_body
      @turn_radar -= @turn_body + @turn_turret
      @turn_body = trim(-10, @turn_body, 10)
      @turn_turret = trim(-30, @turn_turret, 30)
      @turn_radar = trim(-60, @turn_radar, 60)
      @robot.accelerate(@accelerate)
      @robot.turn(@turn_body)
      @robot.turn_gun(@turn_turret)
      @robot.turn_radar(@turn_radar)
      @robot.fire(@power)
    end # }}}
    def save_memory # {{{
      @memory.rheading << @radar_heading
      @memory.pos << [@x, @y]
    end # }}}
  end # }}}
  class Robot # {{{
    include ::Robot

    def initialize
      @my_brain = Brain.new(self)
    end

    def tick(events)
      @my_brain.tick(events)
    end
  end # }}}
end

class RubberDuckLinear < RubberRobotLinear::Robot; end

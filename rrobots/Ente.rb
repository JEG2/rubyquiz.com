require 'robot'

class << Module.new # anonymous container

  module RobotMath

    def weighted_linear_regression(data)
      w,x,y = [],[],[]

      data.each do |(xp,yp,wp)|
        w << wp.to_f
        x << xp.to_f
        y << yp.to_f
      end

      x2 = x.map{|e|e*e}
      xy = x.zip(y).map{|(a,b)|a*b}

      xs = x.zip(w).inject(0){|a,(b,c)|a+b*c}
      ys = y.zip(w).inject(0){|a,(b,c)|a+b*c}
      x2s = x2.zip(w).inject(0){|a,(b,c)|a+b*c}
      xys = xy.zip(w).inject(0){|a,(b,c)|a+b*c}
      one = w.inject(0){|a,b|a+b}

      div = xs*xs - one * x2s

      a = (xs * ys - one * xys)/div
      b = (xs * xys - x2s * ys)/div
      return a,b
    end
    
    def zero_fixed_linear_regression(data)
      x,y = [],[]

      data.each do |(xp,yp)|
        x << xp.to_f
        y << yp.to_f
      end

      x2 = x.map{|e|e*e}.inject(0){|a,b|a+b}
      xy = x.zip(y).map{|(a,b)|a*b}.inject(0){|a,b|a+b}

      return xy/x2
    end


    def offset(heading_a,heading_b = 0)
      my_offset = (heading_a-heading_b) % 360
      my_offset = my_offset -360 if my_offset > 180
      my_offset
    end

  end


  module Turnarounder
    def initialize

      @wanted_heading = 0

      @wanted_gun_heading = 0

      @wanted_radar_heading = 0
      
      @last_radar_heading = 0
      
      super 
    end

    def head_to deg
      @wanted_heading = deg
    end

    def head_gun_to deg
      @wanted_gun_heading = deg
    end

    def head_radar_to deg
      @wanted_radar_heading = deg
    end

    def next_delta_heading
      [-10,[offset(@wanted_heading,heading),10].min].max
    end

    alias turn_amount next_delta_heading
    
    def ready?
      offset(next_heading - @wanted_heading).abs < 2
    end

    def next_heading
      heading + next_delta_heading
    end

    def turn_gun_amount
      [-30,[offset(@wanted_gun_heading,gun_heading+next_delta_heading),30].min].max
    end
    
    def gun_ready?
      offset(next_gun_heading - @wanted_gun_heading).abs < 2
    end

    def next_delta_gun_heading
      next_delta_heading+turn_gun_amount
    end

    def next_gun_heading
      heading + next_delta_gun_heading
    end
    
    def turn_radar_amount
      [-60,[offset(@wanted_radar_heading,radar_heading+next_delta_gun_heading),60].min].max
    end

    def radar_ready?
      

      offset(next_radar_heading - @wanted_radar_heading).abs < 2

    end

    def next_delta_radar_heading
      next_delta_gun_heading+turn_radar_amount
    end

    def next_radar_heading
      radar_heading + next_delta_radar_heading
    end

    def final_turn
      proxy_turn turn_amount
      proxy_turn_gun turn_gun_amount
      proxy_turn_radar turn_radar_amount

      @last_radar_heading = radar_heading

    end
    
    def turn x
      @wanted_heading += x
    end
    
    def turn_gun x
      @wanted_gun_heading += x
    end
    
    def turn_radar x
      @wanted_radar_heading += x
    end

    def mid_radar_heading
      turnc = offset(radar_heading,@last_radar_heading)
      
      radar_heading-(turnc/2.0)    
    end

  end

  module Pointanizer
    include Math
    include RobotMath
    include Turnarounder

    def move_to x,y
      @move_x = x
      @move_y = y
      @move_mode = :to
    end

    def move mode,x,y
      @move_x,@move_y = x,y
      @move_mode = mode
    end

    def halt
      @move_mode = false
    end

    def moving?
       @move_mode 
    end

    def on_wall?
      xcor <= size*3 or ycor <= size*3 or battlefield_width - xcor <= size*3 or battlefield_height - ycor <= size*3
    end

    def final_point

        yc = ycor-@move_y rescue 0
        xc = @move_x-xcor rescue 0

        if hypot(yc,xc) < size/3
          @move_mode = false
        end

        acc = true

        case @move_mode
        when :to
          head_to atan2(yc,xc).to_deg
        when :away
          head_to atan2(yc,xc).to_deg+180
        when :side_a
          head_to atan2(yc,xc).to_deg+60
        when :side_b
          head_to atan2(yc,xc).to_deg-60
        when nil,false
          acc = false
        else
          raise "Unknown move mode!"
        end

        accelerate(8) if acc

    end

    def rad_to_xy(r,d)
      return xcor + cos(r.to_rad)*d, \
             ycor - sin(r.to_rad)*d
    end

  end
  
  class Brain
    include Math
    include RobotMath
    include Turnarounder
    include Pointanizer
    
    BULLET_SPEED = 30.0
    TRACK_TIMEOUT = 5
    HISTORY_SIZE = 7
    MIN_POINTS = 4
    HISTORY_TIMEOUT = 20

    SCAN_SWITCH = 2.8
    SCAN_SWITCH2 = 1.2
    
    TRACK_RANGE = 1150.0
    
    #movement
    
    INFACTOR = 9
    OUTFACTOR = 10
    RANDOMIZE = 7
    TIMEOUT = 20
    DIFF = 5.3
    HITAWAY = 5
    SDIFF = 60*DIFF
    
    RANDTURN = 0.11
    
    attr_accessor :predx, :predy
    
    def initialize(robot)
      @robot = robot
      super()

      @points = []
       
      @last_seen_time = -TRACK_TIMEOUT
      
      @radar_speed = 1
      @track_mul = 1

      @searching =0
      @seeking =0
      
      #movement
      @move_direction = 1
      @lasthitcount = 0
      @lasthitcount2 = false
      @lastchange = -TIMEOUT
    end

    def old_predict ptime
      if @points.size < MIN_POINTS
        return rand(battlefield_width),rand(battlefield_height)
      end

      ltime = @points.last.last
      ftime = ltime - HISTORY_TIMEOUT
      xint = []
      yint = []
      @points.each do |(x,y,ktime)|
        r = ((ktime-ftime)/HISTORY_TIMEOUT.to_f)
        r = (10**r)**2
        xint << [ktime,x,r]
        yint << [ktime,y,r]
      end
    
      xa,xb = weighted_linear_regression(xint)
      ya,yb = weighted_linear_regression(yint)

      return xa*ptime+xb,ya*ptime+yb
    
    end

    def predict ptime
      if @points.size < MIN_POINTS
        return rand(battlefield_width),rand(battlefield_height)
      end
      
      ltime = (@points.last.last+@points[-2].last)/2.0
      lx = (@points.last[0]+@points[-2][0])/2.0
      ly = (@points.last[1]+@points[-2][1])/2.0
      
      xint = @points.map{|x,y,xtime| [xtime-ltime,x-lx]}
      yint = @points.map{|x,y,xtime| [xtime-ltime,y-ly]}
      
      
      xa = zero_fixed_linear_regression xint
      ya = zero_fixed_linear_regression yint
      
      q = (ptime-ltime)
      
      x,y =  q*xa+lx,q*ya+ly
      
      x2,y2 = old_predict ptime
      
      return (x+x2)/2,(y+y2)/2
      
    end

    def predcurrent
      @predx,@predy = predict time unless @predx
    end

    def tick events
      
      fire 0.1
      
      #event processing

      if event = events['robot_scanned'].pop
        dist = event.first
        
        x,y = rad_to_xy(mid_radar_heading,dist)
      
      
        @points << [x,y,time]
      
        if @points.size > HISTORY_SIZE or time - @points.first.last >= HISTORY_TIMEOUT
          @points.shift
        end
        
        @last_seen_time = time
        
        @radar_speed = 1
        
        @track_mul = 1
        
        head_radar_to mid_radar_heading
        
        @direction = 1
        
      end
      
      #moving
      
      @predx,@predy = nil,nil
      
      if events['got_hit'].pop
        @lasthitcount +=1
      elsif @lasthitcount2
        @lasthitcount2 = false
        @lasthitcount = 0
      else 
        @lasthitcount2 = true
      end

      if ((on_wall? or (tmp = @lasthitcount >= HITAWAY) or rand < RANDTURN) and time - @lastchange > TIMEOUT) or @lasthitcount >= HITAWAY * 4
        @lasthitcount2 = false
        @lasthitcount = 0
        @lastchange = time
        @move_direction *= -1
      end
      halt
      accelerate 8
      predcurrent

      yc = ycor-predy rescue 0
      xc = predx-xcor rescue 0

      deg = atan2(yc,xc).to_deg+90*@move_direction

      hyp = hypot(yc,xc)

      if hyp < SDIFF
        deg += OUTFACTOR*@move_direction
      elsif hyp > SDIFF+size
        deg -= INFACTOR*@move_direction
      end 

      deg += rand(RANDOMIZE)
      deg -= rand(RANDOMIZE)

      head_to deg
      
      #aiming
       
      if @points.size >= MIN_POINTS
        predcurrent
        
        hyp = hypot(@predx-xcor,@predy-ycor)
        
        steps = (hyp-20) / BULLET_SPEED 
      
        fx,fy = predict(time+steps+1)
        
        gh = atan2(ycor-fy,fx-xcor).to_deg+rand(7)-3
        
        head_gun_to gh
      end  
      
      #scanning

      if time-@last_seen_time >= TRACK_TIMEOUT or @points.size < MIN_POINTS
        say "Searching,"
   
        if radar_ready?
          turn_radar @radar_speed
          @radar_speed *= -SCAN_SWITCH
        end
      
      else
        say "Seek and Destroy!"

        if radar_ready?
          predcurrent
          
          yc = ycor-@predy rescue 0
          xc = @predx-xcor rescue 0
        
          deg = atan2(yc,xc).to_deg
        
          dist = hypot(yc,xc)
          
          sign = [-0.5,-1.5,-0.5,0.5,1.5,0.5][@direction % 6]

          @direction += 1
        
          deg +=  ( TRACK_RANGE * @track_mul * sign)/dist
        
          @track_mul *= SCAN_SWITCH2
        
          head_radar_to deg
        
        end
      end

      final_point
      final_turn
      
    end

    def method_missing(*args,&block)
      @robot.relay(*args,&block)
    end

  end

  class Proxy
    include ::Robot

    def initialize
      @brain = Brain.new(self)
    end

    EXPORT_MAP = Hash.new{|h,k|k}

    EXPORT_MAP['xcor'] = 'x'
    EXPORT_MAP['ycor'] = 'y'
    EXPORT_MAP['proxy_turn'] = 'turn'
    EXPORT_MAP['proxy_turn_gun'] = 'turn_gun'
    EXPORT_MAP['proxy_turn_radar'] = 'turn_radar'
    
    def relay(method,*args,&block)
      self.send(EXPORT_MAP[method.to_s],*args,&block)
    end

    def tick events
      @brain.tick events
    end

  end


  classname = "Ente"
  unless Object.const_defined?(classname)
    Object.const_set(classname,Class.new(Proxy))
  end
end




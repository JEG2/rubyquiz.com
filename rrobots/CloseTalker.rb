#
#Duckbill05, but fires power 3 bullets
require 'robot'

class CloseTalker
  include Robot
  # ###########
  # #    Initialize
  # ###########
  def myinit
    @outerlimit = 10000
    @runmode = "rotate"   # mode for steering logic
    @dir = 1    # direction of rotation 1 = ccw,-1=cw
    @period = 20  # period of wobble in tracking
    @hit_filter = 0 #low pass filter tells how much damage we are taking
    @sincehit = 100 #how long since we were hit
    @sinceevade = 100 #how long since we took evasive action
    @time_sync = 0 #phase for our jerky motion
    @sinceturn = 0
    @lastenergy = 100
    @outerlimits = (battlefield_width+battlefield_height)*2
    @duckdbg = false
    @mytrack = TrackingCT.new(battlefield_width,battlefield_height,@outerlimits)
    @chase_lim = [150,200,250]
    @mycontrol = ControlsCT.new
    debug " initialized DuckBill\n"
  end      
  def debug(a)
    print a if @duckdbg
    STDOUT.flush if @duckdbg
  end
    
  # ###########
  # #    TICK, the Robot code
  # ###########
  def tick events
    #mode nil is startup and initialize variables
    #STDOUT.flush
    # +++++  Sensors +++++ #
    myinit if time==0 #this initializes the class.
    debug "\nat (#{x},#{y}) at #{time}\n"
    debug "radar=#{radar_heading}, gun=#{gun_heading},range=#{@mytrack.range}\n"
    @mycontrol.setparms(heading,gun_heading,radar_heading)
    @mytrack.setparms(x,y,radar_heading,time)
    damage = @lastenergy - energy
    @lastenergy = energy
    @hit_filter = (@hit_filter + damage) * 0.95
    debug "hit filter = #{@hit_filter}\n"
    @sincehit += 1 
    @sincehit = 0 if not events['got_hit'].empty?
    @sinceevade += 1
    # +++++  Tracking +++++ #
    @runmode = "dance" if game_over
    @mycontrol.aimrad(*@mytrack.simpleradar(events))
    aim,err = @mytrack.predict
    aim = @mytrack.angle if aim == false
    @mycontrol.aimgun(aim)
    fire 3
    # +++++ Steering +++++ #
    #compute the distances to the four walls
    walls = [battlefield_width - x,y,x,battlefield_height - y]
    toleftwall,torightwall = walls[(@dir+1)%4],walls[(@dir-1)%4]
    if (time + @time_sync )%@period == 0
      @dir = -@dir
    elsif @hit_filter > 6 and @sinceevade > 20
      @sinceevade = 0
      @time_sync = ((@period /2) - time)%20
      @dir *= -1
    end
    #debug "wallroom left=#{toleftwall}, right=#{torightwall}\n"
    if @runmode == "rotate"
    #runmode 0 circles around the target
      #calc direction we would like to go
      if @mytrack.range > @chase_lim[2]
        @runmode = "runto"
        mydir = (@mytrack.angle + @dir * 30)%360
      elsif @mytrack.range < @chase_lim[0]
        @runmode = "runfrom"
        mydir = (@mytrack.angle + 180 + @dir * 30)%360
      else
        mydir = (@mytrack.angle + @dir * 90)%360
      end
      #figure out which wall we might hit
      wallidx = ((@mytrack.angle + 180)/90 + (@dir == 1? 0 : 1))%4
      #calculate angle of incidence with wall, 0 is head on, 90 is glancing blow
      incedence = (mydir - (90 * wallidx))%360
      if walls[wallidx] < 100 
        if incedence < 45
          @dir *= -1
          mydir = (@mytrack.angle + @dir * 90)%360
        else
          mydir = (90 * (wallidx + @dir))%360
        end
      end
      accelerate 1
    elsif @runmode == "runfrom"
    #run away
      mydir = (@mytrack.angle + 180 + @dir * 30)%360
      @runmode = "runto" if walls.sort.first < 100 and @mytrack.range < @chase_lim[0]
      @runmode = "rotate" if @mytrack.range > @chase_lim[1]
      accelerate 1
    elsif @runmode == "runto"
    #run towards
      mydir = (@mytrack.angle + @dir * 30)%360
      @runmode = "rotate" if @mytrack.range < @chase_lim[1]
      accelerate 1
      @holddir = mydir
    elsif @runmode == "dance"
    #dance baby dance!
      @mycontrol.aimrad(radar_heading + 10)
      ang = Math.atan2(y-battlefield_height/2,battlefield_width/2 - x).to_deg
      mydir = ang%360
      @mycontrol.aimgun(gun_heading + 3)
      fire 0.1
      accelerate 1
    end  
    debug "steering: mode=#{@runmode}, dir=#{mydir}, rotation = #{@dir}\n"
    @mycontrol.aimtank(mydir)
    turns = @mycontrol.calcturns
    turn(turns[0])
    turn_gun(turns[1])
    turn_radar(turns[2])
    #we already computed our turns, now execute them
  end
end


class ControlsCT
  def initialize
    @turns = [0,0,0,0,0,0,0,0,0,0,0,0] # holds data for turn/aim calculations
    @tankdir = @gundir = @raddir = 0
  end
  def setparms(a,b,c)
    @tankdir = a
    @gundir = b
    @raddir = c
  end
  def min(a,b)
    (a < b)? a : b
  end
  def max(a,b)
    (a > b)? a : b
  end
  def raddif(a,b)
    (180 + a - b)%360 -180
  end
  #dir is 1 for ccw, -1 for cw, and 0 for whichever is quickest
  def aimtank(angle,rate=10,dir=0)
    @turns[0,3] = angle%360,rate,dir
    raddif(angle,@tankdir).abs < 0.1
  end
  def aimgun(angle,rate=30,dir=0)
    @turns[4,3] = angle%360,rate,dir
    raddif(angle,@gundir).abs < 0.1
  end
  def aimrad(angle,rate=60,dir=0)
    @turns[8,3] = angle%360,rate,dir
    raddif(angle,@raddir).abs < 0.1
  end
  def calcturns
    #this translates directional commands from robot into motor actions
    #turns: 0=desired heading, 1=max speed,2=dir[1=ccw,-1=cw,0=fastest],
    #         3=computed turn, 0-3 for tank, 4-7 for gun, 8-11 for radar
    #compute turns for tank, gun, and radar headings
    ccw = (@turns[0] - @tankdir) % 360
    cw = 360 - ccw
    dir = (@turns[2] == 0)? ((ccw<cw)? 1 : -1) : @turns[2]
    @turns[3] = dir * min((dir==1)? ccw : cw,@turns[1])
    ccw = (@turns[4] - @turns[3] - @gundir) % 360
    cw = 360 - ccw
    dir = (@turns[6] == 0)? ((ccw<cw)? 1 : -1) : @turns[6]
    @turns[7] = dir * min((dir==1)? ccw : cw,@turns[5])
    ccw = (@turns[8] - @turns[7] - @turns[3] - @raddir) % 360
    cw = 360 - ccw
    dir = (@turns[10] == 0)? ((ccw<cw)? 1 : -1) : @turns[10]
    @turns[11] = dir * min(((dir==1)? ccw : cw),@turns[9])
    [@turns[3],@turns[7],@turns[11]]
  end
end

class TrackingCT
  #handles radar scanning and target prediction
  def initialize(width,height,alongways)
    @trkmode = 0
    @trk_dir = 1
    @trk_res = 6
    @tangle = 0
    @range = alongways
    @radold = 0
    @raddir = 0
    @ScanRes = [0.5,1,2,4,8,16,32,60]
    @trkdbg = false
    @tracking = []
    @width = width
    @height = height
    @outerlimit = alongways
    @radar_setting = [0,0,0]
  end
  def setparms(nx,ny,rad,t)
    @x,@y,@raddir,@time = nx,ny,rad,t
  end
  def raddif(a,b)
    (180 + a - b)%360 -180
  end
  def range
    @range
  end
  def angle
    @tangle
  end
  def debug(a)
    print a if @trkdbg
    STDOUT.flush if @trkdbg
  end
  def min(a,b)
    (a < b)? a : b
  end
  def max(a,b)
    (a > b)? a : b
  end
  def simpleradar(events)
    dif = raddif(@raddir,@radold)
    @radave = (@radold + dif/2.0)%360
    debug "\ntrking:#{@trkmode},res=#{@ScanRes[@trk_res]} degrees,rot=#{@trk_dir},sweep=(#{@radold},#{@raddir})\n"
    if events['robot_scanned'].empty?
      @closest = @outerlimit
    else
      @closest = events['robot_scanned'].collect{|e| e.first}.sort.first
      debug ",blip: dist=#{@closest}, ang=#{@radave}\n"
    end
    debug "closest=#{@closest}, range=#{@range}, ang=#{@radave}, basedir=#{@basedir}\n"
    if @trkmode == "start" or @trkmode == 0
    #start mode: initialize some stuff and start looking
      @basedir = @raddir
      setrad(@raddir + 180,60,@trk_dir)
      @range = @outerlimit
      @trkmode = "search"
    elsif @trkmode == "search" 
    #scan mode: find a target
      if @closest < @outerlimit
        @trk_dir = -@trk_dir
        @trk_res = 5
        @range = @closest
        @tangle = @radave
        @trkmode = "track"
        setrad(@radave)
      elsif setrad(@raddir + 60,60,@trk_dir)
        @trk_dir = -@trk_dir
        setrad(@basedir + 180,60,@trk_dir)
      end
    elsif @trkmode == "track"  
    #track mode: continue tracking target
      if @closest < @range * 1.25
      #found bot, refine scan, scan in other direction
        @range = @closest
        @trk_dir =  -@trk_dir
        @trk_res = max(@trk_res - 1,0)
        add(@x,@y,@radave, @range , @time) if @trk_res < 3
        @tangle = @radave
        setrad(@raddir + @ScanRes[@trk_res] * @trk_dir)
      else
      #missed bot, expand scan and reverse direction
        if @trk_res == @ScanRes.size - 1
        #lost the target and we are at max scan
          @basedir = @raddir
          setrad(@raddir + 180,60,@trk_dir)
          @trkmode = "search"
        else
          @trk_dir =  -@trk_dir
          @trk_res = min(@trk_res + 1,@ScanRes.size - 1)
          setrad(@raddir + @ScanRes[@trk_res] * @trk_dir)
        end
      end #stage
    end #mode
    @radold = @raddir
    @radar_setting
  end #radar
  def setrad(angle,rate=60,dir=0)
    @radar_setting = [angle%360,rate,dir]
    raddif(angle,@raddir).abs < 0.1
  end
  def add(x,y,angle,dist,time)
    @tracking << [x + Math::cos(angle.to_rad)*dist,y - Math::sin(angle.to_rad)*dist,time]
    debug "at #{@x},#{@y}\n"
    debug "added track angle=#{angle},dist=#{dist},#{@tracking.last.inspect}\n"
  end
  def trim
    #delete really old samples
    @tracking.delete_if{|e| @time - e[2] > 10}
    @tracking.shift while @tracking.size > 4
  end
  def velocity (e1,e2)
    distance(e1[0],e1[1],e2[0],e2[1])/(e1[2]-e2[2]).abs
  end
  def distance (x1,y1,x2,y2)
    ((x1-x2)**2 + (y1-y2)**2)**(0.5)
  end
  def findline
    sx=sy=st=sxt=syt=stt=err=0.0
    @tracking.each{|e|
      debug " findline element = #{e.inspect}\n"
      sx += e[0]
      sxt += e[2]*e[0]
      sy += e[1]
      syt += e[2]*e[1]
      st += e[2]
      stt += e[2]*e[2]
    }
    n=@tracking.size
    xm = (sxt/st-sx/n)/(stt/st-st/n)
    xb = sx/n-(st/n)*xm
    ym = (syt/st-sy/n)/(stt/st-st/n)
    yb = sy/n-(st/n)*ym
    debug "x = #{xm}t + #{xb}\n"
    debug "y = #{ym}t + #{yb}\n"
    [xm,xb,ym,yb]
  end
  def err(xm,xb,ym,yb)
    errsum=0.0
    @tracking.each{|e|
      dx,dy = e[0] - (xm*e[2]+xb),e[1]- (ym*e[2]+yb)
      errsum += (dx**2 + dy**2)
    }
    errsum/@tracking.size
  end
  def predict
    trim
    if @tracking.size < 1
      return false,0 
    elsif @tracking.size == 1
      interceptx,intercepty = @tracking[0][0],@tracking[0][1]
      myerr=500
    else
      xm,xb,ym,yb = findline
      intercepttime = @time + distance(xm*@time+xb,ym*@time+yb,@x,@y)/30.0
      #interceptx,intercepty = limitcoord(intercepttime*a + b, intercepttime*c+d)
      interceptx,intercepty = intercepttime*xm + xb, intercepttime*ym+yb
      myerr=err(xm,xb,ym,yb)
    end
    debug"intercept at (#{interceptx},#{intercepty},#{intercepttime})\n"
    angle = (Math.atan2(@y - intercepty,interceptx - @x) * 180 / Math::PI)%360
    debug "firing angle is #{angle}, error is #{myerr}\n"
    [angle,myerr]
  end
  def limitcoord(x,y)
    nx=[x,0.0].max
    nx = [nx,@width.to_f].min
    ny = [ny,@height.to_f].min
    [nx,ny]
  end
end

require 'robot'

History = Struct.new(:x, :y, :t, :prec)

class GayRush
    Margin = 100
    MinRefl = 30
    FlurryAngle=0
    include Robot

    def clamp(val, min, max)
        return val < min ? min : (val > max ? max : val)
    end

    def turn_to(dir)
        unless dir
            return 0
        end

        delta2 = (dir + 360 - @heading) % 360
        delta1 = (@heading + 360 - dir) % 360
        if(delta1 < delta2)
            if delta1 <= 10
                return -delta1
            else
                return -10
            end
        else
            if delta2 <= 10
                return delta2
            else
                return 10
            end
        end
    end

    def turn_gun_to(dir)
        unless dir
            return 0
        end

        delta2 = (dir + 360 - @gun_heading) % 360
        delta1 = (@gun_heading + 360 - dir) % 360
        if(delta1 < delta2)
            if delta1 <= 20
                return -delta1
            else
                return -20
            end
        else
            if delta2 <= 20
                return delta2
            else
                return 20
            end
        end
    end



    def tick(events)
        if time==0
            # - obsolete heuristic
                #@oldavx = battlefield_height/2
                #@avx = battlefield_height/2
                #@oldavy = battlefield_width/2
                #@avy = battlefield_width/2

            @radarstep=30
            @flurry=0
            @last_not_f = 0
            @dist = 0
            puts "GayRush> Do you think you are stronger than me?"
            @h = Array.new(3) { History.new(800.to_f,800.to_f,0.to_f,0.to_f) }
        end


        guntrn = 0

        # check if the enemy was detected
        if events['robot_scanned'].empty?

            #update the radar position
            if @radarstep.abs<60
                if not @was_seen
                    #look alternatively left and right with 2x bigger windows
                    @radarstep*=-2
                else
                    # if we did not find the robot (but the prev tick it had
                    # been found) simply move forward the radar
                    @radarstep*=1.2
                end
            end

            @radarstep = clamp( @radarstep, -60, 60)

            if not @was_seen
                @escape_to = nil
            end
            @was_seen = nil

            @last_not_f = time

        else #seen
            # get the distance of the robot
            @dist = events['robot_scanned'].flatten.min

            # this is the average angle we are looking at
            angle = @radar_heading - @radarstep * 0.5

            #invert the direction of the radar if we have seen something
            @radarstep*=-0.5

            # mark that we have seen something
            @was_seen = true

            # choose the direction to move to try to escape enemy hits
            dir = @dist>700 ? 75 : (@dist < 400 ? 135 : (@dist < 550 ? 105 : 90) )
            @escape_to = angle + (((time / 100) % 2 == 0) ? dir : -dir)

            # where we guess that the enemy is
            guess_x = x + @dist * Math.cos( angle * (Math::PI / 180.0))
            guess_y = y + @dist * -Math.sin( angle * (Math::PI / 180.0))

            #update the history, of the radar step is small enough
            prec = @radarstep.abs
            if prec <= 4
                if (@h[2].t>time-8) and (prec<@h[2].prec) and
                                                @h[2].prec > 1
                # replace the last entry with a more accurate one
                @h[2] = History.new( guess_x.to_f, guess_y.to_f,
                                                @time.to_f, prec.to_f )
                else
                # set the new last entry
                @h.shift
                @h << History.new( guess_x.to_f, guess_y.to_f,
                                                @time.to_f, prec.to_f )
                end
            end

            # - update the heuristic (obsolete)
                #fact1 = 0.7
                #fact2 = 0.3
                #@avx = @avx * (1-fact1) + guess_x * fact1
                #@avy = @avy * (1-fact1) + guess_y * fact1
                #@oldavx = @oldavx * (1-fact2) + guess_x * fact2
                #@oldavy = @oldavy * (1-fact2) + guess_y * fact2


                #if gun_heat == 0
                #  fire 0.5
                #end
        end

    ##########################################################################
    #   Take the aim
    ##########################################################################

      # - obsolete heuristic aiming
       #advfact = @dist * 0.008
       #shx = (@avx - @oldavx)*advfact + @avx
       #shy = (@avy - @oldavy)*advfact + @avy

      # take the aim linearly
        # guess the time at which the cannonball will reach the enemy
        sht = @time + @dist / 30
        ratio = (sht-@h[2].t) / (@h[2].t-@h[1].t).to_f
        # this is the delta position vector
        vx = @h[2].x - @h[1].x;
        vy = @h[2].y - @h[1].y;
        # this is the linear guess
        shx = @h[2].x + vx*ratio
        shy = @h[2].y + vy*ratio

      # add a correction to be better vrt non linear robots (optional)
        # this is the delta position vector
        dx = @h[1].x - @h[0].x;
        dy = @h[1].y - @h[0].y;
        ratio2 = (sht-@h[2].t) / (@h[1].t-@h[0].t).to_f
        # apply Gram-Schmidt to orthogonalize relatively to v[xy]
        fact = (dx*vx+dy*vy) / (vx*vx+vy*vy).to_f
        latx = dx - fact*vx;
        laty = dy - fact*vy;
        # subtract a section of the orthogonal vector proportional to the time
        shx = shx - latx*ratio2
        shy = shy - laty*ratio2

      #calculate the angle at which the cannon should be aiming
        angle2 = Math::atan2( -shy+y, shx-x ) * (180.0 / Math::PI);
        guntrn = turn_gun_to(angle2)

    ##########################################################################
    #   Reflect against the borders
    ##########################################################################
        if @target_angle.nil?
            if @x<Margin and (@heading>=90 and @heading<=270)
                @target_angle = rand(180 - MinRefl*2) + 270 + MinRefl
            elsif @y<Margin and (@heading<=180)
                @target_angle = rand(180 - MinRefl*2) + 180 + MinRefl
            elsif @x>(battlefield_width-Margin) and (@heading<=90 or @heading>=270)
                @target_angle = rand(180 - MinRefl*2) + 90 + MinRefl
            elsif @y>(battlefield_height-Margin) and (@heading>=180)
                @target_angle = rand(180 - MinRefl*2) + MinRefl
            end
        end

        turnangle = 0
        if @target_angle
            turnangle = turn_to(@target_angle)
            if turnangle == 0
                @target_angle = nil
            end
        else
            turnangle = turn_to(@escape_to)
        end

        oldflurry=@flurry #adjust
        @flurry=rand(2*FlurryAngle+1)-FlurryAngle
        @flurry=0 if @radarstep.abs >20
        turn turnangle
        turn_gun guntrn+@flurry-oldflurry-turnangle
        #radar movement should be flurry independent
        turn_radar @radarstep-guntrn-@flurry+oldflurry
        #XXX: adjust aim when strafing

        accelerate(8)

        #fire small bullets
        fire 0.1

    if not events['got_hit'].empty?
      puts "GayRush> Ouch!"
    end
  end #tick
end #class


require 'robot'
require 'matrix'

class Vector
    def angle
        Math.atan2(self.y, self.x)
    end
    def x
        self[0]
    end
    def y
        self[1]
    end
end

class HornRobot
    include Robot

    def initialize
        @pos, @vel, @opp_pos, @opp_vel, @target_pos, @target_vel =
[Vector[0,0]]*6

        @last_saw = -1000
        @radar_turn = 60
        @dist = 100000

        #where to be on wheel around opponent
        @angle = 0
    end

    def tick(events)
        convert(events)

        #find opponent
        if @e['robot_scanned'].empty?
            @radar_turn *= -2 if (@radar_turn.abs < 60)
            @radar_turn *= -1 if (@radar_turn == 60)
            #@opp_pos += @opp_vel
        else
            @dist = events['robot_scanned'][0][0]
            opp_heading = (radar_heading + @radar_turn/2.0).to_rad
            new_opp_pos = Vector[Math.cos(opp_heading), Math.sin(opp_heading)]*@dist + @pos
            delta_time = time - @last_saw
            if(delta_time < 30 && @radar_turn < 10) then
                #I don't know what I'm doing wrong here, but this doesn't
                #seem to be a good estimate of their velocity. I know averaging
                #over time would be better, but This should at least be a close
                #start which it's not right now.
                @opp_vel = (new_opp_pos - @opp_pos) * (1.0/delta_time)
            else
                @opp_vel = Vector[rand,rand]
            end
            @opp_pos = new_opp_pos
            @radar_turn *= -0.5 if @radar_turn.abs > 0.5
            @last_saw = time
        end

        #Choose target position. Right now this chooses a point on
        #the circle around the opponent. Not really effective, but it
        #avoids ok.
        @angle = (@angle + 5) % 360
        t_x = 1000*Math.cos(@angle.to_rad) + @opp_pos.x
        t_y = 1000*Math.sin(@angle.to_rad) + @opp_pos.y
        t_x = 0-t_x if t_x < 0
        t_y = 0-t_y if t_y < 0
        t_x = 2*battlefield_width-t_x if t_x > battlefield_width
        t_y = 2*battlefield_width-t_y if t_y > battlefield_width
        @target_pos = Vector[t_x, t_y]

        #move to target position
        @target_vel = (@target_pos - @pos) * 0.5
        target_heading = @target_vel.angle.to_deg % 360
        #Choose turning amount. The max we need to turn is 90
        #since the bot can go forward or reverse
        heading_prime = (heading+180) % 360
        @body_turn = [target_heading-heading,
        target_heading-(heading+360),
        (target_heading+360)-heading,
        target_heading-heading_prime,
        target_heading-(heading_prime+360),
        (target_heading+360)-heading_prime].min {|a,b| a.abs <=> b.abs}
        @body_turn = 10 if @body_turn > 10
        @body_turn = -10 if @body_turn < -10
        #This avoids somewhat the linear targeting
        accelerate( 5*Math.sin( 0.5/(2*Math::PI) * time) )

        #move turret
        #Linear targeting. Unfortunately my estimate of the opponent's
        #velocity is way off so this just swings the gun wildly.
        speed_b = 30.0
        d = @opp_pos - @pos
        a = d.x**2 + d.y**2
        b = 2*@opp_vel.x*d.x + 2*@opp_vel.y*d.y
        c = @opp_vel.x**2 + @opp_vel.y**2 - speed_b**2
        disc = b**2 - 4*a*c
        t = 20
        if(disc>0) then
            t = (2*a)/(-b + Math.sqrt(disc))
        end
        v_b = @opp_vel + d * (1/t)
        #target_gun_heading = v_b.angle.to_deg % 360
        #Just point the gun at the opponent instead since linear targeting isn't working.
        target_gun_heading = (@opp_pos - @pos).angle.to_deg % 360
        @gun_turn = [target_gun_heading-gun_heading,
        target_gun_heading-(gun_heading+360),
        (target_gun_heading+360)-gun_heading].min {|a,b| a.abs <=> b.abs }

        #adjust movements
        gun = @gun_turn - @body_turn
        gun = 30 if gun > 30
        gun = -30 if gun < -30
        radar = @radar_turn - gun - @body_turn
        radar = 60 if radar > 60
        radar = -60 if radar < -60

        turn(@body_turn)
        turn_gun(gun)
        turn_radar(radar)
        power = 0.5
        power += 1.25/3 * @radar_turn.abs if @radar_turn < 3
        power += 1.25/700 * @dist if @dist < 1000 && @dist > 300
        fire(power)
    end

    #Convert to vectors
    def convert(events)
        @e = events
        @pos = Vector[x, battlefield_height-y]
        @vel = Vector[Math.cos(heading.to_rad), Math.sin(heading.to_rad)] * speed
    end
end
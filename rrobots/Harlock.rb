require 'robot'

class Harlock
    include Robot

    def initialize
        @action = :aquire_target
        @angle = 60
        @direction = 1
    end

    def aquire_target aquired
        accelerate 1
        turn -2
        turn_gun 2
        fire 0.4
        
        unless aquired
            turn_radar @angle * @direction
            @angle += 5 if @angle <= 55
        else
            @angle /= 2
            @direction *= -1
            turn_radar @angle * @direction
        end

        if @angle <= 3 then
            @action = :shoot
        end
    end

    def shoot unused_var
        rh = radar_heading
        gh = gun_heading
        turn_gun [rh-gh, 30].min
        turn_radar(-[rh-gh, 30].min)
        
        if (rh-gh == 0)
            fire 2.1
            @action = :aquire_target
            @angle = 60
        end
    end

    def tick events
        self.send @action, events['robot_scanned'][0]
    end
end

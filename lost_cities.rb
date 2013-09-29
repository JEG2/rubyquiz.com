#!/usr/local/bin/ruby -w

require "forwardable"

class Game
  extend Forwardable
  
  LANDS = %w{deserts oceans mountains jungles volcanoes}

  Card = Struct.new(:value, :land)

  def initialize( *players )
    @deck      = Array.new
    @players   = players
    @turn      = players.sort_by { rand }.first
    @discards  = Hash.new
    @last_play = nil

    LANDS.each do |land|
      @discards[land] = Array.new
      @players.each { |player| player.lands[land] = Array.new }

      (["Inv"] * 3 + (2..10).to_a).each do |value|
      	@deck << Card.new(value, land)
      end
    end

    @deck = @deck.sort_by { rand }
    8.times { @players.each { |player| player.hand << @deck.shift } }
  end
  
  def_delegator :@deck, :empty?, :over?
  
  def rotate_player
    @turn = @players.find { |player| player != @turn }
  end
  
  def play
    sort_cards
    draw_board("Your play?")
    
    begin
      play = @turn.move.strip.downcase

      play =~ /^(d?)\s*([i2-9]|10)\s*([domjv])$/ or raise "Invalid play."
      discarded = $1 == "d"
      card      = match_card($2, $3) or raise "No such card."

      unless play_card(card, discarded)
        @turn.hand << card
        raise "You can't play that card."
      end
      
      opponent = @players.find { |player| player != @turn }
      opponent.show "Your opponent #{discarded ? 'discards' : 'plays'} " +
                    "the #{draw_cards([card], true)}."
      @turn.show "You #{discarded ? 'discard' : 'play'} " +
                 "the #{draw_cards([card], true)}."
    rescue
      @turn.show "Error:  #{$!.message}"
      retry
    end
  end
  
  def draw
    sort_cards
    draw_board("Draw from?")

    begin
      draw = @turn.move.strip.downcase

      draw =~ /^[domjvn]$/ or raise "Invalid draw."

      draw_card(draw) or raise "No cards there."
      
      opponent = @players.find { |player| player != @turn }
      if draw == "n"
        opponent.show "Your opponent draws a card from the deck."
        @turn.show "You draw a card from the deck."
      else
        opponent.show "Your opponent picks up " +
                      "the #{draw_cards([@turn.hand.last], true)}."
        @turn.show "You pick up the #{draw_cards([@turn.hand.last], true)}."
      end
      
      @last_play = nil
    rescue
      @turn.show "Error:  #{$!.message}"
      retry
    end
  end
  
  def show_results
    @players.each do |player|
      opponent       = @players.find { |p| player != p }

      your_score     = score(player.lands)
      opponent_score = score(opponent.lands)

      player.show "Game over."
      player.show "Final Score:  #{your_score} (You) vs. " +
                  "#{opponent_score} (Opponent)."
      if your_score > opponent_score
        player.show "Congratulations, you win."
      elsif your_score == opponent_score
        player.show "The game is a draw."
      else
        player.show "I'm sorry, you lose."
      end
    end
  end
  
  private
  
  def draw_board( info )
    opponent = @players.find { |player| player != @turn }
    
    LANDS.each do |land|
      @turn.show "#{land.capitalize}:"
      @turn.show "  Opponent:  #{draw_cards(opponent.lands[land])}"
      @turn.show "  Discards:  #{draw_cards(@discards[land]).sub(/\(.+\)/, '')}"
      @turn.show "       You:  #{draw_cards(@turn.lands[land])}"
    end
    @turn.show " Deck:  #{'#' * @deck.size} (#{@deck.size})"
    @turn.show " Hand:  #{draw_cards(@turn.hand, true)}"
    @turn.show "Score:  #{score(@turn.lands)} (You) vs. " +
               "#{score(opponent.lands)} (Opponent).  #{info}"
  end

  def draw_cards( cards, hand = false )
    if hand
      cards.map { |card| "#{card.value}#{card.land[0, 1].capitalize}" }.join(" ")
    else
      if cards.empty?
        ""
      else
        cards.map { |card| card.value }.join(" ") + " (#{total_cards(cards)})"
      end
    end
  end

  def total_cards( cards )
    return 0 if cards.empty?
    
    multiplier, total = 1, 0
    cards.each do |card|
      if card.value.is_a? String
        multiplier += 1
      else
        total += card.value
      end
    end
    total = (total - 20) * multiplier
    cards.size >= 8 ? total + 20 : total
  end

  def score( lands )
    lands.values.inject(0) { |sum, cards| sum + total_cards(cards) }
  end

  def match_card( value, land )
    card = @turn.hand.find do |c|
    	c.value.to_s.downcase.include?(value) and c.land[0, 1] == land
    end
    @turn.hand.delete_at(@turn.hand.index(card)) unless card.nil?
    card
  end

  def play_card( card, discard )
    if discard
      @last_play = card
      @discards[card.land] << card
      true
    else
      pile = @turn.lands[card.land]
      if pile.empty? or pile.last.value.is_a?(String) or 
         (card.value.is_a?(Integer) and card.value > pile.last.value)
        pile << card
        true
      else
        false
      end
    end
  end

  def draw_card( pile )
    if pile == "n"
      @turn.hand << @deck.shift
      true
    elsif (cards = @discards[@discards.keys.find { |l| l[0, 1] == pile }]) and 
          not cards.empty? and cards.last != @last_play
      @turn.hand << cards.pop
      true
    else
      false
    end
  end
  
  def sort_cards
    @turn.hand.replace(@turn.hand.sort_by do |card|
      [LANDS.index(card.land), card.value.is_a?(String) ? 0 : card.value]
    end)
  end
end

class Player
  extend Forwardable
  
  @@player = nil
  
  def self.inherited( subclass )
    @@player = subclass unless subclass == SocketPlayer
  end
  
  def self.player
    @@player
  end
  
  def initialize( output = $stdout, input = $stdin )
    @output, @input = output, input
    
    @hand  = Array.new
    @lands = Hash.new
  end
  
  attr_reader :hand, :lands

  def_delegator :@output, :puts, :show
  def_delegator :@input, :gets, :move
end

class SocketPlayer < Player
  def initialize( socket )
    super(socket, socket)
  end
end

if __FILE__ == $0
  require "socket"
  
  if File.exists? ARGV.last
    require ARGV.pop
  end

  case ARGV.size
  when 2
    server = TCPSocket.new(ARGV.shift, ARGV.shift.to_i)
    player = (Player.player || Player).new
    
    while line = server.gets
      player.show line
      
      if line =~ /\?\s*$/ or line =~ /^Error:/
        play = player.move
        server.puts play
      end
    end
  when 1
    server = TCPServer.new(ARGV.shift.to_i)

    while opponent = server.accept
      game = Game.new( (Player.player || Player).new,
                       SocketPlayer.new(opponent) )

      until game.over?
        game.rotate_player

        game.play
        game.draw
      end

      game.show_results
      opponent.close
    end
  else
    puts "Usage:" +
         "  Client:  #{File.basename($0)} HOST PORT [PLAYER_FILE]" +
         "  Server:  #{File.basename($0)} PORT [PLAYER_FILE]"
  end
end

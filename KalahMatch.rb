require 'Player'
require 'HumanPlayer'

class KalahMatch
	def start( p1, p2 )
		puts ''
		puts '========== GAME 1 =========='
		p1_score_1, p2_score_1 = KalahGame.new.play_game( p1, p2 )
				
		if p1_score_1 > p2_score_1
			puts p1.name+' won game #1: '+p1_score_1.to_s+'-'+p2_score_1.to_s
		elsif p2_score_1 > p1_score_1
			puts p2.name+' won game #1: '+p2_score_1.to_s+'-'+p1_score_1.to_s
		else
			puts 'game #1 was a tie: '+p1_score_1.to_s+'-'+p2_score_1.to_s
		end
		
		puts ''
		puts '========== GAME 2 =========='		
		p2_score_2, p1_score_2 = KalahGame.new.play_game( p2, p1 )
		
		if p1_score_2 > p2_score_2
			puts p1.name+' won game #2: '+p1_score_2.to_s+'-'+p2_score_2.to_s
		elsif p2_score_2 > p1_score_2
			puts p2.name+' won game #2: '+p2_score_2.to_s+'-'+p1_score_2.to_s
		else
			puts 'game #2 was a tie: '+p1_score_2.to_s+'-'+p2_score_2.to_s
		end
		
		puts ''
		puts '========== FINAL =========='
		
		p1_final = p1_score_1+p1_score_2
		p2_final = p2_score_1+p2_score_2
		
		if p1_final > p2_final
			puts p1.name+' won the match: '+p1_final.to_s+'-'+p2_final.to_s
		elsif p2_final > p1_final
			puts p2.name+' won the match: '+p2_final.to_s+'-'+p1_final.to_s
		else
			puts 'the match was tied overall : '+p1_final.to_s+'-'+p2_final.to_s
		end
	end	
end

class KalahGame
	NOBODY = 0
	TOP = 1
	BOTTOM = 2
	
	def stones_at?( i )
		@board[i]
	end
	
	def legal_move?( move )
		( ( @player_to_move==TOP and move >= 7 and move <= 12 ) || 
			( @player_to_move==BOTTOM and move >= 0 and move <= 5 ) ) and @board[move] != 0
	end
	
	def game_over?
		top = bottom = true
		(7..12).each { |i| top = false if @board[i] > 0 }
		(0..5).each { |i| bottom = false if @board[i] > 0 }
		top or bottom
	end
	
	def winner
		top, bottom = top_score, bottom_score
		if top > bottom
			return TOP
		elsif bottom > top
			return BOTTOM
		else
			return NOBODY
		end
	end
	
	def top_score
		score = 0
		(7..13).each { |i| score += @board[i] }
		score
	end
	
	def bottom_score
		score = 0
		(0..6).each { |i| score += @board[i] }
		score
	end
	
	def make_move( move )
		( puts 'Illegal move...' ; return ) unless legal_move?( move )
		
		stones, @board[move] = @board[move], 0
		
		pos = move+1
		while stones > 0
			pos+=1 if( (@player_to_move==TOP and pos==6) || (@player_to_move==BOTTOM and pos==13) )
			pos = 0 if pos==14
			@board[pos]+=1
			stones-=1
			pos+=1 if stones > 0
		end
		
		if( @player_to_move==TOP and pos>6 and pos<13 and @board[pos]==1 )
			@board[13] += @board[12-pos]+1
			@board[12-pos] = @board[pos] = 0
		elsif( @player_to_move==BOTTOM and pos>=0 and pos<6 and @board[pos]==1 )
			@board[6] += @board[12-pos]+1
			@board[12-pos] = @board[pos] = 0
		end
		
		if @player_to_move==TOP
			@player_to_move = BOTTOM unless pos == 13
		else
			@player_to_move=TOP unless pos == 6
		end
		
	end
	
	def display
		puts ''
		top = '    '
		[12,11,10,9,8,7].each { |i| top += @board[i].to_s+'  ' }
		puts top
		puts @board[13].to_s + '                     ' + @board[6].to_s
		bottom = '    '
		(0..5).each { |i| bottom += @board[i].to_s+'  ' }
		puts bottom
		puts ''
	end
	
	def reset	
		@board = Array.new( 14, 4 )
		@board[6] = @board[13] = 0	
		@player_to_move = BOTTOM
	end
	
	def play_game( bottom, top )
		reset
		
		bottom.side = BOTTOM
		top.side = TOP
		top.game = bottom.game = self
		
		puts bottom.name+' starts...'
		display
		
		until game_over?
			puts ''
			if @player_to_move == TOP
				move = top.choose_move
				puts top.name+' choose move '+move.to_s
			else
				move = bottom.choose_move
				puts bottom.name+' choose move '+move.to_s
			end
			make_move( move )
			display		
		end
		
		[bottom_score, top_score]		
	end
end

p1 = Player.new( 'Player 1' )
p2 = Player.new( 'Player 2' )
KalahMatch.new.start( p1, p2 )
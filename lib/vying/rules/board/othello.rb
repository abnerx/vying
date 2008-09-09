# Copyright 2007, Eric Idema except where otherwise noted.
# You may redistribute / modify this file under the same terms as Ruby.

require 'vying'

Rules.create( "Othello" ) do
  name    "Othello"
  version "1.0.0"
  notation :othello_notation

  players :black, :white

  score_determines_outcome

  cache :moves

  position do
    attr_reader :board

    def init
      @board = Board.new( :shape   => :square,
                          :length  => 8,
                          :plugins => [:custodial_flip] )

      @board[:d4,:e5] = :white
      @board[:e4,:d5] = :black
    end

    def has_moves
      board.frontier.any? { |c| board.will_flip?( c, turn ) } ? [turn] : []
    end

    def move?( move )
      cs = move.to_coords

      board.will_flip?( cs.first, turn ) unless cs.length != 1
    end

    def moves
      board.frontier.select { |c| board.will_flip?( c, turn ) }
    end

    def apply!( move )
      board.custodial_flip( move.to_coords.first, turn )

      rotate_turn

      if moves.empty?
        rotate_turn
        clear_cache
      end

      self
    end

    def final?
      has_moves.empty?
    end

    def score( player )
      board.count( player )
    end

    def hash
      [board, turn].hash
    end
  end

end


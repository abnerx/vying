# Copyright 2007, Eric Idema except where otherwise noted.
# You may redistribute / modify this file under the same terms as Ruby.

require 'vying/rules'

# Yinsh
#
# For detailed rules see:  http://vying.org/games/yinsh

class Yinsh < Rules

  name    "Yinsh"
  version "0.0.1"

  players [:white, :black]

  attr_reader :board, :removed, :rows, :removed_markers

  RING = { :white => :WHITE_RING, :black => :BLACK_RING }

  def initialize( seed=nil )
    super

    @board = YinshBoard.new
    @removed = { :WHITE_RING => 0, :BLACK_RING => 0 }
    @rows = []
    @removed_markers = []
  end

  def moves( player=nil )
    return []          unless player.nil? || has_moves.include?( player )

    a = []

    rings = board.occupied[RING[turn]] || []

    if rings.length < 5 && removed[RING[turn]] == 0
      a = board.unoccupied.map { |c| c.to_s }

    elsif removed_markers.length == 5
      a = rings.map { |c| c.to_s }

    elsif ! rows.empty?
      if removed_markers.empty?
        prows = rows.select { |row| board[row.first] == turn }
      else
        prows = rows.select { |row| row.include?( removed_markers.first ) }
      end

      a = prows.flatten.map { |c| c.to_s }     

    else
      rings.each do |r|
        YinshBoard::DIRECTIONS.each do |d|
          c, over_marker = r, false
          while c = board.coords.next( c, d )
            p = board[c]

            if p.nil?
              a << "#{r}#{c}"
              break if over_marker
            elsif p == :white || p == :black
              over_marker = true
            else
              break
            end
          end
        end

      end

    end


    a
  end

  def apply!( move )
    coords = move.to_coords

    if coords.length == 2
      # move the ring and put down a marker
      board.move( coords.first, coords.last )
      board[coords.first] = turn

      # flip markers
      all = [coords.first]
      d = coords.first.direction_to( coords.last )
      c = coords.first
      until (c = board.coords.next( c, d )) == coords.last
        all << c
        p = board[c]
        if p == :white || p == :black
          board[c] = p == :white ? :black : :white
        end
      end

      all << coords.last

      # check for five-in-a-row
      all.each do |c|
        p = board[c]

        if p == :white || p == :black
          [[:n,:s], [:e,:w], [:nw,:se]].each do |ds|
            row = [c]
            ds.each do |rd|
              c2 = c
              while c2 = board.coords.next( c2, rd )
                p2 = board[c2]
                break if p2 != p
                row << c2
              end
            end
            rows << row if row.length >= 5
          end

        end
      end

      turn( :rotate ) unless rows.any? { |row| board[row.first] == turn }

    elsif coords.length == 1
      rings = board.occupied[RING[turn]] || []
  
      # add a ring to the board
      if rings.length < 5 && removed[RING[turn]] == 0
        board[coords.first] = RING[turn]
        turn( :rotate )

      # remove a ring from the board
      elsif removed_markers.length == 5
        removed[board[coords.first]] += 1
        board[coords.first] = nil
        rows.reject! { |row| row.sort == removed_markers.sort }
        removed_markers.clear
        turn( :rotate )

      # remove a marker
      elsif ! rows.empty?
        board[coords.first] = nil
        removed_markers << coords.first

        # reject entire rows that can no longer complete a 5-in-a-row
        rows.reject! do |row|
            removed_markers.any? { |c| row.include?( c ) } &&
          ! removed_markers.all? { |c| row.include?( c ) }
        end

        # reject individual markers that can no longer complete a 5-in-a-row
        rows.each do |row|
          if row.include?( removed_markers.first )
            row.reject! do |c|
              removed_markers.any? do |rm|
                (c.x - rm.x).abs >= 5 || (c.y - rm.y).abs >= 5 
              end
            end
          end
        end

        # reject empty rows
        rows.reject! { |row| row.empty? }

      end
    

    end

    self
  end

  def final?
    players.any? { |p| score( p ) == 3 } || board.unoccupied.empty?
  end

  def winner?( player )
    opp = player == :white ? :black : :white
    score( player ) == 3 || 
    (board.unoccupied.empty? && score( player ) > score( opp ))
  end

  def loser?( player )
    opp = player == :white ? :black : :white
    score( player ) != 3 ||
    (board.unoccupied.empty? && score( player ) < score( opp ))
  end

  def draw?
    board.unoccupied.empty? && score( :white ) == score( :black )
  end

  def score( player )
    removed[RING[player]]
  end

  def hash
    [board,removed,rows,removed_markers,turn].hash
  end
end

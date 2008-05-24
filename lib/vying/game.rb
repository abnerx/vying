# Copyright 2007, Eric Idema except where otherwise noted.
# You may redistribute / modify this file under the same terms as Ruby.

#  History component of a Game.  This is the sequence and position cache.
#  It behaves much like an array but doesn't write out every position when
#  being serialized (and thus needs to be able to recreate positions based
#  on the sequence when necessary.

class History
  include Enumerable

  attr_reader :sequence, :positions

  SPECIAL_MOVES = { /^draw_offered_by_/     => DrawOffered,
                    /^undo_requested_by_/   => UndoRequested,
                    /^forfeit_by_/          => Forfeit,
                    /^time_exceeded_by_/    => TimeExceeded,
                    /^draw$/                => NegotiatedDraw,
                    /^swap$/                => Swapped }

  # Takes the initial position and initializes the sequence and positions
  # arrays.

  def initialize( start )
    @sequence, @positions = [], [start]
  end

  # Fetch a position from history.

  def []( i )
    return nil          if i > length
    return positions[i] if positions[i]

    # Need to recreate a missing position
    j = i
    until positions[j]
      j -= 1
    end

    until j == i
      p = nil

      SPECIAL_MOVES.each do |pattern, mod|
        if sequence[j] =~ pattern
          p = positions[j].dup
          p.extend mod
          p.special_move = sequence[j]
        end
      end

      p ||= positions[j].apply( sequence[j] )

      positions[j+1] = p
      j += 1
    end

    positions[i]
  end

  # Fetch the first position from history.

  def first
    positions[0]
  end

  # Fetch the last position from history.

  def last
    self[length-1] # Use [] -- positions could be missing
  end

  # Is the last move special?

  def special?( move )
    SPECIAL_MOVES.keys.any? { |p| move =~ p }
  end

  # How many positions are in this history?

  def length
    sequence.length + 1
  end

  # Add a new position to history.  The given move is applied to the last
  # position in history and the new position is appended to the end of the
  # history.

  def <<( move )
    p = nil

    SPECIAL_MOVES.each do |pattern, mod|
      if move =~ pattern
        p = last.dup
        p.extend mod
        p.special_move = move
      end
    end

    p ||= last.apply( move )

    positions << p
    sequence << move
    self
  end

  # Iterate over the positions in this history.

  def each
    sequence.length.times { |i| yield self[i] }
  end

  # Compare History objects.

  def eql?( o )
    positions.first == o.positions.first && sequence == o.sequence
  end

  # Compare History objects.

  def ==( o )
    eql? o
  end

  # For efficiency's sake don't dump the entire positions array

  def _dump( depth=-1 )
    ps = positions

    if length > 6
      ps = [nil] * length
      ps[0] = positions.first
      r = ( (ps.length - 6)..(ps.length - 1) )
      ps[r] = positions[r]
    end

    Marshal.dump( [sequence, ps] )
  end

  # Load mashalled data.

  def self._load( s )
    s, p = Marshal.load( s )
    h = self.allocate
    h.instance_variable_set( "@sequence", s )
    h.instance_variable_set( "@positions", p )
    h
  end

end

#  A Game represents the series of moves and positions that make up a game.
#  It is heavily backed by a subclass of Rules.

class Game
  attr_reader :history, :id, :time_limit, :updated_at

  # Create a game from the given Rules subclass, and an optional seed.  If
  # the game has random elements and a seed is not provided, one will be 
  # created.  If you'd like to replay a game with random elements you must
  # provide the original seed.

  def initialize( rules, seed=nil )
    @rules = rules.to_s
    @history = History.new( self.rules.new( seed ) )
    @user_map = {}
    yield self if block_given?
  end

  def sequence
    history.sequence
  end

  # Returns the Rules subclass that this Game is based on.  For serialization
  # purposes the @rules instance variable actually stores a string, but this
  # returns the class (which is more useful).

  def rules
    Rules.find( @rules )
  end

  # Missing method calls are passed on to the last position in the history,
  # if it responds to the call.

  def method_missing( method_id, *args )
    # These extra checks that history is not nil are required for yaml-ization
    if history && history.last.respond_to?( method_id )
      history.last.send( method_id, *args )
    else
      super
    end
  end

  # We respond to any methods provided by the last position in history.

  def respond_to?( method_id )
    # double !! to force false instead of nil
    super || !!(history && history.last.respond_to?( method_id ))
  end

  # Append a move to the Game's sequence of moves.  Whatever token is used
  # to represent a move will be converted to a String via #to_s.  It's more
  # common to use the more versatile Game#<< method.

  def append( move )
    move = move.to_s

    if move?( move )
      history << move

      if history.last.class.check_cycles?
        (0...(history.length-1)).each do |i|
          history.last.cycle_found if history[i] == history.last
        end
      end

      return self

    elsif special_move?( move )

      msym = move.intern
      if respond_to?( msym )
        send( msym )
      else
        history << move
      end

      return self
    end
    raise "'#{move}' not a valid move"
  end

  # Append a list of moves to this game.  Calls Game#append for each move
  # in the given list.

  def append_list( moves )
    i = 0
    begin
      moves.each { |move| append( move ); i += 1 }
    rescue
      i.times { undo }
      raise
    end
    self
  end

  # Splits a string on the given regex and then feeds it to Game#append_list.

  def append_string( moves, regex=/,/ )
    append_list( moves.split( regex ) )
  end

  # The most versatile way of applying moves to this Game.  It will accept
  # moves as a comma separated String, an Enumerable list of moves, or a 
  # single move.

  def <<( moves )
    if moves.kind_of? String
      return append_string( moves )
    elsif moves.kind_of? Enumerable
      return append_list( moves )
    else
      return append( moves )
    end
  end

  # Undo a single move.  This returns [position, move] that have been undone
  # as an array.

  def undo
    [history.positions.pop, history.sequence.pop]
  end

  # Accepts a hash mapping players to users.  The players should match up to
  # the players returned by #players.  The users should be an instance
  # of User or one of it's subclasses, but should implement the AI::Bot 
  # interface if you intend to use Game#step or Game#play.

  def register_users( h )
    @user_map.merge!( h )
  end

  # Get the User playing as the given player.
  #
  # Example:
  #
  #   g = Game.new Othello
  #   g[:black]                     => nil
  #   g[:black] = RandomBot.new     => <RandomBot>
  #   g[:black]                     => <RandomBot>
  #

  def []( p )
    @user_map[p]
  end

  # Assign an instance of the User playing as the given player.
  #
  # Example:
  #
  #   g = Game.new Othello
  #   g[:black] = RandomBot.new
  #   g[:white] = Human.new
  #

  def []=( p, u )
    @user_map[p] = u if players.include?( p )
  end

  def users
    @user_map.values
  end

  # If this is a 2 player game, #switch_sides will swap the registered users.

  def switch_sides
    if players.length == 2
      ps = players
      @user_map[ps[0]], @user_map[ps[1]] = @user_map[ps[1]], @user_map[ps[0]]
    end
    self
  end

  # Ask the registered users for one move, and apply it.  The registered
  # user must respond to methods like:
  #
  #   *  AI::Bot#offer_draw?
  #   *  AI::Bot#accept_draw?
  #   *  AI::Bot#forfeit?
  #   *  AI::Bot#select
  #
  # If these methods aren't implemented (select in particular) by the
  # registered user, Game#step and Game#play cannot be used.

  def step

    # Accept or reject offered draw
    if allow_draws_by_agreement? && offered_by = draw_offered_by
      accepted = @user_map.all? do |p,u| 
        position = history.last.censor( p )
        p == offered_by || u.accept_draw?( sequence, position, p )
      end

      undo
      history << "draw" if accepted

      return self
    end

    # Accept or reject undo request 
    if requested_by = undo_requested_by
      accepted = @user_map.all? do |p,u| 
        position = history.last.censor( p )
        p == requested_by || u.accept_undo?( sequence, position, p )
      end

      undo
      undo if accepted

      return self
    end

    players.each do |p|
      if @user_map[p].ready?
        position = history.last.censor( p )

        # Handle draw offers
        if allow_draws_by_agreement? && 
           @user_map[p].offer_draw?( sequence, position, p )
          history << "draw_offered_by_#{p}"
          return self
        end

        # Handle undo requests 
        if @user_map[p].request_undo?( sequence, position, p )
          history << "undo_requested_by_#{p}"
          return self
        end

        # Ask for forfeit
        if @user_map[p].forfeit?( sequence, position, p )
          history << "forfeit_by_#{p}"
          return self
        end
      end
    end

    has_moves.each do |p|
      if players.include?( p )
        if @user_map[p].ready?
          position = history.last.censor( p )

          # Ask for an move
          move = @user_map[p].select( sequence, position, p )
          if move?( move, p )
            self << move 
          else
            raise "#{@user_map[p].username} attempted invalid move: #{move}"
          end
        end
      elsif p == :random
        moves = history.last.moves
        self << moves[history.last.rng.rand(moves.size)]
      end
    end
    self
  end

  # Repeatedly calls Game#step until the game is final.

  def play
    step until final?
    results
  end

  # Returns this Game's seed.  If this game's rules don't allow for any random
  # elements the seed will be nil.

  def seed
    history.last.respond_to?( :seed ) ? history.last.seed : nil
  end

  # Is the given player the winner of this game?  The results of this method
  # may be meaningless if Game#final? is not true.  This method accepts either
  # a player or a User.

  def winner?( player )
    history.last.winner?( who?( player ) )
  end

  # Is the given player the loser of this game?  The results of this method
  # may be meaningless if Game#final? is not true.  This method accepts either
  # a player or a User.

  def loser?( player )
    history.last.loser?( who?( player ) )
  end

  # Returns the score for the given player or user.  Shouldn't be used
  # without first checking #has_score?.  This method accepts either a
  # player or a User.

  def score( player )
    history.last.score( who?( player ) )
  end

  # Is the given move valid for the position this Game is currently in?  If
  # a player is provided, also verify that the move is valid for the given
  # player.  This method passes through to the last position in the game's
  # history, but accepts either or a player or a User.

  def move?( move, player=nil )
    history.last.move?( move, who?( player ) )
  end

  # Returns true if the given player has any valid moves.

  def has_moves?( player )
    has_moves.include?( who?( player ) )
  end

  # Returns a list of special moves (forfeit, offer draw, and the like).

  def special_moves( player=nil )
    return [] if final?

    moves = []

    if pie_rule? && sequence.length == 1 && (player.nil? || player == turn)
      moves << "swap"
    end

    if draw_offered?
      return [] if draw_offered_by == player

      moves << "accept_draw" << "reject_draw"
    elsif undo_requested?
      return [] if undo_requested_by == player

      moves << "accept_undo" << "reject_undo"
    else
      normal_undo = false

      players.each do |p|
        if history.length > 1
          last = history.last
          next_to_last = history[history.length - 2]
          if last.has_moves?( p ) && next_to_last.has_moves?( p )
            normal_undo = true
            moves << "undo"  if player.nil? || p == player
          end
        end
     end

      players.each do |p|
        if player.nil? || p == player
          moves << "undo_requested_by_#{p}" unless normal_undo ||
                                                   sequence.length == 0
          moves << "forfeit_by_#{p}"
          moves << "draw_offered_by_#{p}" if allow_draws_by_agreement?
        end
      end

    end

    if player.nil?
      moves << "draw" if allow_draws_by_agreement?
      players.each do |p|
        moves << "time_exceeded_by_#{p}"
      end
    end

    moves
  end

  # Is the given move a valid special move?

  def special_move?( move, player=nil )
    special_moves( player ).include?( move )
  end

  # Who can make special moves?

  def has_special_moves
    players.select { |p| ! special_moves( p ).empty? }    
  end

  # Can the given player make a special move?

  def has_special_moves?( player )
    ! special_moves( player ).empty?
  end

  def swap
    if special_move?( "swap" )
      self[players.first], self[players.last] = 
        self[players.last], self[players.first]

      history << "swap"
    end
  end

  def accept_draw
    if special_move?( "accept_draw" )
      undo
      history << "draw"
    end
  end

  def reject_draw
    undo if special_move?( "reject_draw" )
  end

  def accept_undo
    if special_move?( "accept_undo" )
      undo
      undo
    end
  end

  def reject_undo
    undo if special_move?( "reject_undo" )
  end

  # Takes a User and returns which player he/she is.  If given a player
  # returns that player.

  def who?( user )
    return nil if user.nil?

    return user if user.class == Symbol

    players.find { |p| self[p] == user }
  end

  # Creates a new game instance by replaying from a results object.
  # The results object is a momento, containing only the minimal info
  # needed to recreate a full Game.  The results object must respond
  # to #rules, #seed, and #sequence.  It may also define #user( player )
  # that returns a user object for a player (it may return nil, or a
  # proxy object that responds to #to_user).  The results object may also
  # provide #id, #time_limit, and #updated_at.

  def Game.replay( results )
    g = Game.new( results.rules, results.seed )
    g << results.sequence

    results.rules.players.each do |p|
      if results.respond_to?( :user )
        u = results.user( p )
        g[p] = u.to_user if u
      end
    end

    if results.respond_to?( :id )
      g.instance_variable_set( "@id", results.id )
    end

    if results.respond_to?( :time_limit )
      g.instance_variable_set( "@time_limit", results.time_limit )
    end
    
    if results.respond_to?( :updated_at )
      g.instance_variable_set( "@updated_at", results.updated_at )
    end
    
    g
  end

  # The string representation of a Game is the string representation of the
  # last position in its history.

  def to_s
    history.last.to_s
  end

  # This is being defined so that we don't pass through to Rules#to_yaml_type.
  # And, because #name get's passed to Rules#name which overrides Class#name
  # which YAML normally depends on.

  def to_yaml_type
    "!ruby/object:#{self.class}"
  end

  # Provides a string describing the matchup.  For example:
  #
  #   eki (black) defeated SiriusBot (white), 34-30
  #
  # This depends on the user object's to_s method returning something 
  # reasonable like a username.

  def description
    if final?
      if draw?
        s = rules.players.map { |p| "#{@user_map[p]} (#{p})" }.join( " and " )
        s += " played to a draw"
        s += " (by agreement)" if draw_by_agreement?
        s
      else

        winners = players.select { |p| winner?( p ) }
        losers  = players.select { |p| loser?( p ) }

        ws = winners.map { |p| "#{@user_map[p]} (#{p})" }.join( " and " )
        ls = losers.map  { |p| "#{@user_map[p]} (#{p})" }.join( " and " )

        s = "#{ws} defeated #{ls}"

        if has_score?
          ss = (winners+losers).map { |p| "#{score(p)}" }.join( "-" )
          s = "#{s}, #{ss}"
        end

        s += " (forfeit by #{self[forfeit_by]})" if forfeit?
        s += " (time exceeded)"                  if time_exceeded?
        s
      end
    else
      s = rules.players.map { |p| "#{@user_map[p]} (#{p})" }.join( " vs " )

      if has_score?
        s = "#{s} (#{rules.players.map { |p| score( p ) }.join( '-' )})"
      end

      s
    end
  end
end


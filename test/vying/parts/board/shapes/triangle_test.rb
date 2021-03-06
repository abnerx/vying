
require 'test/unit'
require 'vying'

class TestBoardTriangle < Test::Unit::TestCase
  include Vying

  def test_initialize
    b = Board.triangle( 4 )
    assert_equal( :triangle, b.shape )
    assert_equal( 4, b.width )
    assert_equal( 4, b.height )
    assert_equal( 4, b.length )
    assert_equal( 10, b.coords.length )
    assert_equal( 6, b.coords.omitted.length )
    assert_equal( ["a1", "a2", "a3", "a4", "b1", "b2", "b3", "c1", "c2", "d1"],
                  b.coords.map { |c| c.to_s }.sort )
    assert_equal( ["b4", "c3", "c4", "d2", "d3", "d4"],
                  b.coords.omitted.map { |c| c.to_s }.sort )

    b = Board.triangle( 4, :omit => ["a1", "d1"] )
    assert_equal( :triangle, b.shape )
    assert_equal( 4, b.width )
    assert_equal( 4, b.height )
    assert_equal( 4, b.length )
    assert_equal( 8, b.coords.length )
    assert_equal( 8, b.coords.omitted.length )
    assert_equal( ["a2", "a3", "a4", "b1", "b2", "b3", "c1", "c2"],
                  b.coords.map { |c| c.to_s }.sort )
    assert_equal( ["a1", "b4", "c3", "c4", "d1", "d2", "d3", "d4"],
                  b.coords.omitted.map { |c| c.to_s }.sort )

    assert_raise( RuntimeError ) do
      Board.triangle( 4, :cell_shape => :square )
    end

    assert_raise( RuntimeError ) do
      Board.triangle( 4, :cell_shape => :triangle )
    end

    assert_raise( RuntimeError ) do
      Board.triangle( 4, :cell_shape => :nonexistant )
    end

    assert_raise( RuntimeError ) do
      Board.triangle( 4, :cell_orientation => :nonexistant )
    end
  end

end


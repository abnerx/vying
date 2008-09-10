# Copyright 2007, Eric Idema except where otherwise noted.
# You may redistribute / modify this file under the same terms as Ruby.

require 'optparse'
require 'benchmark'
require 'vying'

CLI::SUBCOMMANDS << "bench"

module CLI
  
  def CLI.bench
    h = { 
      :rules       => [],
      :exclude     => [],
      :n           => 100,
      :clear_cache => false
    }

    benchmark = :position

    opts = OptionParser.new
    opts.banner = "Usage: vying bench [options]"
    opts.on( "-r", "--rules RULES"   ) { |r| h[:rules]   << Rules.find( r )  }
    opts.on( "-e", "--exclude RULES" ) { |r| h[:exclude] << Rules.find( r )  }
    opts.on( "-n", "--number NUMBER" ) { |n| h[:n] = n.to_i                  }
    opts.on( "-g", "--game"          ) { benchmark = :game                   }
    opts.on( "-b", "--board"         ) { benchmark = :board                  }
    opts.on( "-p", "--profile"       ) { require 'profile'                   }
    opts.on( "-c", "--clear-cache"   ) { h[:clear_cache] = true              }

    opts.parse( ARGV )

    if benchmark == :position || benchmark == :game
      h[:rules] = Rules.latest_versions if h[:rules].empty?
      h[:exclude].each { |r| h[:rules].delete( r ) }
    end

    CLI::Bench.send( benchmark, h )
  end

  module Bench

    def self.position( h )
      n = h[:n]

      Benchmark.bm( 30 ) do |x|
        h[:rules].each do |r|
          positions, moves, players = [], [], []

          p = r.new
          n.times do |i|
            positions[i] = p

            if p.final?
              moves[i], players[i] = nil, nil
              p = r.new
            else
              players[i] = p.has_moves[rand( p.has_moves.length )]
              moves[i] = 
                p.moves( players[i] )[rand( p.moves( players[i] ).length )]

              p = p.apply( moves[i], players[i] )
            end
          end

          x.report( "#{r} init" ) do
            n.times { r.new }
          end

          x.report( "#{r} position dup" ) do
            n.times { |i| positions[i].dup }
          end

          positions.each { |p| p.clear_cache } if h[:clear_cache]

          x.report( "#{r} move?" ) do
            n.times { |i| positions[i].move?( moves[i], players[i] ) }
          end

          positions.each { |p| p.clear_cache } if h[:clear_cache]

          x.report( "#{r} has_moves" ) do
            n.times { |i| positions[i].has_moves }
          end

          positions.each { |p| p.clear_cache } if h[:clear_cache]

          x.report( "#{r} moves" ) do
            n.times { |i| positions[i].moves( players[i] ) }
          end

          positions.each { |p| p.clear_cache } if h[:clear_cache]

          x.report( "#{r} apply" ) do
            n.times do |i| 
              positions[i].apply( moves[i], players[i] ) if moves[i]
            end
          end

          positions.each { |p| p.clear_cache } if h[:clear_cache]

          x.report( "#{r} final?" ) do
            n.times { |i| positions[i].final? }
          end

          x.report( "#{r} random play" ) do
            p = r.new
            n.times do
              p = r.new if p.final?
              player = p.has_moves[rand( p.has_moves.length )]
              move = p.moves( player )[rand( p.moves( player ).length )] 
              p.apply!( move, player )
            end
          end
        end
      end
    end

    def self.game( h )

    end

    def self.board( h )
      n = h[:n]

      Benchmark.bm( 30 ) do |x|

        # Coord benchmarks
        c1, c2 = Coord[1,2], Coord[4,5]
        a, str, sym = [1,2], "b3", :b3
        marshalled = Marshal.dump( c1 )
        cs = [c1, c2]

        x.report( "Coord[x,y]" ) do
          n.times { |i| Coord[i%26,i] }
        end

        x.report( "Coord.expand" ) do
          n.times { Coord.expand( cs ) }
        end

        x.report( "Coord#dup" ) do
          n.times { c1.dup }
        end

        x.report( "Array#x,y" ) do
          n.times { a.x; a.y }
        end

        x.report( "String#x,y" ) do
          n.times { str.x; str.y }
        end

        x.report( "Symbol#x,y" ) do
          n.times { sym.x; sym.y }
        end

        x.report( "Coord#+" ) do
          n.times { c1 + c2 }
        end

        x.report( "Coord#<=>" ) do
          n.times { c1 <=> c2 }
        end

        x.report( "Coord#==" ) do
          n.times { c1 == c2 }
        end

        x.report( "Coord#direction_to" ) do
          n.times { c1.direction_to( c2 ) }
        end

        x.report( "Coord#next" ) do
          n.times { c1.next( :ne ) }
        end

        x.report( "Coord#hash" ) do
          n.times { c1.hash }
        end

        x.report( "Coord#to_coords" ) do
          n.times { c1.to_coords }
        end

        x.report( "Coord#to_s" ) do
          n.times { c1.to_s }
        end

        x.report( "Coord#to_sym" ) do
          n.times { c1.to_sym }
        end

        x.report( "Coord#_dump" ) do
          n.times { Marshal.dump( c1 ) }
        end

        x.report( "Coord._load" ) do
          n.times { Marshal.load( marshalled ) }
        end

      end
    end

  end
end


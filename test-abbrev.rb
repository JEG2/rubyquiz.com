#
# Test Suite for MethodAutoCompletion
#
require 'test/unit'
### your implementation name here
#              |
#              V
require ARGV.first

$TESTING = true
class Array
	def same_symbols? *syms
		# all syms are in self and all self's symbols
		# are in syms
		size == syms.size && syms.all?{ |sym| include? sym }
	end
end #class Array
class Test1 < Test::Unit::TestCase
	def test001
		a = Class.new {
			%w<next step stop soup>.each do
				| name |
				define_method name do nil end
			end
			abbrev :next, :step, :stop
			abbrev :soup
		}.new
		assert_nothing_raised do
			a.ne
			a.st
			a.sou
			a.stop
		end
		assert_raise NoMethodError do
			a.nee
		end
		assert_nil a.sto

		def a.sto
			42
		end
		assert_equal 42, a.sto
		assert_nil a.sou
		assert_nil a.soup

	end

	def test002
		a = Class.new {
			abbrev :new, :main
			abbrev :marry!, :xx?, :xx!, :xx
			def new
				:new
			end
			alias_method :main, :new
			def marry!
				42
			end
			attr_accessor :xx
			def xx!; nil end
			alias_method :xx?, :xx!
		}.new
		a.xx = 1764
		assert_equal :new, a.ne
		assert_equal 1764, a.xx
		assert a.x.same_symbols?( :xx?, :xx!, :xx), a.x.inspect
	end

	def test003
		a = Class.new {
			abbrev :n1, "n222", "some"
			def awsome; 1; end
			def n222
				:n222
			end
		}.new
		assert_equal :n222, a.n2
		assert_raise NoMethodError do
			a.so
		end
		assert_raise NoMethodError do
			a.some
		end
		def a.some
			42
		end
		assert_equal 42, a.some
		assert_equal 42, a.som
		assert_equal 1, a.awsome
		assert_equal 42, a.send(:so)
	end #def test003

end #class Test < Test::Unit::Testcase

class Test2 < Test::Unit::TestCase
	def setup
		@class = Class.new {	
			abbrev :a, :aa
			[:sol, :some, :soda].each do
				| so |
				abbrev so
				define_method so do so end
			end
		}

		@mix = Module.new {
				def a; 42; end
		}
	end

	def test1
		a = @class.new
		assert_raise NoMethodError do
			a.a
		end
		assert_raise NoMethodError do
			a.aa
		end
		def a.aa; 1764; end
		assert_raise NoMethodError do
			a.a
		end
		assert_equal 1764, a.aa
		a.extend @mix
		assert_equal 1764, a.aa
		assert_equal 42, a.a
	end #def test1
	def test2
		@a = @class.new
		class << @a
			def aa; 42; end
		end
		assert_raise NoMethodError do
			@a.send( :a )
		end
		assert_equal 42, @a.send(:aa)
	end #def test2
end #class Test2

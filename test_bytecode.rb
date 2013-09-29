require 'test/unit'
require 'interp'
require ARGV[0] || 'compiler'

class TestCompiler < Test::Unit::TestCase
  def test_01
    assert_equal [2+2], Interpreter.new(Compiler.compile('2+2')).run
    assert_equal [2-2], Interpreter.new(Compiler.compile('2-2')).run
    assert_equal [2*2], Interpreter.new(Compiler.compile('2*2')).run
    assert_equal [2**2], Interpreter.new(Compiler.compile('2**2')).run
    assert_equal [2/2], Interpreter.new(Compiler.compile('2/2')).run
    assert_equal [2%2], Interpreter.new(Compiler.compile('2%2')).run
    assert_equal [3%2], Interpreter.new(Compiler.compile('3%2')).run
  end

  def test_02
    assert_equal [2+2+2], Interpreter.new(Compiler.compile('2+2+2')).run
    assert_equal [2-2-2], Interpreter.new(Compiler.compile('2-2-2')).run
    assert_equal [2*2*2], Interpreter.new(Compiler.compile('2*2*2')).run
    assert_equal [2**2**2], Interpreter.new(Compiler.compile('2**2**2')).run
    assert_equal [4/2/2], Interpreter.new(Compiler.compile('4/2/2')).run
    assert_equal [7%2%1], Interpreter.new(Compiler.compile('7%2%1')).run
  end

  def test_03
    assert_equal [2+2-2], Interpreter.new(Compiler.compile('2+2-2')).run
    assert_equal [2-2+2], Interpreter.new(Compiler.compile('2-2+2')).run
    assert_equal [2*2+2], Interpreter.new(Compiler.compile('2*2+2')).run
    assert_equal [2**2+2], Interpreter.new(Compiler.compile('2**2+2')).run
    assert_equal [4/2+2], Interpreter.new(Compiler.compile('4/2+2')).run
    assert_equal [7%2+1], Interpreter.new(Compiler.compile('7%2+1')).run
  end
  
  def test_04
    assert_equal [2+(2-2)], Interpreter.new(Compiler.compile('2+(2-2)')).run
    assert_equal [2-(2+2)], Interpreter.new(Compiler.compile('2-(2+2)')).run
    assert_equal [2+(2*2)], Interpreter.new(Compiler.compile('2+(2*2)')).run
    assert_equal [2*(2+2)], Interpreter.new(Compiler.compile('2*(2+2)')).run
    assert_equal [2**(2+2)], Interpreter.new(Compiler.compile('2**(2+2)')).run
    assert_equal [4/(2+2)], Interpreter.new(Compiler.compile('4/(2+2)')).run
    assert_equal [7%(2+1)], Interpreter.new(Compiler.compile('7%(2+1)')).run
  end
  
  def test_05
    assert_equal [-2+(2-2)], Interpreter.new(Compiler.compile('-2+(2-2)')).run
    assert_equal [2-(-2+2)], Interpreter.new(Compiler.compile('2-(-2+2)')).run
    assert_equal [2+(2*-2)], Interpreter.new(Compiler.compile('2+(2*-2)')).run
  end
  
  def test_06
    assert_equal [(3/3)+(8-2)], Interpreter.new(Compiler.compile('(3/3)+(8-2)')).run
    assert_equal [(1+3)/(2/2)*(10-8)], Interpreter.new(Compiler.compile('(1+3)/(2/2)*(10-8)')).run
    assert_equal [(1*3)*4*(5*6)], Interpreter.new(Compiler.compile('(1*3)*4*(5*6)')).run
    assert_equal [(10%3)*(2+2)], Interpreter.new(Compiler.compile('(10%3)*(2+2)')).run
    assert_equal [2**(2+(3/2)**2)], Interpreter.new(Compiler.compile('2**(2+(3/2)**2)')).run
    assert_equal [(10/(2+3)*4)], Interpreter.new(Compiler.compile('(10/(2+3)*4)')).run
    assert_equal [5+((5*4)%(2+1))], Interpreter.new(Compiler.compile('5+((5*4)%(2+1))')).run
  end
  
  # Testing that short CONST instructions are generated for short-sized ints.
  # A correct solution doesn't *have to* pass this, but it's an added bonus.
  def test_07
    assert_equal [1,128,0,1,127,255,10], Compiler.compile('-32768+32767')
    assert_equal [2, 255, 255, 127, 255, 2, 0, 0, 128, 0, 10], Compiler.compile('-32769+32768')
    assert_equal [1,0,1,2,0,0,255,255,10], Compiler.compile('1+65535')
    assert_equal [1, 255, 255, 2, 0, 33, 12, 60, 10], Compiler.compile('-1+2165820')
  end
end

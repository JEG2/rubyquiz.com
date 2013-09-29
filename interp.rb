class Interpreter
  module Ops
    OPMAP = Hash.new { |h,k| h[k] = 0 }
    OPMAP[1] = 2
    OPMAP[2] = 4

    CONST = 0x01
    LCONST = 0x02
    
    ADD = 0x0a
    SUB = 0x0b
    MUL = 0x0c
    POW = 0x0d
    DIV = 0x0e
    MOD = 0x0f

    SWAP = 0xa0
     
    class << self
      # 0x01: CONST (cbyte1, cbyte2) ... => ..., const      
      def op1(interp, c1, c2)
        interp.stack.push([(c1 << 8) | c2].pack('S').unpack('s').first)
      end

      # 0x02: LCONST (cbyte1, cbyte2, cbyte3, cbyte4) ... => ..., const      
      def op2(interp, c1, c2, c3, c4)
        interp.stack.push([(((c1 << 24) | c2 << 16) | c3 << 8) | c4].pack('I').unpack('i').first)
      end

      # 0x0a: ADD () ..., value1, value2 => ..., result
      def op10(interp)        
        interp.stack.push(Integer(interp.stack.pop + interp.stack.pop))
      end

      # 0x0b: SUB () ..., value1, value2 => ..., result
      def op11(interp)
        b, a = interp.stack.pop, interp.stack.pop        
        interp.stack.push(Integer(a - b))
      end
      
      # 0x0c: MUL () ..., value1, value2 => ..., result
      def op12(interp)
        interp.stack.push(Integer(interp.stack.pop * interp.stack.pop))
      end
      
      # 0x0d: POW () ..., value1, value2 => ..., result
      def op13(interp)
        b, a = interp.stack.pop, interp.stack.pop        
        interp.stack.push(Integer(a ** b))
      end

      # 0x0e: DIV () ..., value1, value2 => ..., result
      def op14(interp)
        b, a = interp.stack.pop, interp.stack.pop        
        interp.stack.push(Integer(a / b))
      end
      
      # 0x0f: MOD () ..., value1, value2 => ..., result
      def op15(interp)
        b, a = interp.stack.pop, interp.stack.pop        
        interp.stack.push(Integer(a % b))
      end

      # 0xa0: SWAP () ..., value1, value2 => ..., value2, value1
      def op160(interp)
        interp.stack.push(interp.stack.pop, interp.stack.pop)
      end
    end
  end

  def initialize(bytes, ops = Ops) 
    @ops = ops
    @bytes = bytes
    @pc = 0
    @stack = []
  end

  attr_accessor :bytes, :pc, :stack

  def step
    if self.pc < bytes.length
      op = bytes[@pc]
      self.pc += 1

      opargs = (0...@ops::OPMAP[op]).map do
        b = bytes[pc]
        self.pc += 1
        b
      end

      @ops.send("op#{op}", self, *opargs)
      true
    else
      false
    end
  end

  def run
    step while pc < bytes.length
    stack
  end
end

if $0 == __FILE__
  require 'test/unit'
  class Interpreter
    class TestInterpreter < Test::Unit::TestCase
      def test_const
        i = Interpreter.new([Ops::CONST, *[5].pack('n').unpack('C*')]).run
        assert_equal [5], i
        
        i = Interpreter.new([Ops::CONST, *[-255].pack('n').unpack('C*')]).run
        assert_equal [-255], i
        
        i = Interpreter.new([Ops::CONST, *[32767].pack('n').unpack('C*')]).run
        assert_equal [32767], i
        
        i = Interpreter.new([Ops::CONST, *[-32768].pack('n').unpack('C*')]).run
        assert_equal [-32768], i
      end
      
      def test_lconst
        i = Interpreter.new([Ops::LCONST, *[0].pack('N').unpack('C*')]).run
        assert_equal [0], i
        
        i = Interpreter.new([Ops::LCONST, *[496].pack('N').unpack('C*')]).run
        assert_equal [496], i
        
        i = Interpreter.new([Ops::LCONST, *[-240].pack('N').unpack('C*')]).run
        assert_equal [-240], i
        
        i = Interpreter.new([Ops::LCONST, *[2147483647].pack('N').unpack('C*')]).run
        assert_equal [2147483647], i
        
        i = Interpreter.new([Ops::LCONST, *[-2147483648].pack('N').unpack('C*')]).run
        assert_equal [-2147483648], i
      end
      
      def test_add
        i = Interpreter.new([Ops::ADD])
        i.stack.push(5, 10)
        assert_equal [15], i.run
        
        i = Interpreter.new([Ops::ADD])
        i.stack.push(-5, 10)
        assert_equal [5], i.run
      end
      
      def test_sub
        i = Interpreter.new([Ops::SUB])
        i.stack.push(10, 5)
        assert_equal [5], i.run
        
        i = Interpreter.new([Ops::SUB])
        i.stack.push(10, -5)
        assert_equal [15], i.run
        
        i = Interpreter.new([Ops::SUB])
        i.stack.push(-10, 5)
        assert_equal [-15], i.run
        
        i = Interpreter.new([Ops::SUB])
        i.stack.push(-10, -5)
        assert_equal [-5], i.run
      end
      
      def test_mul
        i = Interpreter.new([Ops::MUL])
        i.stack.push(10, 5)
        assert_equal [50], i.run
        
        i = Interpreter.new([Ops::MUL])
        i.stack.push(10, -5)
        assert_equal [-50], i.run
        
        i = Interpreter.new([Ops::MUL])
        i.stack.push(-10, 5)
        assert_equal [-50], i.run
        
        i = Interpreter.new([Ops::MUL])
        i.stack.push(-10, -5)
        assert_equal [50], i.run
      end
      
      def test_pow
        i = Interpreter.new([Ops::POW])
        i.stack.push(2, 8)
        assert_equal [256], i.run
        
        i = Interpreter.new([Ops::POW])
        i.stack.push(2, 31)
        assert_equal [2147483648], i.run
        
        # The following truncate fp return values
        i = Interpreter.new([Ops::POW])
        i.stack.push(2, -8)
        assert_equal [0], i.run 
        
        i = Interpreter.new([Ops::POW])
        i.stack.push(-2, -8)
        assert_equal [0], i.run
        
        i = Interpreter.new([Ops::POW])
        i.stack.push(-10, -5)
        assert_equal [0], i.run
      end
      
      def test_div
        i = Interpreter.new([Ops::DIV])
        i.stack.push(10, 5)
        assert_equal [2], i.run
        
        i = Interpreter.new([Ops::DIV])
        i.stack.push(10, -5)
        assert_equal [-2], i.run
        
        i = Interpreter.new([Ops::DIV])
        i.stack.push(-10, 5)
        assert_equal [-2], i.run
        
        i = Interpreter.new([Ops::DIV])
        i.stack.push(-10, -5)
        assert_equal [2], i.run
      end
      
      def test_mod
        i = Interpreter.new([Ops::MOD])
        i.stack.push(10, 5)
        assert_equal [0], i.run
        
        i = Interpreter.new([Ops::MOD])
        i.stack.push(10, 3)
        assert_equal [1], i.run
        
        i = Interpreter.new([Ops::MOD])
        i.stack.push(-10, 3)
        assert_equal [2], i.run
        
        i = Interpreter.new([Ops::MOD])
        i.stack.push(-10, -3)
        assert_equal [-1], i.run
      end

      def test_swap
        i = Interpreter.new([Ops::SWAP])
        i.stack.push(10, 5)
        assert_equal [5, 10], i.run
      end

      def test_func
        i = Interpreter.new([Ops::CONST, 0, 5, Ops::LCONST, 0, 0, 0, 5, Ops::ADD,
                             Ops::CONST, 0, 5, Ops::DIV, Ops::CONST, 0, 25, 
                             Ops::MUL, Ops::LCONST, 0, 0, 0, 48, Ops::SUB, 
                             Ops::CONST, 0, 8, Ops::POW, Ops::CONST, 0, 3, Ops::MOD])

        assert_equal [1], i.run
      end
    end
  end
end


  
      

    
    

  

  

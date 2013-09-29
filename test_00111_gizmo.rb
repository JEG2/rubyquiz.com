

require 'test/unit'
require '00111_gizmo'

class Test_SecretAgent00111CommunicationGizmo < Test::Unit::TestCase
  def bits(string)
    string.unpack("B*")[0]
  end

  def test_rle
    assert_equal([10, 0, 10], 
                 SecretAgent00111CommunicationGizmo.rle([true] * 10 + 
                                                        [false] * 2 +
                                                        [true] * 10 + [false]))
    [ [], [true], [true, false, true] ].each do |arr|
      assert_raise(SecretAgent00111CommunicationGizmo::UndefinedRLE) do
        SecretAgent00111CommunicationGizmo.rle(arr)
      end
    end
  end

  def test_unrle
    assert_equal([true] * 10 + [false] * 2 + [true] * 10 + [false],
                 SecretAgent00111CommunicationGizmo.unrle([10,0,10]))
  end
  
  TEST_VECTORS = {
# [array, exponent] => bitstring
    [[], 4]     => "0000010000000111",
#                   ========-----===
#                   exponent  ^   padding
#                     (4)     |
#                      how many trues before 1st false 
#                      one extra false value is appended,
#                      and will be removed when decoding
    [[true], 4]      => "0000010000001111",
#                                =====
#                                  1
    [[true] * 2, 4]  => "0000010000010111",
#                                =====
#                                  2
    [[true] * 3, 4]  => "0000010000011111",
#                                =====
#                                  3
    [[true] * 100 + [false] * 2 + [true] + [false], 4] => 
              "0000010011111100100000000000100000111111",
#                      ======-----=====-----=====------
#                     6 * 16 +  4   ^    ^   ^   padding (to multiple of 8)
#                        = 100      |    |   |    
#                                   |    |   0 trues before next false
#                                   |    |     (extra "false" at the end)
#                                   |   1 true before next false
#                                   |
#                         0 trues before next false (i.e. 2 falses in a row)
    [[true] * 69 + [false] + [true] * 12 + [false] + [false] + [true] * 66 + [false], 5] =>
              "000001011100010100110000000011000010000000111111",
#                      --------======------========------
    [[true] * 78 + [false] + [true] * 43 + [false] + [true] * 27 + [false], 9]  =>
              "000010010001001110000010101100000110110000000000",
#                      ==========----------==========----------            
    [[true] * 3 + [false] + [true] * 29 + [false] + [true] * 116 + [false], 8]  =>
              "000010000000000110000111010011101000000000001111",
#                      =========---------=========---------
    [[true] * 64 + [false] + [true] * 80 + [false] + [true] * 4 + [false], 7]   =>
              "0000011101000000010100000000010000000000",
#                      ========--------========--------
    [[true] * 22 + [false] + [true] * 18 + [false] + [true] * 108 + [false], 6] =>
              "0000011000101100010010101011000000000111",
#                      =======-------========-------
    [[true] * 53 + [false] + [true] * 78 + [false] + [true] * 17 + [false], 6] => 
              "0000011001101011000111000100010000000111",
    [[true] * 69 + [false] + [true] * 80 + [false], 12] => 
              "000011000000001000101000000101000000000000000001",
    [[true] * 99 + [false] + [true] * 50 + [false], 10] => 
              "000010100000110001100000110010000000000001111111",
    [[true] * 137 + [false] + [true] * 12 + [false], 9] => 
              "0000100100100010010000001100000000000011",
    [[true] * 34 + [false] + [true] * 115 + [false], 5] => 
              "00000101100001011101001100000011",
    [[true] * 150 + [false], 12] => "0000110000000100101100000000000000111111",

  }

  def test_basic_encoding
    TEST_VECTORS.each_pair do |(array, exponent), encoded|
      assert_equal(encoded, 
                   bits(SecretAgent00111CommunicationGizmo.encode(array, exponent)))
    end
  end

  def test_basic_decoding
    TEST_VECTORS.each_pair do |(array, exponent), encoded|
      bitstring = [encoded].pack("B*")
      assert_equal(array, SecretAgent00111CommunicationGizmo.decode(bitstring))
    end
  end

  def test_round_trip_probabilistic
    100.times do
      exponent = 3 + rand(10)
      sequence = (0..100).map{ rand < 0.99 }
      encoded = SecretAgent00111CommunicationGizmo.encode(sequence, exponent)
      decoded = SecretAgent00111CommunicationGizmo.decode(encoded)
      assert_equal(sequence, decoded)
    end
  end

  require 'stringio'
  def test_encoder
    TEST_VECTORS.each_pair do |(array, exponent), encoded|
      bitstring = [encoded].pack("B*")
      io = StringIO.new
      encoder = SecretAgent00111CommunicationGizmo::Encoder.new(exponent, io)
      array.each{|result| encoder << result}
      encoder.finish
      assert_equal(bitstring, io.string)
    end
  end

  def test_decoder
    TEST_VECTORS.each_pair do |(array, exponent), encoded|
      bitstring = [encoded].pack("B*")
      io = StringIO.new(bitstring)
      decoder = SecretAgent00111CommunicationGizmo::Decoder.new(io)
      # the real-time decoder cannot tell when io.eof?, since the
      # link could have been severed (e.g. if the bartender is killed); it
      # thus cannot know when it has to remove a trailing "false", so we
      # compensate for that in the following assertion:
      assert_equal(exponent, decoder.exponent)
      assert_equal(array + [false], decoder.read)
    end
  end
  
  def test_decoder_partial
    TEST_VECTORS.each_pair do |(array, exponent), encoded|
      bitstring = [encoded].pack("B*")
      s = ""
      os = StringIO.new(s)
      is = StringIO.new(s)
      decoder = SecretAgent00111CommunicationGizmo::Decoder.new(is)
      decoded = []
      bitstring.each_byte do |x|
        os.write x.chr
        decoded.concat decoder.read
      end
      assert_equal(array.size + 1, decoded.size)
      assert_equal(array + [false], decoded)
    end
  end
end


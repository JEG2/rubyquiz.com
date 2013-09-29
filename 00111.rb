

def generate(len, probability = 0.99)
  (0...len).map{ rand < probability }
end

def exponent(probability)
  (Math.log(-Math.log(2)/Math.log(probability)) / Math.log(2)).floor
end

prob = 1 - 1.0 / 37  # probability of 00111's win
LEN = 1000
sequence = generate(LEN, prob)
e = exponent(prob)
puts <<EOF
Probability : #{prob}
Approx. with: #{Math.exp(-Math.log(2) / 2 ** e)}
Exponent: #{e}  (p**#{e} = 1/2; m = 2 ** e = #{2 ** e})
EOF

require '00111_gizmo'

encoded = SecretAgent00111CommunicationGizmo.encode(sequence, e)
decoded = SecretAgent00111CommunicationGizmo.decode(encoded)
puts "Decoded correctly?   #{sequence == decoded ? "yes" : "no"}"

require 'zlib'
deflated = Zlib::Deflate.deflate(sequence.map{|x| x ? "1" : "0"}.join)
puts <<EOF % (100.0 * encoded.size / LEN)
Original size: #{LEN}
Compressed to: #{encoded.size} bytes (%.1f%%)
Compare to     #{deflated.size} bytes  using deflate...
EOF

puts "=" * 80
puts "Testing buffered encoder/decoder"

require 'stringio'

io = StringIO.new("")
encoder = SecretAgent00111CommunicationGizmo::Encoder.new(e, io)
sequence.each{|result| encoder << result}
encoder.finish

decoded2 = SecretAgent00111CommunicationGizmo.decode(io.string)
puts "Decoded correctly? (b)  #{sequence == decoded2 ? "yes" : "no"}"

is = StringIO.new(io.string)
decoder = SecretAgent00111CommunicationGizmo::Decoder.new(is)
decoded3 = decoder.read
puts "Decoded correctly? (c)  #{(sequence +[false]) == decoded3 ? "yes" : "no"}"


# usage: ruby -r klass.rb test.rb <iter> [<constructor> [<lines> <columns>] ...]

require 'benchmark'
require 'test/unit/assertions'
require 'stringio'
include Test::Unit::Assertions

# char = byte pre 1.9, each_char already defined in 1.9
unless "".respond_to?(:each_char)
    class String;alias_method(:each_char, :each_byte);end
end

iterations = ARGV.shift.to_i

while cursor = ARGV.shift
    nlines = (ARGV.shift || 10000).to_i
    ncolumns = (ARGV.shift || 100).to_i
    n = nlines*ncolumns
    chars = (?a..?z).to_a
    line = (0...ncolumns).inject("") { |line, i| line << chars[i%chars.length] }
    line[-1] = ?\n
    io = StringIO.new
    nlines.times { io.puts(line) }
    
    iterations.times { 
        cursor = eval(cursor)
        reassign = lambda { |c| cursor = c }
        Benchmark.benchmark("#{cursor.class}: #{nlines}x#{ncolumns}\n",16,nil,"total","ftotal") { |b|

            total = b.report("insert_before") { nlines.times { line.each_char { |ch|
                cursor.insert_before(ch, reassign)
            } } }
            i = 0
            total += b.report("left") {
                i += 1 while cursor.left(reassign)
            }
            assert_equal(n, i)
            i = 0
            total += b.report("right") {
                i += 1 while cursor.right(reassign)
            }
            assert_equal(n, i)
            i = 0
            total += b.report("up") {
                i += 1 while cursor.up(reassign)
            }
            assert_equal(nlines, i)
            i = 0
            total += b.report("down") {
                i += 1 while cursor.down(reassign)
            }
            assert_equal(nlines, i)
            total += b.report("insert_after") { nlines.times { line.each_char { |ch|
                cursor.insert_after(ch, reassign)
            } } }
            i = 0
            total += b.report("delete_before") {
                i += 1 while cursor.delete_before(reassign)
            }
            assert_equal(n, i)
            i = 0
            total += b.report("delete_after") {
                i += 1 while cursor.delete_after(reassign)
            }
            assert_equal(n, i)
            
            
            io.pos = 0
            ftotal = b.report("read") { cursor.read(io, reassign) }
            i = 0
            ftotal += b.report("up") {
                i += 1 while cursor.left(reassign)
            }
            assert_equal(n, i)
            io.pos = 0
            ftotal = b.report("read") { cursor.read(io, reassign) }
            cursor.up(reassign)
            cursor.insert_before(line[0], reassign)
            cursor.down(reassign)
            i = 0
            ftotal += b.report("delete_before") {
                i += 1 while cursor.delete_before(reassign)
            }
            assert_equal(n+1, i)
            i = 0
            ftotal += b.report("right") {
                i += 1 while cursor.right(reassign)
            }
            assert_equal(n, i)
            i = 0
            ftotal += b.report("left") {
                i += 1 while cursor.up(reassign)
            }
            assert_equal(nlines, i)
            i = 0
            ftotal += b.report("down") {
                i += 1 while cursor.down(reassign)
            }
            assert_equal(nlines, i)
            i = 0
            ftotal += b.report("up") {
                i += 1 while cursor.up(reassign)
            }
            assert_equal(nlines, i)
            flunk unless cursor.down(reassign)
            cursor.insert_after(line[0], reassign)
            flunk unless cursor.up(reassign)
            flunk if cursor.up(reassign)
            i = 0
            ftotal += b.report("delete_after") {
                i += 1 while cursor.delete_after(reassign)
            }
            assert_equal(n+1, i)

            [total,ftotal]

        }
    }
end



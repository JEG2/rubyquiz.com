
class SplitGapCursor
    attr_accessor(:prev, :next)
    def initialize(prv=nil, nxt=nil, before="", after="")
        @prev = prv
        @next = nxt
        @before = before
        @after = after
    end
    def insert_before(ch, reassign=nil)
        @before << ch
    end
    def insert_after(ch, reassign=nil)
        @after << ch
    end
    def delete_before(reassign=nil)
        @before.slice!(-1) or (
            @prev and (reassign[@prev]; @prev.delete_before(reassign))
        )
    end
    def delete_after(reassign=nil)
        @after.slice!(-1) or (
            @next and (reassign[@next]; @next.delete_after(reassign))
        )
    end
    def left(reassign=nil)
        @after << (@before.slice!(-1) or return(
            @prev and (reassign[@prev]; @prev.left(reassign))
        ))
    end
    def right(reassign=nil)
        @before << (@after.slice!(-1) or return(
            @next and (reassign[@next]; @next.right(reassign))
        ))
    end
    def up(reassign=nil)
        while ch = @before.slice!(-1)
            @after << ch
            return(true) if ch==?\n
        end
        @prev and (reassign[@prev]; @prev.up(reassign))
    end
    def down(reassign=nil)
        while ch = @after.slice!(-1)
            @before << ch
            return(true) if ch==?\n
        end
        @next and (reassign[@next]; @next.down(reassign))
    end
    def read(io, reassign)
        # create a file cursor
        fcursor = FileCursor.new(io)
        fcursor.prev = self
        # split this buffer so that the file can be inserted
        fcursor.next = SplitGapCursor.new(fcursor, @next, "", @after)
        @after = ""
        @next = fcursor
        # use the new file cursor
        reassign[fcursor]
    end
    def inspect
        "[#{@prev&&@prev.inspect_prev}, #{@before.inspect}, #{@after.inspect}, #{@next&&@next.inspect_next}]"
    end
    def inspect_prev
        "[#{@prev&&@prev.inspect_prev}, #{@before.inspect}, #{@after.inspect}]"
    end
    def inspect_next
        "[#{@before.inspect}, #{@after.inspect}, #{@next&&@next.inspect_next}]"
    end
end

class FileCursor
    attr_accessor(:prev, :next)
    def initialize(io, b=0, e=(io.seek(0,IO::SEEK_END);io.pos), i=e)
        @prev = nil
        @next = nil
        @io = io
        @begin = b
        @end = e
        @i = i
    end
    def insert_before(ch, reassign)
        if @i==@begin
            # insert in @prev (make one if necessary) and make it the current
            reassign[@prev||=SplitGapCursor.new(nil, self)]
            @prev.insert_before(ch, reassign)
        elsif @i==@end
            # insert in @next (make one if necessary) and make it the current
            reassign[@next||=SplitGapCursor.new(self, nil)]
            @next.insert_before(ch, reassign)
        else
            # split the file at @i
            after = FileCursor.new(@io, @i, @end, @i)
            after.next = @next
            @end = @i
            # make a new gap buffer current and insert in it 
            @next = SplitGapCursor.new(self, after)
            after.prev = @next
            reassign[@next]
            @next.insert_before(ch, reassign)
        end
    end
    def insert_after(ch, reassign)
        if @i==@begin
            # insert in @prev (make one if necessary) and make it the current
            reassign[@prev||=SplitGapCursor.new(nil, self)]
            @prev.insert_after(ch, reassign)
        elsif @i==@end
            # insert in @next (make one if necessary) and make it the current
            reassign[@next||=SplitGapCursor.new(self, nil)]
            @next.insert_after(ch, reassign)
        else
            # split the file at @i
            after = FileCursor.new(@io, @i, e=@end, @i)
            after.next = @next
            @end = @i
            # make a new gap buffer current and insert in it 
            @next = SplitGapCursor.new(self, after)
            after.prev = @next
            reassign[@next]
            @next.insert_after(ch, reassign)
        end
    end
    def delete_before(reassign)
        if @i==@begin
            # make @prev become the current and let it delete
            @prev and (
                reassign[@prev]
                @prev.delete_before(reassign)
            )
        else
            if @i!=@end
                # split the file at @i
                after = FileCursor.new(@io, @i, @end, @i)
                after.next = @next
                # need this so that future insert won't get stuck
                @next = SplitGapCursor.new(self, after)
                after.prev = @next
            end
            # truncate final character and return it
            @io.pos = (@end = (@i-=1))
            @io.getc
        end
    end
    def delete_after(reassign)
        if @i==@end
            # make @next become the current and let it delete
            @next and (
                reassign[@next]
                @next.delete_after(reassign)
            )
        else
            if @i!=@begin
                # split the file at @i
                before = FileCursor.new(@io, @begin, @i, @i)
                before.prev = @prev
                # need this so that future insert won't get stuck
                @prev = SplitGapCursor.new(before, self)
                before.next = @prev
            end
           # shift off first character and return it
           @io.pos = @i
           @begin = (@i+=1)
           @io.getc
        end
    end
    def left(reassign)
        if @i==@begin
            # nothing remaining, go to the @prev cursor
            @prev and (
                reassign[@prev]
                @prev.left(reassign)
            )
        else
            @i -= 1
        end
    end
    def right(reassign)
        if @i==@end
            # nothing remaining, go to the @next cursor
            @next and (
                reassign[@next]
                @next.right(reassign)
            )
        else
            @i += 1
        end
    end
    def up(reassign)
        while (@i-=1)>=@begin
            @io.pos = @i
            return(true) if @io.getc==?\n
        end
        # couldn't find a newline in this buf, try @prev
        @i = @begin
        @prev and (reassign[@prev]; @prev.up(reassign))
    end
    def down(reassign)
        while @i<@end
            @io.pos = @i
            @i += 1
            return(true) if @io.getc==?\n
        end
        # couldn't find a newline in this buf, try @next
        @next and (reassign[@next]; @next.down(reassign))
    end
    def read(io, reassign)
        # split the file at @i
        after = FileCursor.new(@io, @i, @end, @i)
        after.next = @next
        @end = @i
        # make a new gap buffer read into it
        @next = SplitGapCursor.new(self, after)
        after.prev = @next
        reassign[@next]
        @next.read(io, reassign)
    end
    def inspect
        "[#{@prev&&@prev.inspect_prev}, #{@io.inspect}, #{@begin}, #{@end}, #{@i}, #{@next&&@next.inspect_next}]"
    end
    def inspect_prev
        "[#{@prev&&@prev.inspect_prev}, #{@io.inspect}, #{@begin}, #{@end}, #{@i}]"
    end
    def inspect_next
        "[#{@io.inspect}, #{@begin}, #{@end}, #{@i}, #{@next&&@next.inspect_next}]"
    end
end



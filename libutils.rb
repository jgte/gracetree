#!/usr/bin/env ruby

# https://gist.github.com/ChuckJHardySnippets/2000623
class String
  def to_b
    return true   if self == true   || self =~ (/(true|t|yes|y|1)$/i)
    return false  if self == false  || self.blank? || self =~ (/(false|f|no|n|0)$/i)
    raise ArgumentError.new("invalid value for Boolean: \"#{self}\"")
  end
end

# https://stackoverflow.com/questions/18358717/ruby-elegantly-convert-variable-to-an-array-if-not-an-array-already
class  Object;    def  ensure_array;  [self]  end  end
class  Array;     def  ensure_array;  to_a    end  end
class  NilClass;  def  ensure_array;  to_a    end  end

class LibUtils

  def LibUtils.calling_methods(debugdeep=false)
    LibUtils.peek(caller.join("\n"),'caller.join("\n")',debugdeep)
    out=Array.new
    caller[1..-1].each do |c|
      c1=c.to_s.slice(/`.*'/)
      out.push(c1[1...-1].sub("block in ","")) unless c1.nil?
    end
    LibUtils.peek(out.join("\n"),'out.join("\n")',debugdeep)
    return out
  end

  @TABLEN=50
  @NAMLEN=20
  @VARLEN=24

  def LibUtils.peek(var,varname,disp=true,args=Hash.new)
    return unless disp
    args={
      :show_caller    => true,
      :return_string  => false,
    }.merge(args)
    if args[:show_caller]
      caller_str=caller[0].split("/")[-1]
    else
      caller_str=nil
    end
    out =              caller_str.ljust(@TABLEN)+" : "
    out+=            varname.to_s.ljust(@NAMLEN)+" : "
    case var
    when Hash
      out+=var.pretty_inspect.chomp.ljust(@VARLEN)+" : "
    when Array
      out+=var.join(',').ljust(@VARLEN)+" : "
    else
      if var.to_s.nil?
        out+="to_s returned nil!".ljust(@VARLEN)+" : "
      else
        out+=var.to_s.ljust(@VARLEN)+" : "
      end
    end
    out+=var.class.to_s
    if args[:return_string]
      return out
    else
      puts out
    end
  end

  def LibUtils.natural_sort(x)
    return x.ensure_array.sort_by {|e| e.split(/(\d+)/).map {|a| a =~ /\d+/ ? a.to_i : a }}
  end


end
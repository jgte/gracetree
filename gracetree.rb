#!/usr/bin/env ruby

require 'yaml'
require 'optparse'
require 'pp'
require 'fileutils'
require 'benchmark'

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
      LibUtils.stderr(out)
    end
  end

  def LibUtils.natural_sort(x)
    return x.ensure_array.sort_by {|e| e.split(/(\d+)/).map {|a| a =~ /\d+/ ? a.to_i : a }}
  end

  def LibUtils.stderr(s)
      $stderr.puts(s)
      $stderr.flush
  end

  def LibUtils.utc2gps(utc)
    return (utc-Time.utc(2000,1,1,12,0,0,0)).to_i
  end
end

class GraceTree
  attr_accessor :parfile, :pars, :pars_input, :deppars, :rsdb, :adb

  PARFILE=File.dirname(__FILE__)+"/default.par"
  raise RuntimeError,"Cannot find parfile #{PARFILE}." unless File.exist?(PARFILE)
  PLACEHOLDER={
    :year   => 'YEAR',
    :month  => 'MONTH',
    :day    => 'DAY',
    :doy    => 'DOY',
    :release=> 'RELEASE',
    :reldate=> 'RELDATE',
    :jobid  => 'JOBID',
    :arc    => 'ARC',
    :sat    => 'SAT',
    :version=> 'VERSION',
  }
  PLACEHOLDER_REGEXP={
    :year   => '\d\d',
    :month  => '\d\d',
    :day    => '\d\d',
    :doy    => '\d\d\d',
    :release=> 'RL\d\d[a-z]?',
    :reldate=> 'RL\d\d[a-z]?_\d\d-\d\d',
    :jobid  => '\d+',
    :arc    => '\d+',
    :sat    => '[AB]',
    :version=> '*',
  }

  DEFAULT={
    :year  => '[0-9][0-9]',
    :month => '[0-9][0-9]',
    :day   => '[0-9][0-9]',
    :doy   => '[0-9][0-9][0-9]',
    :release=>'RL05', #this cannot be a wildcard, since the name of the database depends on it
    :reldate=>'*',
    :jobid => '*',
    :arc   => '*',
    :sat   => '[AB]',
    :version=> '*',
  }
  DATABASE={
    :rs => "released_solutions.database",
  }
  PARTICLE_LIST=[
    "year","month","day","jobid","sat","arc","release","reldate","doy","version"
  ]
  SCRATCH=(ENV["SCRATCH"].nil? ? "/tmp" : ENV["SCRATCH"])

  def initialize(argv)
    #default par file
    @parfile=PARFILE
    #default parameters for this run
    @pars={
      "execute"             => nil,
      "execute-option"      => nil,
      "root"                => nil,
      "sink"                => SCRATCH+"/gracetree",
      "year"                => DEFAULT[:year],
      "month"               => DEFAULT[:month],
      "day"                 => DEFAULT[:day],
      "doy"                 => DEFAULT[:doy],
      "release"             => DEFAULT[:release],
      "reldate"             => DEFAULT[:reldate],
      "jobid"               => DEFAULT[:jobid],
      "arc"                 => DEFAULT[:arc],
      "sat"                 => DEFAULT[:sat],
      "version"             => DEFAULT[:version],
      "subdir"           => nil,
      "filetype"            => nil,
      "pattern"             => nil,
      "clean-grep"          => false,
      "copy"                => true,
      "copylimit"           => 1000,
      "argv"                => argv,
      "debug"               => false,
      "hardlinkdir"         => '.',
      "hardlinkname"        => nil,
      "flock"               => SCRATCH+"/.lock/main",
      "breakifempty"        => false,
    }
    #get input arguments and replace default parameters
    self.options(argv)
    LibUtils.peek(argv,'argv',@pars["debug"])
    #set dependent parameters to an empty Hash, populated as needed
    @deppars=Hash.new

    # set_trace_func proc { |event, file, line, id, binding, classname|
    #   printf "%8s %s:%-2d %10s %8s\n", event, file, line, id, classname if classname==GraceTree
    # }

  end

  def self.valid_commands
    GraceTree.instance_methods(false).sort.grep(/^x/).map{|i| i.to_s.sub(/^x/,'')}
  end

  def options_default_str(option,extra='')
    if @pars[option].nil?
      "(no default value set; add '#{option}: default_value' to the parameter file)"
    else
      "(default is '#{@pars[option]}"+extra+"')"
    end
  end

  def options(argv)

    #retrive parameter file from the input arguments
    argv.each_index do |i|
      @parfile=argv[i+1] if argv[i]=="-p" || argv[i]=="--parameters-file"
    end
    #load parameters
    if File.exist?(@parfile)
      @pars=@pars.merge(YAML.load_file(@parfile))
    end

    out = OptionParser.new do |opts|

      opts.banner = "Usage: #{File.basename(__FILE__)} [options]"
      opts.separator ""

      opts.on("-p","--parameters-file PARFILE","File with parameters (default #{PARFILE}, i.e. in the same directory as #{File.basename(__FILE__)})") do |i|
        @parfile=String.new(i.to_s)
        #append parameters
        if File.exist?(@parfile)
          @pars=@pars.merge(YAML.load_file(@parfile))
        end
      end
      opts.on("-x","--execute COMMAND","Perform one (or more, using the COMMAND1+COMMAND2+...COMMANDN notation) "+
        "of the following operations "+
        self.options_default_str("execute")+":\n"+GraceTree.valid_commands.join(', ')+'.') do |i|
        @pars["execute"]=String.new(i.to_s)
      end
      opts.on("-X","--execute-option COM_OPTION","COMMAND-specific option, possibilities are:\n"+
        "if COMMAND == par     -> COM_OPTION is the name of a parameter\n"+
        "if COMMAND == element -> COM_OPTION is the name of a element\n"+
        self.options_default_str("execute-option")+'.') do |i|
        @pars["execute-option"]=String.new(i.to_s)
      end
      opts.on("-R","--root ROOT","Index files below ROOT "+
        self.options_default_str("root")+'.') do |i|
        @pars["root"]=File.expand_path(String.new(i.to_s))
      end
      opts.on("-S","--sink SINK","Copy files to SINK "+
        self.options_default_str("sink",", i.e. #{SCRATCH}/gracetree")+'.') do |i|
        @pars["sink"]=File.expand_path(String.new(i.to_s))
      end
      opts.on("-y","--year YEAR","Replace the placeholder '#{PLACEHOLDER[:year]}' in subdir: or infix: with this value "+
        self.options_default_str("year")+'.') do |i|
        #only consider the first -y/--year and ignore everything else
        if @pars["year"] == DEFAULT[:year]
          begin
            @pars["year"]=String.new("%02d" % i.to_s)
          rescue ArgumentError
            @pars["year"]=String.new(i.to_s)
          end
          #some translation
          case @pars["year"].length
          when 1; @pars["year"]="0"+@pars["year"]
          when 2; #do nothing
          when 4; @pars["year"]=pars["year"][2..3]
          end
        end
      end
      opts.on("-m","--month MONTH","Replace the placeholder '#{PLACEHOLDER[:month]}' in subdir: or infix: elements with this value "+
        self.options_default_str("month")+'.') do |i|
        #only consider the first -m/--month and ignore everything else
        if @pars["month"] == DEFAULT[:month]
          begin
            @pars["month"]=String.new("%02d" % i.to_s)
          rescue ArgumentError
            @pars["month"]=String.new(i.to_s)
          end
        end
      end
      opts.on("-d","--day DAY","Replace the placeholder '#{PLACEHOLDER[:day]}' in subdir: or infix: elements with this value "+
        self.options_default_str("day")+'.') do |i|
        begin
          @pars["day"]=String.new("%02d" % i.to_s)
        rescue ArgumentError
          @pars["day"]=String.new(i.to_s)
        end
      end
      opts.on("-o","--doy DOY","Replace the placeholder '#{PLACEHOLDER[:doy]}' in subdir: or infix: elements with this value "+
        self.options_default_str("doy")+'.') do |i|
        begin
          @pars["doy"]=String.new("%03d" % i.to_s)
        rescue ArgumentError
          @pars["doy"]=String.new(i.to_s)
        end
      end
      opts.on("-j","--jobid JOBID","Replace the placeholder '#{PLACEHOLDER[:jobid]}' in :prefix, infix: or suffix: elements with this value "+
        self.options_default_str("jobid")+'.') do |i|
        @pars["jobid"]=String.new(i.to_s)
      end
      opts.on("-r","--release RELEASE","Replace the placeholder '#{PLACEHOLDER[:release]}' in :prefix, infix: or suffix: elements with this value "+
        self.options_default_str("release")+'.') do |i|
        @pars["release"]=String.new(i.to_s)
      end
      opts.on("-D","--reldate RELEASE_DATE","Replace the placeholder '#{PLACEHOLDER[:reldate]}' in :prefix, infix: or suffix: elements with this value, e.g. RL05_17-01 "+
        self.options_default_str("reldate")+'.') do |i|
        @pars["reldate"]=String.new(i.to_s)
      end
      opts.on("-V","--version VERSION","Replace the placeholder '#{PLACEHOLDER[:version]}' in :prefix, infix: or suffix: elements with this value, e.g. RL61_GPSRL62 "+
        self.options_default_str("version")+'.') do |i|
        @pars["version"]=String.new(i.to_s)
      end
      opts.on("-v","--sub-dir SUBDIR","Append SUBDIR to the end of the subdir: element "+
        self.options_default_str("subdir")+'.') do |i|
        @pars["subdir"]=String.new(i.to_s)
      end
      opts.on("-t","--filetype FILETYPE","Gather files of type FILETYPE, as defined in #{@parfile}: "+
        self.options_default_str("filetype")+":\n"+@pars["filetypelist"].keys.join(', ')+'.') do |i|
        @pars["filetype"]=String.new(i.to_s)
      end
      opts.on("-g","--pattern PATTERN","Grep PATTERN from the files in SINK/FILETYPE "+
        self.options_default_str("pattern")+'.') do |i|
        @pars["pattern"]=String.new(i.to_s)
      end
      opts.on("-a","--arc ARC","Replace the placeholder '#{PLACEHOLDER[:arc]}' in infix: element with this value "+
        self.options_default_str("arc")+'.') do |i|
        @pars["arc"]=String.new(i.to_s)
      end
      opts.on("-s","--satellite SAT","Replace the placeholder '#{PLACEHOLDER[:sat]}' in :prefix, infix: or suffix: elements with this value "+
        self.options_default_str("sat")+'.') do |i|
        @pars["sat"]=String.new(i.to_s)
      end
      opts.on("-c","--[no-]clean-grep","Remove filename and PATTERN from grep output "+
        self.options_default_str("clean-grep")+'.') do |i|
        @pars["clean-grep"]=i
      end
      opts.on("-C","--[no-]copy","Copy files before grepping/awking "+
        self.options_default_str("copy")+'.') do |i|
        @pars["copy"]=i
      end
      opts.on("-L","--copy-limit COPY_LIMIT","Do not copy more than COPY_LIMIT files to #{SCRATCH} "+
        self.options_default_str("copylimit")+'.') do |i|
        @pars["copylimit"]=i.to_i
      end
      opts.on("-l","--hard-link-dir HARDLINK_DIR","Create hard link to this dir; make sure it's in the same volume as SINK, currently #{@pars["sink"]} "+
        self.options_default_str("hardlinkdir")+'.') do |i|
        @pars["hardlinkdir"]=String.new(i.to_s)
      end
      opts.on("-n","--hard-link-name HARDLINK_NAME","Create hard link with this name "+
        self.options_default_str("hardlinkname")+'.') do |i|
        @pars["hardlinkname"]=String.new(i.to_s)
      end
      opts.on("-F","--flock-file FLOCK_FILE","Use this file as lock for io-intensive operations "+
        self.options_default_str("flock")+'.') do |i|
        @pars["flock"]=String.new(i.to_s)
      end
      opts.on("-B","--[no-]break-if-empty","Break execution if no file is found "+
        self.options_default_str("breakifempty")+'.') do |i|
        @pars["breakifempty"]=i
      end
      opts.on("-?","--[no-]debug","Turn on debug mode "+
        self.options_default_str("debug",' and makes output very verbose!')+'.') do |i|
        @pars["debug"]=i
      end
      opts.on_tail( '-h', '--help', 'Display this screen.' ) do
        LibUtils.stderr(opts)
        LibUtils.stderr("\nExamples:
        - gracetree.rb -m 5 -d 4 -t gpsgrvout -s A: shows all gps_reg_l/grcA_gpsgrv_*out files for 20*/05/04
        - gracetree.rb -t gpsgrvout -x lsstr: shows the ls wildcarded filename of the gpsgrvout files
        ")
        exit
      end
      unless File.directory?(@pars["sink"])
        begin
          Dir.mkdir(@pars["sink"])
          LibUtils.stderr("NOTICE: created directory #{@pars["sink"]}")
        rescue Errno::ENOENT
          LibUtils.stderr("NOTICE: cannot create directory #{@pars["sink"]}")
        end        
      end
    end
    #parse it
    out.parse(argv)

    #handle doy/month+day redundancy (only if year is given)
    if @pars["year"] != DEFAULT[:year]
      if @pars["month"] == DEFAULT[:month] && @pars["day"] == DEFAULT[:day] && @pars["doy"] != DEFAULT[:doy]
        #assign month and day
        d=Date.ordinal(@pars["year"].to_i,@pars["doy"].to_i)
        @pars["month"]="%02d" % d.month.to_s
        @pars["day"]  ="%02d" % d.mday.to_s
      elsif @pars["month"] != DEFAULT[:month] && @pars["day"] != DEFAULT[:day] && @pars["doy"] == DEFAULT[:doy]
        #assign doy
        @pars["doy"]="%03d" % Date.new(y=@pars["year"].to_i,m=@pars["month"].to_i,d=@pars["day"].to_i).yday
      elsif @pars["month"] != DEFAULT[:month] && @pars["day"] != DEFAULT[:day] && @pars["doy"] != DEFAULT[:doy]
        #sanity
        raise RuntimeError,"Inputs MONTH and DAY not compatible with input DOY." unless
          @pars["doy"]==Date.new(@pars["year"].to_i,@pars["month"].to_i,@pars["day"].to_i).yday.to_s
      end
    end
    #need command
    if argv.length.zero?
      LibUtils.stderr(out)
      if File.exist?(@parfile)
        LibUtils.stderr("(Default parameter file exists: #{@parfile})")
      else
        LibUtils.stderr("(Cannot find default parameter file: #{@parfile}")
      end
      exit 1
    end

    return out

  end

  def exec(args=Hash.new)
    debug_here=false
    #merge input args with default ones
    args={
      :com          => @pars["execute"],
      :return_array => false,
      :c0           => nil,
      :n0           => nil,
    }.merge(args)
    #need to patch things up when there's no methodlist in the parfile
    @pars["methodlist"].nil? ? methodlist=Hash.new : methodlist=@pars["methodlist"]
    LibUtils.peek(args,'args',@pars["debug"] || debug_here)
    case
    when args[:com].include?('+')
      dat=Hash.new
      LibUtils.peek(args[:com],'com',@pars["debug"] || debug_here)
      c0=nil
      n0=nil
      args[:com].split('+').each do |c|
        LibUtils.peek(c,'iter:c',@pars["debug"] || debug_here)
        dat[c]=self.exec({:com => c, :return_array => true})
        LibUtils.peek(n0,'iter:n0',@pars["debug"] || debug_here)
        LibUtils.peek(c0,'iter:c0',@pars["debug"] || debug_here)
        LibUtils.peek(dat[c].length,'iter:dat[c].length',@pars["debug"] || debug_here)
        raise RuntimeError,"When using the COMMAND1+COMMAND2+...COMMANDN notation, "+
          "the COMMANDs need to refer to methods that return arrays." unless dat[c].is_a?(Array)
        if n0.nil?
          n0=dat[c].length
          c0=c;
        else
          #expand scalars
          if n0==1 && dat[c].length>1
            dat[c0]=dat[c0].cycle(dat[c].length).to_a
          elsif dat[c].length==1 && n0>1
            dat[c]=dat[c].cycle(n0).to_a
          end
          raise RuntimeError,"When using the COMMAND1+COMMAND2+...COMMANDN notation, "+
            " each COMMAND must return arrays of consistent size:\n"+
            "Operation #{c0} returned array of size #{n0}\n"+
            "Operation #{c} returned array of size #{dat[c].length}" unless n0==dat[c].length
        end
      end
      out=(0..n0-1).map { |i|
        args[:com].split('+').map{ |c|
          dat[c][i]
        }.join(' ')
      }
    when methodlist.has_key?(args[:com])
      # http://stackoverflow.com/questions/11566094/trying-to-split-string-into-single-words-or-quoted-words-and-want-to-keep-the
      out=GraceTree.new(
        @pars["argv"]+@pars["methodlist"][args[:com]].split(/\s(?=(?:[^"]|"[^"]*")*$)/).map{|a| a.gsub('"','')}
      ).exec({:return_array=>true})
    else
      out=self.method('x'+args[:com]).call
    end
    #maybe this is not yet to be shown
    if args[:return_array]
      return out
    else
      case out
      when NilClass
        #do nothing
      when String
        puts out
      when Array
        puts out.join("\n")
      when Hash
        puts YAML.dump(out)
      else
        pp out
      end
    end
  end

  def xpar(parname=@pars["execute-option"])
    @pars[parname]
  end

  def xprint
    out=Hash.new
    self.instance_variables.map do |attribute|
      out[attribute]=self.instance_variable_get(attribute);
    end
    return out
  end

  def debug_common_args
    out=['-y',@pars["year"],'-m',@pars["month"],'-d',@pars["day"]]
    out+=['-?'] if @pars["debug"]
    return out
  end

  def xdebug(methodlist=[
      'filetype',
      'particles',
      'filename_raw',
      'filename_quick',
      'filename',
      'released_solution',
      'released_solution_literal',
      'sink',
      'findstr',
      'lsstr',
  ])
    out=Hash.new
    methodlist.each do |m|
      out[m]=self.method('x'+m).call
    end
    return out
  end

  def debugallfiletypes(methodlist)
    out=Hash.new
      xfiletypelist.each_key do |k|
        out[k]=GraceTree.new(['-t',k.to_s]+self.debug_common_args).xdebug(methodlist)
      end
    return out
  end

  def xdebugall
    self.debugallfiletypes([
      'filetype',
      'particles',
      'filename_raw',
      'filename_quick',
      'filename',
      'released_solution',
      'sink',
      'findstr',
      'lsstr',
      "ls",
      "find",
      "year",
      "month",
      "day",
      "jobid",
      "release",
      "reldate",
      "sat",
      "arc",
    ])
  end

  def xdebugparticles
    self.debugallfiletypes([
      "year",
      "month",
      "day",
      "jobid",
      "release",
      "reldate",
      "sat",
      "arc",
    ])
  end

  def xparfile
    YAML.dump(@pars)
  end

  def xfiletypelist
    @pars["filetypelist"]
  end

  def xftl
    @pars["filetypelist"].keys
  end

  def xfiletype(args=Hash.new)
    return args[:filetype] if args.has_key?(:filetype)
    unless @deppars.has_key?(:filetype)
      raise RuntimeError,"Need FILETYPE." if @pars["filetype"].nil?
      if xfiletypelist.has_key?(@pars["filetype"])
        #why not use @pars["filetype"] immediately? Because we need all these checks, which should not be done more than once
        @deppars[:filetype]=@pars["filetype"]
      else
        raise RuntimeError,"Need a valid FILETYPE, i.e. one of #{xfiletypelist.keys.join(', ')}."
      end
    end
    @deppars[:filetype]
  end

  def xelement(name=@pars["execute-option"],ft=xfiletype)
    LibUtils.peek(name,'in:name',@pars["debug"])
    LibUtils.peek(ft,'in:ft',@pars["debug"])
    if name.nil?
      LibUtils.peek(xfiletypelist[ft],'xfiletypelist[ft]',@pars["debug"])
      xfiletypelist[ft]
    else
      LibUtils.peek(xfiletypelist[ft][name],'xfiletypelist[ft][name]',@pars["debug"])
      xfiletypelist[ft][name]
    end
  end

  def xfilename_raw(args=Hash.new)
    args={
      :filetype=>xfiletype(args),
      :add_root=>true,
    }.merge(args)
    ft=args[:filetype]
    LibUtils.peek(args,'in:args',@pars["debug"])
    #build complete filename
    out=String.new
    if args[:add_root]
      unless xelement("rootdir",ft).nil?
        out+=xelement("rootdir",ft)+"/" 
      else
        out+=@pars["root"]+"/" 
      end
    end
    LibUtils.peek(xelement(nil,ft),'xelement(nil,ft)',@pars["debug"])
    out+=xelement("subdir",ft)+'/' unless xelement("subdir",ft).nil?
    out+=@pars["subdir"]+'/' unless @pars["subdir"].nil?
    ["prefix","infix","suffix"].each do |k|
      out+=xelement(k,ft) unless xelement(k,ft).nil?
    end
    return out.gsub('.','\.')
  end

  def xfilename(args=Hash.new)
    debug_here=false
    args={
      :particles=>Hash.new,
    }.merge(args)
    LibUtils.peek(args,'in:args',@pars["debug"] || debug_here)
    out=xfilename_raw(args)
    LibUtils.peek(out,'1:out',@pars["debug"] || debug_here)
    #replace named parts
    named_parts=out.match(/<.*?>/)
    LibUtils.peek(named_parts,'1:named_parts',@pars["debug"] || debug_here)
    #loop over all named parts
    named_parts.to_a.map{ |n| n.gsub(/<|>/,'') }.each do |n|
      LibUtils.peek(n,'iter:n',@pars["debug"] || debug_here)
      #retrieve string to replace the named part
      replace_str=self.method('x'+n).call
      LibUtils.peek(replace_str,'iter:replace_str',@pars["debug"] || debug_here)
      out=out.gsub("<#{n}>",replace_str)
      LibUtils.peek(out,'iter:out',@pars["debug"] || debug_here)
    end
    #remove double slashes
    out=out.gsub('//','/')
    LibUtils.peek(out,'2:out',@pars["debug"] || debug_here)
    #update relevant particles
    particles=xparticles.merge(args[:particles])
    LibUtils.peek(particles,'particles',@pars["debug"] || debug_here)
    #replace placeholders with requested filename parts
    PARTICLE_LIST.map{|p| p.to_sym}.each do |k|
      LibUtils.peek(k,'iter:k',@pars["debug"] || debug_here)
      unless particles[k.to_s].nil?
        case k
        when :release
          out=out.gsub(PLACEHOLDER[k],particles[k.to_s].to_s.sub(/[UD]D/,'')) 
        else
          out=out.gsub(PLACEHOLDER[k],particles[k.to_s].to_s) 
        end
      end
      LibUtils.peek(out,'iter:out',@pars["debug"] || debug_here)
    end
    return out
  end

  def xfilename_quick
    #update filename if needed
    @deppars[:filename]=xfilename unless @deppars.has_key?(:filename)
    #return saved filename
    @deppars[:filename]
  end

  def xparticles
    unless @deppars.has_key?(:particles)
      @deppars[:particles]=Hash.new
      PARTICLE_LIST.each do |k|
        @deppars[:particles][k]=@pars[k]
      end
    end
    @deppars[:particles]
  end

  def parse_krrreg(filename)
    DateTime.strptime(File.basename(filename).split('_')[1],'%y-%m-%d').mjd.to_s
  end

  def xstart
    [parse_krrreg(File.open(xls({:filetype => "krrreg"})[0]).to_a.first)]
  end

  def xstop
    [parse_krrreg(File.open(xls({:filetype => "krrreg"})[0]).to_a.last)]
  end

  def released_solutions_io(op,dbfile=@pars["sink"]+'/'+DATABASE[:rs]+'.'+@pars["release"])
    debug_here=false
    LibUtils.peek(dbfile,'dbfile',@pars["debug"]||debug_here)
    case op
    when :load
      @rsdb=YAML.load_file(dbfile)
    when :save
      File.open(dbfile,'w') {|f| f.write(@rsdb.to_yaml)}
    when :build
      #get file with solution list
      estimdirfile=GraceTree.new(['-t','estimdir','-r',@pars["release"]]).xfind
      raise RuntimeError,"Expecting the EstimDirs file to be one, not #{estimdirfile.length}." unless estimdirfile.length==1
      #build released solutions database
      @rsdb=Hash.new
      File.foreach(estimdirfile[0]) do |l|
        mjd_stop_old=0
        LibUtils.peek(l,'line',@pars["debug"]||debug_here)
        a = l.split(' ');
        LibUtils.peek(a[8],'mjd start',@pars["debug"]||debug_here)
        #TODO: clean this up, it is not longer useful
        # y = a[1].sub('20','').to_i
        # m = Date::MONTHNAMES.index(a[2])
        #build dirname
        dir=a[4].sub(@pars["root"]+"/",'')
        dir.chop! if dir[-1..-1]=='/'
        LibUtils.peek(dir,'dir',@pars["debug"]||debug_here)
        reldate=a[4].split('/').find { |i| /RL\d\d/ =~ i }
        LibUtils.peek(reldate,'reldate',@pars["debug"]||debug_here)
        #skip placeholders: if old stop date is later than current stop date or if current stop date is very large
        next if mjd_stop_old > a[9].to_i || a[9].to_i>99999
        #loop over all days in this solution
        ((a[8].to_i+1)..a[9].to_i).each do |mjd|
          #build date
          today=Date.jd(mjd.to_i+2400000)
          LibUtils.peek(today.to_s+' '+mjd.to_s+' '+reldate,'today mjd release',@pars["debug"]||debug_here)
          #retrieve year, month and day
          y=solution_year(reldate).to_i
          m=solution_month(reldate).to_i
          d=today.day
          #make sure this combination of keys is assigned
          @rsdb[y]=Hash.new unless @rsdb.has_key?(y)
          @rsdb[y][m]=Hash.new unless @rsdb[y].has_key?(m)
          @rsdb[y][m][d]=Hash.new unless @rsdb[y][m].has_key?(d)
          #save directory day-wise
          @rsdb[y][m][d]=dir
        end
        LibUtils.peek(a[9],'mjd stop',@pars["debug"]||debug_here)
        mjd_stop_old=a[9]
      end
    when :init
      if File.exist?(dbfile)
        self.released_solutions_io(:load)
      else
        self.released_solutions_io(:build)
        self.released_solutions_io(:save)
      end
    else
      raise RuntimeError,"Cannot handle operation '#{op}',"
    end
  end

  def solution_year(reldate=@pars['reldate'])
    # LibUtils.peek(reldate,'reldate',@pars["debug"]||debug_here)
    reldate.split('_')[1].split('-')[0]
  end
  def solution_month(reldate=@pars['reldate'])
    reldate.split('_')[1].split('-')[1]
  end

  def invalid_solution_date
    ( @pars['month'].to_i.zero? or @pars['year'].to_i.zero? ) && @pars['reldate']==DEFAULT[:reldate]
  end

  #if @pars['reldate'] has the standard RL05_YY-MM, nothing happens
  # otherwise retrieve the year and month from the non-standard RL05b_YY-MM
  def solution_date(d="15")
    raise RuntimeError,"Need valid YEAR and MONTH or RELEASE_DATE to retrieve the released solution." if invalid_solution_date
    #transalate year (reldate is by default RL05_YY-MM, but some solutions from 6/2013 to 6/2014 are RL05b_YY-MM)
    if @pars['reldate']==DEFAULT[:reldate]
      y=@pars['year']
    else
      y=solution_year
    end
    #transalate month
    if @pars['reldate']==DEFAULT[:reldate]
      m=@pars['month']
    else
      m=solution_month
    end
    #over-write the defaul day value if it is set
    d=@pars['day'] unless @pars['day']==DEFAULT[:day]
    return y,m,d
  end

  def xreleased_solution
    #load/build released solutions database
    self.released_solutions_io(:init)
    #init output
    out=String.new
    begin
      #start poking at even-spaced days along a month, to try to get the solution for this year/month
      ["15","7","21","4","11","18","25"].each do |d|
        y,m,d=solution_date(d)
        LibUtils.peek("20"+y+'-'+m+'-'+d,'today', @pars["debug"])
        LibUtils.peek(@rsdb[y.to_i][m.to_i][d.to_i],"@rsdb[#{y}][#{m}][#{d}]",@pars["debug"])
        #retrieve requested solution record
        out=@rsdb[y.to_i][m.to_i][d.to_i]
        LibUtils.peek(out,'out',@pars["debug"])
        #exit loop if something was found
        break unless out.nil?
      end
      #trigger rescue if we didn't find any valid solution for this month
      raise if out.nil?
    rescue
      y,m=solution_date
      LibUtils.stderr("Could not find a released solution for 20#{y}/#{m}.")
      exit
    end
    #done
    return out.split('/iter')[0]+'/iter'
  end

  def xreleased_solution_literal
    #the released_solution dir should have the 'solution_60' directory in it
    `find #{@pars["root"]}/#{xreleased_solution} -type d -name solution_60`.chomp.split('/solution_60')[0].sub(@pars["root"]+'/','')
  end


  def get_particle(particle_name,args=Hash.new)
    debug_here=false
    args={
      :particles=>{particle_name.to_s => nil},
    }.merge(args)
    LibUtils.peek(particle_name,'in:particle_name',@pars["debug"] || debug_here)
    LibUtils.peek(args,'in:args',@pars["debug"] || debug_here)
    #retrieve lsstr with particle_name as placeholder
    lsstr_with_placeholder=xfilename(args)
    LibUtils.peek(lsstr_with_placeholder,    'lsstr_with_placeholder',       @pars["debug"] || debug_here)
    LibUtils.peek(PLACEHOLDER[particle_name],"PLACEHOLDER[#{particle_name}]",@pars["debug"] || debug_here)
    #build file match string
    fm=Regexp.new(lsstr_with_placeholder.gsub('*','.*?').gsub('+','\\\+').
      gsub(PLACEHOLDER[particle_name],'('+PLACEHOLDER_REGEXP[particle_name]+')')
    )
    LibUtils.peek(fm,'fm',@pars["debug"] || debug_here)
    #retrieve file list, considering requested parameters (args needs to be passed so that non-input filetypes can be resolved)
    file_list=xls(args.merge({
      :particles=>{particle_name.to_s => @pars[particle_name.to_s]},
    }))
    LibUtils.peek(file_list,'file_list',@pars["debug"] || debug_here)
    #loop over file list and use file match to pick the value of the requested particle
    out=Array.new
    file_list.each do |f|
      LibUtils.peek(fm,'iter:-1:fm',@pars["debug"] || debug_here)
      m=f.match(fm)
      LibUtils.peek(m,'iter:m',@pars["debug"] || debug_here)
      LibUtils.peek(m.captures.join(','),'iter:m.captures',@pars["debug"] || debug_here)
      #skip this file is there is no match
      next if m.nil?
      #save this capture
      out_now=m.captures[0]
      LibUtils.peek(out_now,'iter:0:out_now',@pars["debug"] || debug_here)
      # #TODO: figure out the reason for this
      # #get the next capture if this is "RL05" or "RL05b"
      # out_now=m.captures[1] if out_now=~/RL05|RL05b/
      # LibUtils.peek(out_now,'iter:1:out_now',@pars["debug"] || debug_here)
      # #skip this file is there is no capture
      # next if out_now.nil?
      #TODO: this needs to be fixed externally, two-digit years is the internal representation
      #special handling
      # case particle_name
      # when :year
      #   #prepend century if year
      #   out_now='20'+out_now
      # end
      # LibUtils.peek(out_now,'iter:2:out_now',@pars["debug"] || debug_here)
      #save to output array
      out<<out_now
    end
    LibUtils.peek(out,'out',@pars["debug"] || debug_here)
    return out
  end

  def xjobid
    self.get_particle(:jobid)
  end
  def xrelease
    self.get_particle(:release)
  end
  def xreldate
    self.get_particle(:reldate)
  end
  def xyear
    self.get_particle(:year)
  end
  def xmonth
    self.get_particle(:month)
  end
  def xday
    self.get_particle(:day)
  end
  def xdoy
    self.get_particle(:doy)
  end
  def xsat
    self.get_particle(:sat)
  end
  def xarc
    self.get_particle(:arc)
  end
  # #this is far too general to work 
  # def xversion
  #   self.get_particle(:version)
  # end


  def xfindstr
    unless @deppars.has_key?(:findstr)
      filename=xfilename_quick
      @deppars[:findstr] = "find "+File.dirname(filename)+" -type f -name "+File.basename(filename).gsub('*',"\\\*")+" 2> /dev/null"
    else
      @deppars[:findstr]
    end
  end

  def xfind
    unless @deppars.has_key?(:find)
      @deppars[:find] = LibUtils.natural_sort(`#{xfindstr}`.split("\n"))
      # raise unless $?.success?
    end
    @deppars[:find]
  end

  #builds a Hash with:
  # {
  #   :from_particle_name1 => [value11,value12,...],
  #   :from_particle_name2 => [value21,value22,...],
  #   ...
  # }
  def xfrom_particles(args=Hash.new)
    debug_here=false
    particles=Hash.new
    from_particles=xfiletypelist[args[:filetype]].keys.select{ |k| k.to_s.match(/.*_from/)}
    unless from_particles.nil?
      LibUtils.peek(args,'in:args',@pars["debug"] || debug_here)
      LibUtils.peek(from_particles,'from_particles',@pars["debug"] || debug_here)
      from_particles.each do |k|
        LibUtils.peek(k,'iter:k',@pars["debug"] || debug_here)
        #get target filetype
        ft=xelement(k,args[:filetype])
        LibUtils.peek(ft,'iter:ft',@pars["debug"] || debug_here)
        #get particle name (just remove '_from')
        p=k.sub('_from','').to_sym
        LibUtils.peek(p,'iter:p',@pars["debug"] || debug_here)
        #get list of particles from target filetype
        plist=self.get_particle(
          p,{:filetype=>ft}
        )
        LibUtils.peek(plist,'iter:plist',@pars["debug"] || debug_here)
        particles[p.to_s]=plist
      end
      # LibUtils.peek(particles,'out:particles',@pars["debug"] || debug_here)
    end
    return particles
  end

  #handles the output from xfrom_particles and converts it into ls-frienly strings:
  # - if the number of values in the from_particles is the same, then assemble explicit filenames
  # - if not, then use the {value1,value2,...} notation and let ls figure it out
  def xlsstr(args=Hash.new)
    debug_here=false
    #by default, lsstr is built considering the requested filetype but that can be changed internally
    args={
      :filetype=>xfiletype(args)
    }.merge(args)
    LibUtils.peek(args,'in:args',@pars["debug"] || debug_here)
    from_particles=xfrom_particles(args)
    LibUtils.peek(from_particles,'from_particles',@pars["debug"] || debug_here)
    out=String.new
    if from_particles.empty?
      out=xfilename(args)
      LibUtils.peek(out,'out:from_particles empty',@pars["debug"] || debug_here)
    else
      #build a vector with unique from_particles value lengths
      fpl=from_particles.values.map{|v| v.length}.uniq
      LibUtils.peek(fpl,'fpl',@pars["debug"] || debug_here)
      if fpl.length==1
        out=Array.new
        #all from_particle values have the same length, so build filenames explicitly
        (0...fpl[0]).each do |i|
          particles_now=Hash.new
          from_particles.each do |k,v|
            LibUtils.peek("#{k}=#{v[i]}","iter:k=v[#{i}]",@pars["debug"] || debug_here)
            particles_now[k]=v[i]
          end
          LibUtils.peek(particles_now,'iter:particles_now',@pars["debug"] || debug_here)
          out<<xfilename(args.merge({:particles=>particles_now}))
        end
        out=out.join(' ')
        LibUtils.peek(out,'out:from_particles explicit',@pars["debug"] || debug_here)
      else
        #loop over all from_particles values
        from_particles.each do |k,v|
          if v.length==1
            #if there's only one value for this particle, then use it literally
            from_particles[k]=v
          else
            #if there's multiple values, then build a {}-list
            from_particles[k]='{'+v.join(",")+'}'
          end
        end
        out=xfilename(args.merge({:particles=>from_particles}))
        LibUtils.peek(out,'out:from_particles {}-list',@pars["debug"] || debug_here)
      end
    end
    return out
  end

  def flock
    return "flock #{@pars["flock"]}"
  end

  def xls(args=Hash.new)
    debug_here=false
    LibUtils.peek(args,'in:args',@pars["debug"] || debug_here)
    lsstr=xlsstr(args)
    LibUtils.peek(lsstr,'lsstr',@pars["debug"] || debug_here)
    #cache results for later use
    if @deppars.has_key?(lsstr)
      out=@deppars[lsstr]
      LibUtils.peek(nil,'loaded from cache',@pars["debug"] || debug_here)
    else
      lsglobbed=lsstr.split(' ').ensure_array.map{|f| Dir.glob(f)}.flatten
      LibUtils.peek(lsglobbed,'lsglobbed',@pars["debug"] || debug_here)
      out=lsglobbed.map{|f| File.zero?(f) ? nil : f}.compact.uniq.sort
      @deppars[lsstr]=out
      LibUtils.peek(nil,'saved into cache',@pars["debug"] || debug_here)
    end
    LibUtils.peek(out,'out',@pars["debug"] || debug_here)
    raise RuntimeError,"Could not find any file matching #{lsstr}" if @pars["breakifempty"] && out.length==0
    return out
  end

  def robust_year_month
    if invalid_solution_date
       @pars['year'].to_i.zero? ? y="NA" : y=@pars['year']
      @pars['month'].to_i.zero? ? m="NA" : m=@pars['month']
    else
      y,m=solution_date
    end
    return y,m
  end

  def xsink(base=@pars["sink"])
    debug_here=false
    unless @deppars.has_key?(:sink)
      # y,m=robust_year_month
      # LibUtils.peek(y,'in:y',@pars["debug"] || debug_here)
      # LibUtils.peek(m,'in:m',@pars["debug"] || debug_here)
      # LibUtils.peek(@pars["year"],'in:@pars["year"]',@pars["debug"] || debug_here)
      # LibUtils.peek(@pars["month"],'in:@pars["month"]',@pars["debug"] || debug_here)
      @deppars[:sink] = base+'/'+@pars["filetype"]#+'/'+y+'/'+m
    else
      @deppars[:sink]
    end
  end

  def fsink(f)
    out=Hash.new
    out[:file]=f.sub(@pars["root"],xsink)
    out[:dir]=File.dirname(out[:file])
    `#{flock} mkdir -p #{out[:dir]} 1>&2`.chomp unless File.directory?(out[:dir])
    return out
  end

  def xfsink
    out=fsink(xfilename)
    out[:file]
  end

  def xls_scratch
    xls.each.map{ |f| fsink(f) }
  end

  def xcopy
    debug_here=false
    LibUtils.peek(xlsstr,         "xlsstr",         @pars["debug"] || debug_here)
    LibUtils.peek(xfilename_quick,"xfilename_quick",@pars["debug"] || debug_here)
    #do not copy too many files
    LibUtils.peek(xls.length,"xls.length",@pars["debug"] || debug_here)
    raise RuntimeError,"May need to copy #{xls.length} files, which is above the COPY_LIMIT (#{@pars["copylimit"]})." if xls.length>@pars["copylimit"]
    count=0
    out=Array.new
    xls.each do |f|
      sink=fsink(f)
      LibUtils.peek(f,    "iter:f",    @pars["debug"] || debug_here)
      LibUtils.peek(sink[:file],"iter:sink[:file]",@pars["debug"] || debug_here)
      if File.size?(sink[:file]).nil? || File.mtime(sink[:file]) < File.mtime(f)
        LibUtils.peek(File.mtime(f),          "iter:mtime(f)",           @pars["debug"] || debug_here)
        LibUtils.peek(File.mtime(sink[:file]),"iter:mtime(sink[:file])}",@pars["debug"] || debug_here) unless File.size?(sink[:file]).nil?
        o=`#{flock} rsync -aH --update --times --itemize-changes #{f} #{sink[:dir]} 1>&2`.chomp
        raise RuntimeError,"Failed to copy file #{f} to #{sink[:dir]}:\n#{o}" unless $?.success?
        count+=1
      end
      out.push(sink[:file])
    end
    if count>0
      LibUtils.stderr("Copied #{count} file(s) from:\n#{xlsstr}\nto:\n#{xsink}")
    end
    return out
  end

  def xgrepstr
    raise RuntimeError,"Need PATTERN." if pars["pattern"].nil?
    file_list=xls_scratch.join(' ')
    raise RuntimeError,"Found no files with name #{xfilename}." if file_list.empty?
    #NOTICE: never user --no-filename with grep because the sorting is done at the level of the filename, so that the retrieved data remains aligned
    "for file in #{file_list}; do "+
      "[ -s $file ] && "+
      "echo $file: $(grep '#{pars["pattern"]}' $file || echo '#{pars["pattern"]}'); "+
    "done"
  end

  def xgrep
    xcopy if @pars["copy"]
    out=`#{xgrepstr}`.split("\n")
    # Don't use this: it looses the blanks in parameters with sub-arcs (e.g. AC0YD6)
    # out=xls_scratch.map{ |file|
    #   open(file){ |f|
    #     f.grep(Regexp.new(@pars["pattern"])).map { |g|
    #       file+': '+g.gsub('  ',' ').chomp
    #     }
    #   }
    # }.flatten
    LibUtils.peek(out,'out',@pars["debug"])
    out=LibUtils.natural_sort(out)
    LibUtils.peek(out,'out:sorted',@pars["debug"])
    out=out.map{|o| o.sub(Regexp.new('^.*'+pars["pattern"].gsub(/\s+/, ' ')),'')} if @pars["clean-grep"]
    LibUtils.peek(out,'out:cleaned',@pars["debug"])
    return out
  end

  def xawkstr
    raise RuntimeError,"Need PATTERN." if pars["pattern"].nil?
    file_list=xls_scratch.join(' ')
    raise RuntimeError,"Found no files with name #{xfilename}." if file_list.empty?
    "awk '#{pars["pattern"].gsub("'",'"')}' #{file_list}"
  end

  def xawk
    xcopy if @pars["copy"]
    `#{xawkstr}`.split("\n")
  end

  def xnlstr
    out="wc -l #{xls_scratch.join(' ')}"
    out+=" | head -n-1" if xls_scratch.length>1
    return out
  end

  def xnl
    xcopy if @pars["copy"]
    `#{xnlstr}`.split("\n")
  end

  def xln
    linksink=File.expand_path(@pars["hardlinkdir"])
    `#{flock} mkdir -p #{linksink} 1>&2`.chomp unless File.directory?(linksink)
    LibUtils.peek(linksink,'linksink',@pars["debug"])
    out=Array.new
    xcopy.each do |f|
      if @pars["hardlinkname"].nil?
        linkname=linksink+"/"+File.basename(f)
      else
        linkname=linksink+"/"+@pars["hardlinkname"]
        unless out.length==0
          #delete previously linked file ('out' for sure already had length zero)
          File.delete(linkname)
          raise RuntimeError,"Cannot handle multiple link targets if HARDLINK_NAME is given" 
        end
      end
      LibUtils.peek(linkname,'linkname',@pars["debug"])
      unless File.exist?(linkname)
        com=`#{flock} ln #{f} #{linkname} 1>&2`.chomp
        raise RuntimeError,"Failed to ln file #{f} to #{linkname}:\n#{com}" unless $?.success?
      end
      out.push(linkname)
    end
    return out
  end

  def xdbstr
     raise RuntimeError,"Cannot grab from DB unless the element dbgrab: is defined for file of type '#{xfiletype}'" if xelement("dbgrab").nil?
     raise RuntimeError,"Cannot grab from DB unless the arguments -y, -m and -d are given" if @pars["year"]==DEFAULT[:year] || @pars["month"]==DEFAULT[:month] || @pars["day"]==DEFAULT[:day] 
     raise RuntimeError,"Cannot grab from DB unless the argument -V is given" if @pars["version"]==DEFAULT[:version]
     raise RuntimeError,"Cannot grab from DB unless the argument -s is given" if @pars["sat"]==DEFAULT[:sat]
     s=LibUtils.utc2gps(Time.utc(2000+@pars["year"].to_i,@pars["month"].to_i,@pars["day"].to_i,0,0,0)).to_s
     e=LibUtils.utc2gps(Time.utc(2000+@pars["year"].to_i,@pars["month"].to_i,@pars["day"].to_i,23,59,59)).to_s
     ". ~byaa676/.python/bin/activate; #{flock} #{xelement("dbgrab")} -s #{s} -e #{e} -i #{@pars["sat"]} -v #{@pars["version"]} 1>&2"
  end

  def xdb
    sink=fsink(GraceTree.new(['-t',xfiletype,'-y',@pars["year"],'-m',@pars["month"],'-d',@pars["day"],'-s',@pars["sat"],'-x','lsstr','-V',@pars["version"]]).xlsstr)
    unless File.exist?(sink[:file])
      file_tmp="./"+File.basename(sink[:file])
      com=`#{xdbstr}`.chomp
      raise RuntimeError,"Failed grab from DB to file #{file_tmp}:\n#{com}" unless $?.success?
      com=`#{flock} mv #{file_tmp} #{sink[:dir]} 1>&2`.chomp
      raise RuntimeError,"Failed to move grabbed data from DB in file #{file_tmp} to #{sink[:dir]}:\n#{com}" unless $?.success?
    end
    sink[:file]
  end

end

GraceTree.new(ARGV).exec if __FILE__==$0






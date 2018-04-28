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
      puts out
    end
  end

  def LibUtils.natural_sort(x)
    return x.ensure_array.sort_by {|e| e.split(/(\d+)/).map {|a| a =~ /\d+/ ? a.to_i : a }}
  end


end

class GraceTree
  attr_accessor :parfile, :pars, :pars_input, :deppars, :rsdb, :adb

  PARFILE=File.dirname(__FILE__)+"/default.par"
  PLACEHOLDER={
    :year   => 'YEAR',
    :month  => 'MONTH',
    :day    => 'DAY',
    :jobid  => 'JOBID',
    :arc    => 'ARC',
    :sat    => 'SAT'
  }
  PLACEHOLDER_REGEXP={
    :year   => '\d\d',
    :month  => '\d\d',
    :day    => '\d\d',
    :jobid  => '\d+',
    :arc    => '\d+',
    :sat    => '[AB]'
  }

  DEFAULT={
    :jobid => '*',
    :arc   => '*',
    :sat   => '[AB]'
  }
  DATABASE={
    :rs => "released_solutions.database",
  }
  PARTICLE_LIST=[
    "year","month","day","jobid","sat","arc"
  ]


  def initialize(argv)
    #default par file
    @parfile=PARFILE
    #default parameters for this run
    @pars={
      "execute"             => nil,
      "root"                => nil,
      "sink"                => ENV["SCRATCH"]+"/gracetree",
      "year"                => '[0-9][0-9]',
      "month"               => '[0-9][0-9]',
      "day"                 => '[0-9][0-9]',
      "jobid"               => DEFAULT[:jobid],
      "arc"                 => DEFAULT[:arc],
      "sat"                 => DEFAULT[:sat],
      "filetype"            => nil,
      "pattern"             => nil,
      "clean-grep"          => false,
      "argv"                => argv,
      "debug"               => false
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
    GraceTree.instance_methods(false).sort.grep(/^x/).map{|i| i.sub(/^x/,'')}
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

      opts.banner = "Usage: #{File.basename(__FILE__)} -x COMMAND [options]"
      opts.separator ""

      opts.on("-p","--parameters-file PARFILE","File with parameters (default #{PARFILE}, i.e. in the same directory as #{File.basename(__FILE__)})") do |i|
        @parfile=String.new(i.to_s)
      end
      opts.on("-x","--execute COMMAND","Perform one (or more, using the COMMAND1+COMMAND2+...COMMANDN notation) "+
        "of the following operations "+
        self.options_default_str("execute")+":\n#{GraceTree.valid_commands.join("\n")}") do |i|
        @pars["execute"]=String.new(i.to_s)
      end
      opts.on("-r","--root ROOT","Index files below ROOT "+
        self.options_default_str("root")+'.') do |i|
        @pars["root"]=File.expand_path(String.new(i.to_s))
      end
      opts.on("-S","--sink SINK","Copy files to SINK/FILETYPE "+
        self.options_default_str("sink",", i.e. $SCRATCH/gracetree")+'.') do |i|
        @pars["sink"]=File.expand_path(String.new(i.to_s))
      end
      opts.on("-y","--year YEAR","Replace the placeholder '#{PLACEHOLDER[:year]}' in SUBIR or INFIX with this value "+
        self.options_default_str("year")+'.') do |i|
        begin
          @pars["year"]=String.new("%02d" % i.to_s)
        rescue ArgumentError
          @pars["year"]=String.new(i.to_s)
        end
        #some sanity
        raise RuntimeError,"Expecting --year to be two digits." unless @pars["year"].length==2

      end
      opts.on("-m","--month MONTH","Replace the placeholder '#{PLACEHOLDER[:month]}' in SUBIR or INFIX with this value "+
        self.options_default_str("month")+'.') do |i|
        begin
          @pars["month"]=String.new("%02d" % i.to_s)
        rescue ArgumentError
          @pars["month"]=String.new(i.to_s)
        end
      end
      opts.on("-d","--day DAY","Replace the placeholder '#{PLACEHOLDER[:day]}' in SUBIR or INFIX with this value "+
        self.options_default_str("day")+'.') do |i|
        begin
          @pars["day"]=String.new("%02d" % i.to_s)
        rescue ArgumentError
          @pars["day"]=String.new(i.to_s)
        end
      end
      opts.on("-j","--jobid JOBID","Replace the placeholder '#{PLACEHOLDER[:jobid]}' in PREFIX, INFIX or SUFFIX with this value "+
        self.options_default_str("jobid")+'.') do |i|
        @pars["jobid"]=String.new(i.to_s)
      end
      opts.on("-t","--filetype FILETYPE","Gather files of type FILETYPE "+
        self.options_default_str("filetype")+'.') do |i|
        @pars["filetype"]=String.new(i.to_s)
      end
      opts.on("-g","--pattern PATTERN","Grep PATTERN from the files in SINK/FILETYPE "+
        self.options_default_str("pattern")+'.') do |i|
        @pars["pattern"]=String.new(i.to_s)
      end
      opts.on("-a","--arc ARC","Replace the placeholder '#{PLACEHOLDER[:arc]}' in INFIX with this value "+
        self.options_default_str("arc")+'.') do |i|
        @pars["arc"]=String.new(i.to_s)
      end
      opts.on("-s","--satellite SAT","Replace the placeholder '#{PLACEHOLDER[:sat]}' in PREFIX, INFIX or SUFFIX with this value "+
        self.options_default_str("sat")+'.') do |i|
        @pars["sat"]=String.new(i.to_s)
      end
      opts.on("-c","--[no-]clean-grep","Remove filename and PATTERN from grep output "+
        self.options_default_str("clean-grep")+'.') do |i|
        @pars["clean-grep"]=i
      end
      opts.on("-?","--[no-]debug","Turn on debug mode "+
        self.options_default_str("debug",' and makes output very verbose!')+'.') do |i|
        @pars["debug"]=i
      end

      opts.on_tail( '-h', '--help', 'Display this screen.' ) do
        puts opts
        exit
      end
      raise RuntimeError,"Directory #{pars["sink"]} does not exist, please create it." unless File.directory?(@pars["sink"])
    end
    #parse it
    out.parse(argv)

    #need command
    if @pars["execute"].nil?
      puts out
      raise RuntimeError,"Need COMMAND."
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
    LibUtils.peek(args,'args',@pars["debug"]&&debug_here)
    case
    when args[:com].include?('+')
      dat=Hash.new
      LibUtils.peek(args[:com],'com',@pars["debug"]&&debug_here)
      c0=nil
      n0=nil
      args[:com].split('+').each do |c|
        LibUtils.peek(c,'iter:c',@pars["debug"]&&debug_here)
        dat[c]=self.exec({:com => c, :return_array => true})
        LibUtils.peek(n0,'iter:n0',@pars["debug"]&&debug_here)
        LibUtils.peek(c0,'iter:c0',@pars["debug"]&&debug_here)
        LibUtils.peek(dat[c].length,'iter:dat[c].length',@pars["debug"]&&debug_here)
        raise RuntimeError,"When using the COMMAND1+COMMAND2+...COMMANDN notation, "+
          "the COMMANDs need to refer to methods that return arrays." unless dat[c].is_a?(Array)
        if n0.nil?
          n0=dat[c].length
          c0=c;
        else
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

  def xfiletype
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

  def xfilename_raw(args=Hash.new)
    args={
      :filetype=>xfiletype,
      :add_root=>true,
    }.merge(args)
    #build complete filename
    out=String.new
    out+=@pars["root"]+"/" if args[:add_root]
    out+=xfiletypelist[args[:filetype]]["subdir"]+'/' unless xfiletypelist[args[:filetype]]["subdir"].nil?
    ["prefix","infix","suffix"].each do |k|
      out+=xfiletypelist[args[:filetype]][k] unless xfiletypelist[args[:filetype]][k].nil?
    end
    return out
  end

  def xfilename(args=Hash.new)
    debug_here=true
    args={
      :particles=>Hash.new,
      :wildcarded_named_parts=>false,
    }.merge(args)
    LibUtils.peek(args,'in:args',@pars["debug"]&&debug_here)
    out=xfilename_raw(args)
    LibUtils.peek(out,'1:out',@pars["debug"]&&debug_here)
    #replace named parts
    named_parts=out.match(/<.*?>/)
    LibUtils.peek(named_parts,'1:named_parts',@pars["debug"]&&debug_here)
    #loop over all named parts
    named_parts.to_a.map{ |n| n.gsub(/<|>/,'') }.each do |n|
      LibUtils.peek(n,'iter:n',@pars["debug"]&&debug_here)
      #retrieve string to replace the named part
      if args[:wildcarded_named_parts]
        replace_str=xfilename_raw({
          :filetype=>n,
          :add_root=>false
        })
      else
        replace_str=self.method('x'+n).call
      end
      LibUtils.peek(replace_str,'iter:replace_str',@pars["debug"]&&debug_here)
      out=out.gsub("<#{n}>",replace_str)
      LibUtils.peek(out,'iter:out',@pars["debug"]&&debug_here)
    end
    #remove double slashes
    out=out.gsub('//','/')
    LibUtils.peek(out,'2:out',@pars["debug"]&&debug_here)
    #update relevant particles
    particles=xparticles(args[:particles])
    LibUtils.peek(particles,'particles',@pars["debug"]&&debug_here)
    #replace placeholders with requested filename parts
    [:year,:month,:day,:jobid,:sat,:arc].each do |k|
      LibUtils.peek(k,'iter:k',@pars["debug"]&&debug_here)
      out=out.gsub(PLACEHOLDER[k],particles[k.to_s].to_s) unless particles[k.to_s].nil?
      LibUtils.peek(out,'iter:out',@pars["debug"]&&debug_here)
    end
    return out
  end

  def xfilename_quick
    #update filename if needed
    @deppars[:filename]=xfilename unless @deppars.has_key?(:filename)
    #return saved filename
    @deppars[:filename]
  end

  def xparticles(particles=Hash.new)
    out=Hash.new
    PARTICLE_LIST.each do |k|
      out[k]=@pars[k]
    end
    return out.merge(particles)
  end

  def released_solutions_io(op,dbfile=@pars["sink"]+'/'+DATABASE[:rs])
    case op
    when :load
      @rsdb=YAML.load_file(dbfile)
    when :save
      File.open(dbfile,'w') {|f| f.write(@rsdb.to_yaml)}
    when :build
      #get file with solution list
      estimdirfile=GraceTree.new(['-t','estimdir']).xfind
      raise RuntimeError,"Expecting the EstimDirs file to be one, not #{estimdirfile.length}." unless estimdirfile.length==1
      #build released solutions database
      @rsdb=Hash.new
      File.foreach(estimdirfile[0]) do |l|
        a = l.split(' ');
        y = a[1].sub('20','').to_i
        m = Date::MONTHNAMES.index(a[2])
        @rsdb[y]=Hash.new unless @rsdb.has_key?(y)
        @rsdb[y][m]=Hash.new unless @rsdb[y].has_key?(m)
        @rsdb[y][m]=a[4].sub(@pars["root"]+"/",'')
        @rsdb[y][m].chop! if @rsdb[y][m][-1..-1]=='/'
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

  def xreleased_solution
    raise RuntimeError,"Need valid YEAR and MONTH to retrieve the released solution." if @pars['month'].to_i.zero? or @pars['year'].to_i.zero?
    #load/build released solutions database
    self.released_solutions_io(:init)
    #retrieve requested solution record
    out=@rsdb[@pars['year' ].to_i][@pars['month'].to_i]
    LibUtils.peek(out,'out',@pars["debug"])
    raise RuntimeError,"Could not find a released solution for 20#{@pars['year']}/#{@pars['month']}." if out.nil?
    return out
  end

  def xsink(base=@pars["sink"])
    raise RuntimeError,"Need valid YEAR and MONTH to build sink directory name." if @pars['month'].to_i.zero? or @pars['year'].to_i.zero?
    unless @deppars.has_key?(:sink)
      @deppars[:sink] = base+'/'+@pars["filetype"]+'/'+@pars['year']+'/'+@pars['month']
    else
      @deppars[:sink]
    end
  end

  def get_particle(particle_name,args=Hash.new)
    debug_here=true
    args={
      :particles=>{particle_name.to_s => nil},
      :wildcarded_named_parts => true
    }.merge(args)
    LibUtils.peek(particle_name,'in:particle_name',@pars["debug"]&&debug_here)
    LibUtils.peek(args,'in:args',@pars["debug"]&&debug_here)
    #retrieve lsstr with particle_name as placeholder
    lsstr_with_placeholder=xfilename(args)
    LibUtils.peek(lsstr_with_placeholder,    'lsstr_with_placeholder',       @pars["debug"]&&debug_here)
    LibUtils.peek(PLACEHOLDER[particle_name],"PLACEHOLDER[#{particle_name}]",@pars["debug"]&&debug_here)
    #build file match string
    fm=Regexp.new(lsstr_with_placeholder.gsub('*','.*?').gsub('+','\\\+').
      gsub(PLACEHOLDER[particle_name],'('+PLACEHOLDER_REGEXP[particle_name]+')')
    )
    LibUtils.peek(fm,'fm',@pars["debug"]&&debug_here)
    #retrieve file list, considering requested parameters (args needs to be passed so that non-input filetypes can be resolved)
    file_list=xls(args.merge({
      :particles=>{particle_name.to_s => @pars[particle_name.to_s]},
      :wildcarded_named_parts => false
    }))
    LibUtils.peek(file_list,'file_list',@pars["debug"]&&debug_here)
    #loop over file list and use file match to pick the value of the requested particle
    out=Array.new
    file_list.each do |f|
      m=f.match(fm)
      LibUtils.peek(m,'iter:m',@pars["debug"]&&debug_here)
      #skip this file is there is no match
      next if m.nil?
      #save this capture
      out_now=m.captures[0]
      #get the next captuure if this is "RL05" or "RL05b"
      out_now=m.captures[1] if out_now=~/RL05|RL05b/
      LibUtils.peek(out_now,'iter:1:out_now',@pars["debug"]&&debug_here)
      #skip this file is there is no capture
      next if out_now.nil?
      #append century if year
      out_now='20'+out_now if particle_name==:year
      LibUtils.peek(out_now,'iter:2:out_now',@pars["debug"]&&debug_here)
      #save to output array
      out<<out_now
    end
    LibUtils.peek(out,'out',@pars["debug"]&&debug_here)
    return out
  end

  def xjobid
    self.get_particle(:jobid)
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
  def xsat
    self.get_particle(:sat)
  end
  def xarc
    self.get_particle(:arc)
  end

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

  def xlsstr(args=Hash.new)
    #by default, lsstr is built considering the requested filetype but that can be changed internally
    args={
      :filetype=>xfiletype
    }.merge(args)
    LibUtils.peek(args,'in:args',@pars["debug"])
    from_particles=xfiletypelist[args[:filetype]].keys.find{ |k| k.to_s.match(/.*_from/)}
    LibUtils.peek(from_particles,'from_particles',@pars["debug"])
    if from_particles.nil?
      out=xfilename(args)
    else
      particles=Hash.new
      from_particles.each do |k|
        LibUtils.peek(k,'iter:k',@pars["debug"])
        #get target filetype
        ft=xfiletypelist[xfiletype][k]
        LibUtils.peek(ft,'iter:ft',@pars["debug"])
        #get particle name (just remove '_from')
        p=k.sub('_from','').to_sym
        LibUtils.peek(p,'iter:p',@pars["debug"])
        #get list of particles from target filetype
        particles[p.to_s]='{'+
          self.get_particle(
            p,{:filetype=>ft}
          ).join(",")+
          '}'
        LibUtils.peek(particles,'iter:particles',@pars["debug"])
      end
      out=xfilename(args.merge({:particles=>particles}))
    end
    LibUtils.peek(out,'out',@pars["debug"])
    return out
  end

  def xls(args=Hash.new)
    LibUtils.peek(args,'in:args',@pars["debug"])
    out = LibUtils.natural_sort(`$(which ls) -1 -U #{xlsstr(args)}`.split("\n").map{|f| File.zero?(f) ? nil : f}.compact)
    raise RuntimeError,"Could not list the requested files." unless $?.success?
    return out
  end

  def xcopy
    `mkdir -p #{xsink}`.chomp unless File.directory?(xsink)
    count=0
    xls.each do |f|
      out=`cp --update --preserve=all #{f} #{xsink}`.chomp
      unless out.empty?
        puts out
        count+=1
      end
    end
    "Copied #{count} files from:\n#{xlsstr}\nto:\n#{sink}" if count>0
  end

  def xgrepstr
    raise RuntimeError,"Need PATTERN." if pars["pattern"].nil?
    #NOTICE: never user --no-filename with grep because the sorting is done at the level of the filename, so that the retrieved data remains aligned
    "for file in $($(which ls) -1 -U #{xsink}/#{File.basename(xfilename_quick)}); do "+
      "[ -s $file ] && "+
      "echo $file: $(grep '#{pars["pattern"]}' $file || echo '#{pars["pattern"]}'); "+
    "done"
  end

  def xgrep
    xcopy
    out=LibUtils.natural_sort(`#{xgrepstr}`.split("\n"))
    out=out.map{|o| o.sub(Regexp.new('^.*'+pars["pattern"].gsub(/\s+/, ' ')),'')} if @pars["clean-grep"]
    return out
  end

  def xawkstr
    raise RuntimeError,"Need PATTERN." if pars["pattern"].nil?
    "awk '#{pars["pattern"]}' #{xsink}/#{File.basename(xfilename_quick)}"
  end

  def xawk
    xcopy
    `#{xawkstr}`.split("\n")
  end


end

GraceTree.new(ARGV).exec if __FILE__==$0





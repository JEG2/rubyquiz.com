##############################################################################
# A Distributed Testing Service for RubyQuiz 73
#
# Author:  Robert Feldt (robert.feldt@gmail.com)
# Version: 0.4
# Date:    2006-03-30
##############################################################################
require 'drb'
require 'fileutils'
require 'digest/md5'

class Module
  def undef_all_but(*excluded)
    instance_methods.each do |m|
      undef_method(m) unless excluded.any? {|p| m =~ p}
    end
  end
end

module RubyQuiz73
  class BlankSlate
    undef_all_but /^__/
  end

  # Proxy for the class on the client side so that it really is a class and
  # not a DRbObject. Might be needed in assertions etc.
  class ClassUnderTestProxy
    # We exclude kind_of? so that assert_kind_of can be used in the tests
    undef_all_but /^kind_of\?$/, /^__/

    class <<self
      attr_accessor :___cut_proxy
      def new(*args, &block)
        super(___cut_proxy.new(*args, &block))
      end
      def new_subclass(cutProxy)
        klassproxy = Class.new(ClassUnderTestProxy)
        klassproxy.___cut_proxy = cutProxy
        klassproxy
      end
      # XXX: You currently have to list the class methods that should
      # be proxied over to the CUT on the server.
      undef_method "instance_methods"
      def method_missing(m, *a, &b)
        ___cut_proxy.send(m, *a, &b)
      end
    end

    def initialize(o); @o = o; end

    def method_missing(m, *a, &b)
      # Note that we do not wrap results even if they are CUT instances
      # since it has too steep a price in terms of performance.
      res = @o.send(m, *a, &b)
    end
  end

  class DistrTestingService
    def initialize(srcfilenames = nil)
      @black_num, @white_num = 0, 0
      @log_filename = Time.now.strftime("dts_log_%Y%m%d_%H%M%S.txt")
      @log = File.open(@log_filename, "a")
      @proxied_classes = []
      @src_file_pack = FilePack.new(srcfilenames)
    end

    def cut=(cut)
      @cut = cut
      add_proxied_class(cut)
    end

    attr_reader :cut

    def add_proxied_class(klass)
      @proxied_classes << klass
    end

    # Return a proxy to the CUT
    def cut_proxy(email)
      raise "No Class Under Test has been specified" unless @cut
      LoggingProxy.new(@log, email, @cut, @proxied_classes)
    end

    class LoggingProxy < BlankSlate
      include DRb::DRbUndumped
    
      def initialize(log, email, obj, proxiedClasses = [])
        @log, @email, @o, @proxied_classes = log, email, obj, proxiedClasses
      end

      # Exclude some methods from the log since DRb calls will flood it 
      # otherwise
      ExcludedMethods = [:private_methods, :protected_methods,
                         "respond_to?".intern, "kind_of?".intern,
                         "nil?".intern]

      def ___log?(m)
        !ExcludedMethods.include?(m)
      end

      def method_missing(method, *args, &block)
        if ___log?(method)
          s = "#{@email},#{@o.object_id},#{@o.class.inspect},#{method},#{args.inspect}" 
          msg = Time.now.strftime("%Y%m%d %H:%M.%S, #{s}")
          msg << ",with_block" if block

          begin
            @log.puts(msg)
          rescue
            puts "Could not log #{msg}"
          end
        end

        if [:eval, :module_eval, :class_eval, :instance_eval].include?(method)
          @log.puts "  Trying something nasty; disallow"
          raise "No, no no no, don't funk with my sys!"
        end

        res = @o.send(method, *args, &block)

        if ___log?(method)
          begin
            @log.puts "  => #{res.inspect}"
          rescue
            # in case the result cannot be inspected or problem with log file.
            puts "Could not log result"
          end
        end

        # Flush every now and then so we do not miss log entries if server 
        # goes down. We need not do it very often though since many messages
        # are created for each "real" message send.
        @log.flush if rand() < 0.001

        if @proxied_classes.include?(res.class)
          res = LoggingProxy.new(@log, @email, res, @proxied_classes)
        end

        return res
      end
    end

    # A FilePack is a set of named files with their contents.
    class FilePack
      def initialize(filenames = nil)
        @files = {}
        @md5s = {}
        filenames.each {|fn| add_file(fn)} if Array === filenames 
      end

      # Allow max 5e5 byte files so server hd is not flooded
      MaxFileSize = 5e5

      def add_file(filename, contents = nil)
        contents ||= File.open(filename) {|fh| fh.read(MaxFileSize)}
        if contents.length > MaxFileSize
          contents = contents[0,MaxFileSize]
        end
        @md5s[filename] = Digest::MD5.new(contents).hexdigest
        @files[filename] = contents
      end

      def save_files_under(dirPath)
        Dir.chdir(dirPath) do
          @files.each do |name, contents|
            File.open(name, "w") {|fh| fh.write contents}
            puts "Saved file #{name}"
          end
        end
      end

      def summary_info
        @files.map do |name, contents|
          "  #{name.ljust(24)} (size: #{contents.size}, md5: #{@md5s[name]})"
        end.join("\n")
      end
    end

    def submit_testsuite(email, filePack, dirNameTemplate)
      t = Time.now
      dirname = t.strftime(dirNameTemplate + "_%Y%m%d_%H%M%S")
      dir = File.join(Dir.pwd, dirname)
      FileUtils.mkdir_p dir
      info = <<-EOS
email: #{email.strip}
time:  #{t.inspect}
files:
#{filePack.summary_info}
      EOS
      filePack.add_file("___info___.txt", info)
      filePack.save_files_under(dir)
    end

    def submit_blackbox_testsuite(email, filePack)
      @black_num += 1
      submit_testsuite(email, filePack, 
                       "black#{@black_num}_" + flatten_email(email))
      return @src_file_pack
    end
    
    def flatten_email(email)
      email.gsub("@", "__at__").gsub(/[^\w]/, "_")
    end

    def submit_whitebox_testsuite(email, filePack)
      @white_num += 1
      submit_testsuite(email, filePack, 
                       "white#{@white_num}_" + flatten_email(email))
    end
  end # DistrTestingService

  TestingServiceUrls = 
    [
     "druby://pronovomundo.com:2000",
     "druby://aquas.htu.se:8954",
    ]
  MainTestingServiceUrl = TestingServiceUrls.first

  def self.dts
    return @dts unless @dts.nil?
    TestingServiceUrls.each do |url|
      begin
        @dts = DRbObject.new(nil, url)
        # Ensure we really have a connection by asking it to flatten email adr
        if @dts.flatten_email("d@d.com") == "d__at__d_com"
          puts "Connected to DistrTestingService at #{url}"
          return @dts
        end
      rescue Exception
      end
      puts "Could not connect to #{url}"
    end
    raise "Did not find any testing service online" unless @dts
    @dts
  end

  def self.dts=(dts); @dts = dts; end

  def self.cut_proxy(email)
    @cut_proxy ||= dts.cut_proxy(email)
  end

  def self.valid_email?(email)
    String === email && email =~ /^[a-zA-Z_\.0-9]+@[a-zA-Z_\.0-9]+$/
  end

  def self.class_under_test(email)
    raise "You must give a valid email" unless valid_email?(email)
    cp = cut_proxy(email)
    cpl = ClassUnderTestProxy.new_subclass(cp)
    cpl
  end
end # RubyQuiz73

def undef_basic_attack_methods
  eval %{
    module Kernel
      [:eval, :system, :exec, :callcc, :`,               # `
       :set_trace_func, :sleep, :syscall].each do |m| 
        undef_method m
      end
    end

    class Module
      [:module_eval, :class_eval, 
       :define_method, :method, :instance_method,
       :private_class_method].each do |m| 
        undef_method m
      end
    end

    class Object
      [:instance_eval].each {|m| undef_method m}
    end
  }
end

SRC_FILES = ["digraph.rb"]

def run_as_server
  puts "Starting Distributed Testing Service"
  DRb.start_service
  include RubyQuiz73
  url = ARGV[1] || MainTestingServiceUrl
  SRC_FILES.each {|sf| require File.basename(sf, ".rb")}
  RubyQuiz73.dts = DistrTestingService.new(SRC_FILES)
  RubyQuiz73.dts.cut = DiGraph
  undef_basic_attack_methods()
  DRb.start_service url, RubyQuiz73.dts
  $SAFE = 1
  puts DRb.uri
  DRb.thread.join
end

def describe_usage
  usage = <<EOS

Command and code for taking part in RubyQuiz 73: Distributed DiGraph Testing.

 Usage:
  ruby #{$0} help                       - print this help text
  ruby #{$0} submit1 <file1> <file2> .. - submit file(s) after blackbox
  ruby #{$0} submit2 <file1> <file2> .. - submit file(s) after whitebox
  
 Examples:
  ruby #{$0} submit1 test_digraph.rb  
  ruby #{$0} submit2 test_digraph2.rb digraph_fixed.rb  

 Further information:
  robert.feldt@gmail.com
EOS
  puts usage
end

def all_files_exist(filenames)
  filenames.all? {|fn| File.exist?(fn)}
end

def answer(question, message = nil)
  STDOUT.puts message if message
  STDOUT.puts ""
  STDOUT.print question
  STDOUT.flush 
  STDIN.gets.strip
end

def if_answer(question, trueAnswers = [], &block)
  a = answer(question)
  block.call if trueAnswers.include?(a) && block != nil
end

def request_email()
  email = nil
  while email == nil
    email = answer("What is your email address? ", "In order to submit you need to give your email adress. You should give the same email adress for all your submissions.")
    unless RubyQuiz73.valid_email?(email)
      puts "Email address invalid: #{email}"
      email = nil
    end
  end
  email
end

def execute_submit_command(filenames, blackBox = true)
  if blackBox && filenames.length < 1
    puts "ERROR: You must submit at least one test file after the black box phase"
    exit -1
  elsif blackBox == false && filenames.length < 1
    puts "ERROR: You must submit at least one test file after the white box phase"
    exit -1
  end
  unless all_files_exist(filenames)
    puts "ERROR: Not all of the named files was found"
    exit -1
  end
  email = request_email()
  fp = RubyQuiz73::DistrTestingService::FilePack.new(filenames)
  puts "The following files will be submitted:\n#{fp.summary_info}"
  if_answer("Ok? [Y/n] ", ["", "Y", "y"]) do
    puts "Submitting files"
    if blackBox
      src_filepack = RubyQuiz73.dts.submit_blackbox_testsuite(email, fp)
      if RubyQuiz73::DistrTestingService::FilePack === src_filepack
        src_filepack.save_files_under(".")
      else
        puts "ERROR: Did not get back any source code files"
      end
    else
      RubyQuiz73.dts.submit_whitebox_testsuite(email, fp)
    end
  end
end

def run_as_command
  case ARGV[0]
  when "submit1", /black/
    execute_submit_command(ARGV[1..-1], true)
  when "submit2", /white/
    execute_submit_command(ARGV[1..-1], false)
  when "help"
    describe_usage()
  else
    puts "ERROR: Unknown command  #{ARGV[0]}"
    describe_usage()
  end
end

if $0 == __FILE__
  if ARGV[0] == "server" 
    run_as_server()
  else
    run_as_command()
  end
else
  # We have been included in a test session.
  # Nothing to do (the drb connection will be set up when the user
  # calls class_under_test.
end

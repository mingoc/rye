module Rye
  
  # = Rye::Set
  #
  #
  class Set
    attr_reader :name
    attr_reader :boxes
    attr_reader :opts
    
    # * +name+ The name of the set of machines
    # * +opts+ a hash of optional arguments 
    #
    # The +opts+ hash is used as defaults for all for all Rye::Box objects. 
    # All args supported by Rye::Box are available here with the addition of:
    #
    # * :parallel => run the commands in parallel? true or false (default).
    #
    def initialize(name='default', opts={})
      @name = name
      @boxes = []
      
      # These opts are use by Rye::Box and also passed to Net::SSH
      @opts = {
        :parallel => false,
        :user => Rye.sysinfo.user, 
        :safe => true,
        :port => 22,
        :keys => [],
        :password => nil,
        :proxy => nil,
        :debug => nil,
        :error => STDERR,
      }.merge(opts)
      
      @parallel = @opts.delete(:parallel) # Rye::Box doesn't have :parallel
      
      @safe = @opts.delete(:safe)
      @debug = @opts.delete(:debug)
      @error = @opts.delete(:error)

      add_keys(@opts[:keys])
    end
    
    # * +boxes+ one or more boxes. Rye::Box objects will be added directly 
    # to the set. Hostnames will be used to create new instances of Rye::Box 
    # and those will be added to the list. 
    def add_box(*boxes)
      boxes = boxes.flatten.compact 
      @boxes += boxes.collect do |box|
        b = box.is_a?(String) ? Rye::Box.new(box, @opts) : box
        b.add_keys(@keys)
        b
      end
      self
    end
    alias :add_boxes :add_box
    
    # Add one or more private keys to the SSH Agent. 
    # * +additional_keys+ is a list of file paths to private keys
    # Returns the instance of Rye::Set
    def add_key(*additional_keys)
      additional_keys = [additional_keys].flatten.compact || []
      Rye.add_keys(additional_keys)
      self
    end
    alias :add_keys :add_key
    
    # Add an environment variable. +n+ and +v+ are the name and value.
    # Returns the instance of Rye::Set
    def add_env(n, v)
      run_command(:add_env, n, v)
      self
    end
    alias :add_environment_variable :add_env
    
    # See Rye.keys
    def keys
      Rye.keys
    end
    
    def to_s
      "%s: %s" % [self.name, ]
    end
    
    def inspect
      %q{#<%s:%s boxes=%s opts=%s>} % [self.class.to_s, self.name, self.boxes.join(','), self.opts.inspect]
    end
    
    # See Rye::Box.[]
    def [](key=nil)
      run_command(:cd, key)
      self
    end
#    alias :cd :'[]'  # fix for jruby
    def cd(key=nil)
      run_command(:cd, key)
      self
    end

    # Catches calls to Rye::Box commands. If +meth+ is the name of an 
    # instance method defined in Rye::Cmd then we call it against all 
    # the boxes in +@boxes+. Otherwise this method raises a
    # Rye::CommandNotFound exception. It will also raise a Rye::NoBoxes
    # exception if this set has no boxes defined. 
    #
    # Returns a Rye::Rap object containing the responses from each Rye::Box. 
    def method_missing(meth, *args)
      # Ruby 1.8 populates Module.instance_methods with Strings. 1.9 uses Symbols.
      meth = (Rye.sysinfo.ruby[1] == 8) ? meth.to_s : meth.to_sym
      raise Rye::NoBoxes if @boxes.empty?
      raise Rye::CommandNotFound, meth.to_s unless Rye::Cmd.instance_methods.member?(meth)
      run_command(meth, *args)
    end
    
  private
    
    # Determines whether to call the serial or parallel method, then calls it. 
    def run_command(meth, *args)
      runner = @parallel ? :run_command_parallel : :run_command_serial
      self.send(runner, meth, *args)
    end
    
    
    # Run the command on all boxes in parallel
    def run_command_parallel(meth, *args)
      p @boxes
      debug "P: #{meth} on #{@boxes.size} boxes (#{@boxes.collect {|b| b.host }.join(', ')})"
      threads = []
      
      raps = Rye::Rap.new(self)
      (@boxes || []).each do |box|
        threads << Thread.new do
          Thread.current[:rap] = box.send(meth, *args) # Store the result in the thread
        end
      end
      
      # Should it bubble up the exception for a single box?
      # socket errors?
      threads.each do |t| 
        sleep 0.01        # Give the thread some breathing room
        t.join            # Wait for the thread to finish
        raps << t[:rap]   # Grab the result
      end
      
      raps
    end
    
    
    # Run the command on all boxes in serial
    def run_command_serial(meth, *args)
      debug "S: #{meth} on #{@boxes.size} boxes (#{@boxes.collect {|b| b.host }.join(', ')})"
      raps = Rye::Rap.new(self)
      (@boxes || []).each do |box|
        raps << box.send(meth, *args)
      end
      raps
    end
    
    def debug(msg); @debug.puts msg if @debug; end
    def error(msg); @error.puts msg if @error; end
  
  end
  
end
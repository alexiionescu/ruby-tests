# frozen_string_literal: true

# rubocop:disable Style/Documentation
# rubocop:disable Style/ClassVars

LIB_CONST_TEST = 200

class Test1
  attr_accessor :some_var1

  CONST_TEST = 100
  @@tests = 0 # counts how many times test was called on any Test1 instances
  def initialize
    @itests = 0 # counts how many times test was called on this instance
    @some_var1 = 1
  end

  attr_reader :itests

  # instance method
  def test(add = 0, log: false)
    @@tests += 1
    @itests += 1
    @some_var1 += add
    puts "[#{format('%03d', object_id)}] Test1 test #{@itests} some_var1=#{@some_var1}" if log
    self # return self instance to allow chaining
  end

  # class method,self is class itself
  def self.tests
    @@tests
  end
end

class TestChild1 < Test1
  def test(add = 0)
    # super # call parent method with same arguments as child method
    super(add, log: false) # call parent method without logging
    puts "[#{format('%03d', object_id)}] TestChild1 test #{@itests} some_var1=#{@some_var1}"
    self
  end
end

module TestModule
  class TestEx < TestChild1
    def test(add = 0)
      # call grand parent test
      Test1.instance_method(:test).bind_call(self, add, log: false)
      puts "[#{format('%03d', object_id)}] TestEx test #{@itests} some_var1=#{@some_var1}"
      self
    end
  end
end

module TestInterface
  CONST_MOD_TEST = 150
  attr_accessor :some_var1

  def initialize
    @some_var1 = 1
  end

  def if_test
    raise 'Not implemented'
  end

  def if_test_lambda
    raise 'Not implemented'
  end
end

class Test2
  include TestInterface

  def if_test
    puts "Test2 if_test some_var1=#{@some_var1} CONST_MOD_TEST=#{CONST_MOD_TEST}"
    self
  end

  def if_test_lambda
    if block_given?
      yield @some_var1
    else
      puts 'Test2 if_test_lambda no block'
    end
  end
end

# rubocop:enable Style/Documentation
# rubocop:enable Style/ClassVars

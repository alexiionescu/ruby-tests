require_relative 'lib/oo_test_cls'

puts "Test1 public class methods\n#{Test1.public_methods(false)}"
puts "Test1 public instance methods\n#{Test1.public_instance_methods(false)}"

puts "\n------- Test1 testing -------\n"

t1_n1 = Test1.new
t1_n1.test.test(log: true)

t1_n2 = Test1.new
t1_n2.test.test(5).test(10, log: true)
t1_n2.test(5, log: true)

tc1 = TestChild1.new.test(5)
tc1.test(5)

puts "t1_n1.test was called #{t1_n1.itests} times"
puts "t1_n2.test was called #{t1_n2.itests} times"
puts "tc1.test   was called #{tc1.itests} times"
puts "Test1.test was called #{Test1.tests} times"

puts "\n------- Other classes and modules -------\n"
t2 = Test2.new.if_test
t2.some_var1 = 10
t2.if_test_lambda { |v| puts "Test2 if_test_lambda v=#{v}" }
t2.some_var1 = 20
puts "Test2->some_var1=#{t2.some_var1}"
t2.some_var1 = 30
t2.if_test
t2.if_test_lambda

puts <<~TEST
  Contants from Test1 and lib/utils.rb
    Test1::CONST_TEST=#{Test1::CONST_TEST}
    LIB_CONST_TEST=#{LIB_CONST_TEST}
TEST

puts "\n------- Extending classes -------\n"

module TestModule
  # extend class TestEx
  class TestEx
    def new_test
      puts "[#{format('%03d', object_id)}] TestEx new_test #{@itests} some_var1=#{@some_var1}"
    end
  end
end

tcex = TestModule::TestEx.new.test(5).test(2)
tcex.new_test

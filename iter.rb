require 'json'

# s_array = ['Sharon', 'Leo', 'Leila', 'Brian', 'Arun']
s_array = %w[Sharon Leo Leila Brian Arun]

puts "s_array has Sharon => #{s_array.include?('Sharon')}"

s_array.reject { |name| name.start_with?('L') }
       .map(&:upcase)
       .each { |name| puts "Hi, #{name}" }
#  .each_with_index { |name, index| puts "#{index+1}. Hi, #{name}" }

h_sample = { a: 1, b: 2, c: 3,
             many: [1, 2, 3], # same as :many => [1,2,3]
             sub_hash: { a: 1, b: 2, c: 3 } }
puts 'Select and print key-value pairs where value is not 3'
h_sample.select { |_k, v| !(v.is_a? Integer) || v != 3 }
        .each { |key, value| puts "#{key} => #{value}" }

puts "h_smaple has many key => #{h_sample.include?(:many)}"
h_sample[:sub_hash][:d] = 4
puts "h_sample[:sub_hash][:e] is nil? => #{h_sample[:sub_hash][:e].nil?}"
# puts "h_sample[:missing][:e] is nil? => #{h_sample[:missing][:e].nil?}" # NoMethodError
puts "h_sample[:missing][:e] is nil? with catch all => #{begin
  h_sample[:missing][:e].nil?
rescue StandardError
  true
end}" # rescue catch all exceptions
puts "h_sample.dig(:missing,:e) is nil? => #{h_sample.dig(:missing, :e).nil?}"

# h_sample_collected = h_sample.collect {|k,v| [k, v * 2] if v.is_a? Integer }.compact
h_sample_collected = h_sample.filter_map { |k, v| [k, v * 2] if v.is_a? Integer }
p h_sample_collected

j_sample = JSON h_sample
puts j_sample

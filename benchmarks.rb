require 'benchmark'
require 'prime'

DATA = Prime.first(10_000).to_a.freeze
BIG_PRIME = 15_485_863 # Prime.first(1_000_000).last

# print "Data size: #{DATA.size}. Big prime: #{BIG_PRIME}. \n"
# Accumulator class that maintains a running sum modulo 99,991 using values from the DATA array.
class Accumulator
  attr_reader :value

  def initialize(data_size = DATA.size)
    @data = DATA.first(data_size)
    @value = 0
  end

  def add(index)
    100.times do |i|
      @value += @data[(index + i) % @data.size]
      @value %= BIG_PRIME
    end
  end
end

def test_reduce(test_n = 100) # rubocop:disable Metrics/AbcSize
  Benchmark.bm do |x|
    x.report(test_n.to_s) { test_n.times.each_with_object(Accumulator.new(100)) { |i, acc| acc.add(i); } }
    test_n *= 10
    x.report(test_n.to_s) { test_n.times.each_with_object(Accumulator.new(1000)) { |i, acc| acc.add(i); } }
    test_n *= 10
    x.report(test_n.to_s) { test_n.times.each_with_object(Accumulator.new(10_000)) { |i, acc| acc.add(i); } }
  end
end

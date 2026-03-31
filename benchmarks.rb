require 'benchmark'
require 'prime'
require 'pp'

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

def print_zjit_stats(stats) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
  # filter for stats members that are not zero
  stats.each do |key, value|
    next if value.zero?
    next if key.start_with?('ccall_') && value < 1000
    next if key.start_with?('not_annotated_cfuncs_') && value < 1000
    next if key.start_with?('not_inlined_cfuncs_') && value < 1000

    puts "  #{key}: #{value}"
  end
end

def test_reduce(test_n = 100) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/MethodLength,Metrics/PerceivedComplexity
  zjit_stats = []
  Benchmark.bm do |x|
    RubyVM::ZJIT.reset_stats! if RubyVM::ZJIT.stats_enabled?
    x.report(test_n.to_s) { test_n.times.each_with_object(Accumulator.new(100)) { |i, acc| acc.add(i); } }
    if RubyVM::ZJIT.stats_enabled?
      zjit_stats << RubyVM::ZJIT.stats.freeze
      RubyVM::ZJIT.reset_stats!
    end
    test_n *= 10
    x.report(test_n.to_s) { test_n.times.each_with_object(Accumulator.new(1000)) { |i, acc| acc.add(i); } }
    if RubyVM::ZJIT.stats_enabled?
      zjit_stats << RubyVM::ZJIT.stats.freeze
      RubyVM::ZJIT.reset_stats!
    end
    test_n *= 10
    x.report(test_n.to_s) { test_n.times.each_with_object(Accumulator.new(10_000)) { |i, acc| acc.add(i); } }
    if RubyVM::ZJIT.stats_enabled?
      zjit_stats << RubyVM::ZJIT.stats.freeze
      RubyVM::ZJIT.reset_stats!
    end
  end
  zjit_stats.each_with_index do |stats, index|
    puts "ZJIT stats for test #{index + 1}:"
    print_zjit_stats(stats)
  end
end

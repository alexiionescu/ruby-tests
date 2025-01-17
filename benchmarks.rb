require 'benchmark'
# rubocop:disable Metrics/AbcSize

def test_reduce(test_n = 100)
  Benchmark.bm do |x|
    x.report(test_n.to_s) { test_n.times.reduce(0) { |sum, i| sum + i } }
    test_n *= 10
    x.report(test_n.to_s) { test_n.times.reduce(0) { |sum, i| sum + i } }
    test_n *= 10
    x.report(test_n.to_s) { test_n.times.reduce(0) { |sum, i| sum + i } }
  end
end

# rubocop:enable Metrics/AbcSize

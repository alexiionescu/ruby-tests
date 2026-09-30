#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'yaml'
require 'erb'
require 'optparse'

REPEAT_TEST = 'REPEAT'.freeze
NEXT_TEST = 'NEXT'.freeze
FIRST_TEST = 'FIRST'.freeze

options = {}

OptionParser.new do |opt|
  opt.on('-s', '--server=SERVER', 'Server Address') { |o| options[:server_address] = o }
  opt.on('-f', '--file=FILE', 'YAML file with tests') { |o| options[:file] = o }
end.parse!

# Class responsible for processing and executing tests defined in a YAML file.
class TestProcessor
  attr_accessor :repeat_count, :interrupted

  def initialize
    @repeat_count = nil
    @interrupted = false
  end
  # repeat_count is now an instance variable

  def process_countdown(test)
    return false unless test.fetch(:enabled, true)

    log = "#{Time.now.strftime '%H:%M:%S.%L'} Test: #{test[:name]}."
    log += " Repeat count: #{@repeat_count}" unless @repeat_count.nil?
    if test[:countdown]
      test[:countdown] -= 1
      log += " Countdown: #{test[:countdown]}"
      log += '. EXIT' if test[:countdown].zero?
      puts log
      test[:countdown].zero?
    else
      puts log
      false
    end
  end

  def process_test(test)
    return test.fetch(:next, NEXT_TEST) unless test.fetch(:enabled, true)
    return if process_countdown(test)

    http, uri, next_test = prepare_test(test)
    return next_test unless http && uri

    send_test_request(test, http, uri)
    next_test
  end

  def send_test_request(test, http, uri)
    http.use_ssl = (uri.scheme == 'https')
    case test[:request][:method]
    when 'POST'
      request = Net::HTTP::Post.new(uri.path, { 'Content-Type' => 'application/json' })
      send_request(test, http, request)
    when 'PUT'
      request = Net::HTTP::Put.new(uri.path, { 'Content-Type' => 'application/json' })
      send_request(test, http, request)
    end
  end

  def process_repeat(test)
    return test.fetch(:next, NEXT_TEST) unless test[:repeat]&.positive?

    @repeat_count = test[:repeat] if @repeat_count.nil?
    @repeat_count -= 1
    if @repeat_count.positive?
      REPEAT_TEST
    else
      @repeat_count = nil
      test.fetch(:next, NEXT_TEST)
    end
  end

  def wait_handle_interrupt(time)
    sleep(time)
  rescue Interrupt
    puts "\n*** Interrupted while waiting."
    @interrupted = true
  end

  def prepare_test(test)
    time = parse_wait_time(test[:wait])
    if time.positive?
      puts "Waiting for #{test[:wait]} (#{time} s) ..."
      wait_handle_interrupt(time)
    end
    return [nil, nil, process_repeat(test)] unless test[:request]

    uri = URI(test[:request][:url])
    http = Net::HTTP.new(uri.host, uri.port)
    [http, uri, process_repeat(test)]
  end

  # format of wait is 30 seconds/ 1 minute/ 2 minutes etc.
  # convert the wait time to seconds if necessary (e.g., "1 minute" -> 60 seconds)
  def parse_wait_time(wait_str)
    return 0 unless wait_str.is_a?(String)

    time, unit = wait_str.split
    time = time.to_i
    calculate_seconds(time, unit)
  end

  def calculate_seconds(time, unit)
    case unit.strip.downcase
    when 'minute', 'minutes'
      time * 60
    when 'hour', 'hours'
      time * 3600
    else
      time
    end
  end

  def send_request(test, http, request)
    request.body = test[:request][:body].to_json
    # puts "\tDEBUG body: #{request.body}"
    response = http.request(request)
    puts "#{Time.now.strftime '%H:%M:%S.%L'} Response: #{response.code}"
  end
end

processor = TestProcessor.new

erb_res = ERB.new(File.read(options[:file])).result
return unless erb_res

tests = YAML.safe_load(erb_res, symbolize_names: true).fetch(:tests)
return unless tests

test = tests.first
test_index = 0
loop do
  break unless test

  # puts "\tDEBUG: Next test index: #{test_index}: #{test[:name]} (allow_interrupt: #{test[:allow_interrupt]})"

  next_test = processor.process_test(test)
  break if next_test == NEXT_TEST && test_index >= tests.size - 1
  break if test[:countdown]&.zero?

  if processor.interrupted && test[:allow_interrupt] == true
    puts "Exiting due to previous interrupt request at test index #{test_index}: #{test[:name]}"
    break
  end

  # puts "\tDEBUG: Moving to next test '#{next_test}'"

  next unless next_test != REPEAT_TEST

  test = if next_test == NEXT_TEST
           test_index += 1
           tests[test_index]
         elsif next_test == FIRST_TEST
           test_index = 0
           tests.first
         else
           test_index = tests.find_index { |t| t[:name] == next_test }
           tests[test_index]
         end
end

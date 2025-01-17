require 'net/http'
require 'optparse'
require 'yaml'
require 'dotenv'
require 'erb'
require 'digest'
require 'json'
require 'jsonpath'
require 'table_print'
Dotenv.load

options = {
  file: 'http_test.yml'
}

OptionParser.new do |opt|
  opt.on('-f', '--file=FILE', 'YAML file with tests') { |o| options[:file] = o }
end.parse!

if ENV['DCC_PASSWORD'].nil?
  puts "DCC_PASSWORD env variable not found. Enter password for #{ENV['DCC_USER']}:"
  password = gets.chomp
else
  password = ENV['DCC_PASSWORD']
end

params = {
  dcc_user: ENV['DCC_USER'],
  dcc_password: Digest::MD5.hexdigest(password),
  admin_api_host: ENV['ADMIN_API_HOST']
}

def decode_vars(test, response, params)
  vars = test.dig(:response, :vars)
  vars&.each do |k, v|
    jsonpath = JsonPath.new(v)
    params[k] = jsonpath.on(response.body).first
    puts "VARS #{k} = #{params[k]}" unless test.dig(:response, :disable_output)
  end
end

def process_response(test, response, params)
  puts "DEBUG Response Body => #{response.body}" if test[:debug]
  decode_vars(test, response, params)
end

def verify_exit(test)
  return unless test.dig(:response, :exit)

  puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: Exiting because exit flag was set"
  exit
end

def verify_api_error(test, response)
  api_error = test.dig(:response, :api_error)
  return false unless api_error

  jsonpath = JsonPath.new(api_error)
  api_error_res = jsonpath.on(response.body).first
  return false unless api_error_res

  puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: API ERROR: #{api_error_res}" unless test.dig(:response,
                                                                                                        :disable_output)
  verify_exit(test)
  true
end

reload_idx = -1
all_stats = []
at_exit do
  unless all_stats.empty?
    puts "\n----- Session Stats ---- \n"
    tp all_stats
  end
end
# rubocop:disable Metrics/BlockLength
loop do
  erb_res = ERB.new(File.read(options[:file])).result
  test_idx = 0
  YAML.safe_load(erb_res, symbolize_names: true).fetch(:tests).each do |test|
    test_idx += 1
    puts "#{test[:name]}: DEBUG skip" if test[:debug]
    next if test_idx <= reload_idx

    reload_idx = -1

    method = test[:request].fetch(:method, 'post')&.downcase
    unless Net::HTTP.respond_to?(method)
      puts "#{test[:name]}: ERROR http method #{method}"
      next
    end

    session_url = test[:request][:session_url]
    if session_url
      iters = test.fetch(:iter, 1)
      sleep_after = test.fetch(:sleep_after, 0)
      uri = URI(session_url)
      puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: Session Start"
      stats = { 'name' => test[:name], 'http errors' => 0, 'api errors' => 0, 'success' => 0 }
      Net::HTTP.start(uri.hostname, uri.port, { use_ssl: uri.scheme == 'https' }) do |http|
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        iters.times do
          response = http.send(method, test[:request][:path], test[:request][:body].to_json,
                               'Content-Type' => 'application/json')
          if response.code != '200'
            stats['http errors'] += 1
            unless test.dig(:response, :disable_output)
              puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: HTTP ERROR: #{response.code} #{response.body}"
            end
          elsif verify_api_error(test, response)
            stats['api errors'] += 1
          else
            stats['success'] += 1
            puts "DEBUG Response Body => #{response.body}" if test[:debug]
            puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: OK" unless test.dig(:response, :disable_output)
          end
          sleep sleep_after
        end
        stop_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        stats['duration (s)'] = format('%.3f', (stop_time - start_time) / 1_000_000_000.0)
        stats['rps'] = iters * 1_000_000_000 / (stop_time - start_time)
        all_stats << stats
      end
    else
      uri = URI(test[:request][:url])
      puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: DEBUG URL => #{uri}" if test[:debug]
      puts "DEBUG Body => #{test[:request][:body]}" if test[:debug]

      response = Net::HTTP.send(method, uri, test[:request][:body].to_json, 'Content-Type' => 'application/json')
      if response.code != '200'
        puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: HTTP ERROR: #{response.code} #{response.body}"
        verify_exit(test)
        next
      end

      next if verify_api_error(test, response)

      puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: OK" unless test.dig(:response, :disable_output)
      process_response(test, response, params)
      verify_exit(test)
      next unless test.dig(:response, :reload_erb)

      reload_idx = test_idx
      puts "#{Time.now.strftime '%H:%M:%S.%L'} #{test[:name]}: Reload ERB ..."
      p params if test[:debug]

      break
    end
  end
  sleep 1
rescue Interrupt
  puts 'Exiting because Ctrl-C was pressed'
  break
end

# rubocop:enable Metrics/BlockLength

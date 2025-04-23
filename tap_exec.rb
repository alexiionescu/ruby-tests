#!/usr/bin/env ruby

require 'optparse'
require 'socket'

options = {
  repeat: 1,
  repeat_pause: 0,
  steps: 1,
  devs: [],
  seq: []
}

OptionParser.new do |opt|
  opt.on('-t', '--template=TEMPLATE', 'template file: tap_TEMPLATE_alarm/clear.txt') { |o| options[:template] = o }
  opt.on('-d', '--alarm-pause=DURATION', Float, 'after alarm pause in seconds') { |o| options[:a_pause] = o }
  opt.on('-i', '--clear-pause=DURATION', Float, 'after clear pause in seconds') { |o| options[:c_pause] = o }
  opt.on('-s', '--start-dev=DEV', Integer, 'device number to start') { |o| options[:s_dev] = o }
  opt.on('-e', '--end-dev=DEV', Integer, 'device number to end') { |o| options[:e_dev] = o }
  opt.on('-r', '--repeat=CNT', Integer, 'repeat sequence count') { |o| options[:repeat] = o }
  opt.on('-P', '--repeat-pause=CNT', Integer, 'repeat sequence count') { |o| options[:repeat_pause] = o }
  opt.on('--steps=CNT', Integer, 'steps repeat count') { |o| options[:steps] = o }
  opt.on('-a', 'generate alarms from tap_TEMPLATE_alarm.txt') { |o| options[:alarm] = o }
  opt.on('-c', 'generate clears from tap_TEMPLATE_clear.txt') { |o| options[:clear] = o }
  opt.on('--devs=DEV', Array, 'devices list') { |o| options[:devs] = o.map(&:strip) }
  opt.on('--seq=SEQUENCE', 'sequence of alarm,clear or wait: (a|c):dev|w:<seconds> (e.g. a:101 w:5.5 c:101)') do |o|
    options[:sequence] = o
  end
  opt.on('--seq-file=FILE', 'FILE with sequence of steps') { |o| options[:sequence_file] = o }
  opt.on('-h', '--host=HOST', 'destination ip/host') { |o| options[:host] = o }
  opt.on('-p', '--port=PORT', 'destination port') { |o| options[:port] = o }
  opt.on('--page=PAGE', '<PAGE> to replace in template files, default "Button"') { |o| options[:page] = o }
  opt.on('-v', 'verbose mode') { |o| options[:verbose] = o }
  # opt.on('--protocol=PROTO', 'Protocol: UDP, default is UDP') { |o| options[:proto] = o }
end.parse!

required_options = %i[template host port] # same as [:template,:host,:port]
missing_options = required_options - options.keys
raise "Missing required options: #{missing_options}" unless missing_options.empty?

if options[:devs].empty?
  if options[:s_dev] && options[:e_dev]
    options[:devs] = (options[:s_dev]..options[:e_dev]).to_a.map(&:to_s)
  else
    options[:devs] << '101'
  end
end
if options[:sequence_file]
  options[:seq] = File.readlines(options[:sequence_file]).map(&:split).flatten
else
  options[:seq] = options[:sequence].split(' ') unless options[:sequence].nil?
end

a_lines = []
File.readlines("files/tap_#{options[:template]}_alarm.txt").each do |line|
  a_lines.push(line.strip)
end
puts ">>> Alarm Lines: #{a_lines}" if options[:verbose]
c_lines = []
File.readlines("files/tap_#{options[:template]}_clear.txt").each do |line|
  c_lines.push(line.strip)
end
puts ">>> Clear Lines: #{c_lines}" if options[:verbose]

options[:seq] << 'a:<DEV>' if options[:alarm]
options[:seq] << "w:#{options[:a_pause]}" if options[:a_pause]
options[:seq] << 'c:<DEV>' if options[:clear]
options[:seq] << "w:#{options[:c_pause]}" if options[:c_pause]

puts ">>> Devs: #{options[:devs]}" if options[:verbose]
puts ">>> Sequence: #{options[:seq]}" if options[:verbose]

udp_socket = UDPSocket.new
def send_lines(udp_socket, lines, dev, options)
  msg = ''
  lines.each do |line|
    msg << "#{line.sub('<DEV>', dev).sub('<PAGE>', options.fetch(:page, 'Button'))}\r"
  end
  puts "#{Time.now.strftime '%H:%M:%S.%L'} >> #{msg}"
  udp_socket.send(msg, 0)
end

def send_seq(udp_socket, lines, seq_data, options)
  seq_data_s, seq_data_e = seq_data.split('-').map(&:to_i) if seq_data
  if seq_data_e
    (seq_data_s..seq_data_e).each do |dev|
      send_lines(udp_socket, lines, dev.to_s, options)
    end
  else
    send_lines(udp_socket, lines, seq_data, options)
  end
end

rng = Random.new
udp_socket.connect(options[:host], options[:port])
options[:repeat].times do |idx| # rubocop:disable Metrics/BlockLength
  unless options[:seq].empty?
    options[:devs].each do |dev|
      options[:steps].times do |step|
        puts "--- Seq Iter #{idx + 1} Dev '#{dev}' Step #{step + 1} ---"
        options[:seq].each do |seq|
          seq_type, seq_data = seq.split(':')
          break unless seq_data

          seq_data.gsub!('<DEV>', dev)
          puts ">>> Seq: #{seq_type} #{seq_data}" if options[:verbose]
          case seq_type
          when 'a'
            send_seq(udp_socket, a_lines, seq_data, options)
          when 'c'
            send_seq(udp_socket, c_lines, seq_data, options)
          when 'w'
            seq_data_s, seq_data_e = seq_data.split('-').map(&:to_f) if seq_data
            if seq_data_e
              wait = rng.rand(seq_data_s...seq_data_e)
              puts ">>> Wait #{seq_data} -> #{wait} seconds" if options[:verbose]
              sleep wait
            else
              puts ">>> Wait #{seq_data} seconds" if options[:verbose]
              sleep seq_data.to_f
            end
          end
        end
      end
    end
  end
  sleep options[:repeat_pause]
rescue Interrupt
  puts 'Interrupted. Exiting...'
  break
end

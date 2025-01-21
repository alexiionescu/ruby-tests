#!/usr/bin/env ruby

require 'optparse'
require 'socket'

options = {
  a_pause: 0.5,
  c_pause: 0.5,
  repeat: 1,
  steps: 1
}

OptionParser.new do |opt|
  opt.on('-t', '--template=TEMPLATE', 'template file: tap_TEMPLATE_alarm/clear.txt') { |o| options[:template] = o }
  opt.on('-d', '--alarm-pause=DURATION', Float, 'after alarm pause in seconds') { |o| options[:a_pause] = o }
  opt.on('-i', '--clear-pause=DURATION', Float, 'after clear pause in seconds') { |o| options[:c_pause] = o }
  opt.on('-s', '--start-dev=DEV', Integer, 'device number to start') { |o| options[:s_dev] = o }
  opt.on('-e', '--end-dev=DEV', Integer, 'device number to end') { |o| options[:e_dev] = o }
  opt.on('-r', '--repeat=CNT', Integer, 'repeat sequence count') { |o| options[:repeat] = o }
  opt.on('--steps=CNT', Integer, 'steps repeat count') { |o| options[:steps] = o }
  opt.on('--devs=DEV', Array, 'devices list') { |o| options[:devs] = o }
  opt.on('-a', 'generate alarms from tap_TEMPLATE_alarm.txt') { |o| options[:alarm] = o }
  opt.on('-c', 'generate clears from tap_TEMPLATE_clear.txt') { |o| options[:clear] = o }
  opt.on('-h', '--host=HOST', 'destination ip/host') { |o| options[:host] = o }
  opt.on('-p', '--port=PORT', 'destination port') { |o| options[:port] = o }
  opt.on('--page=PAGE', '<PAGE> to replace in template files, default "Button"') { |o| options[:page] = o }
  # opt.on('--protocol=PROTO', 'Protocol: UDP, default is UDP') { |o| options[:proto] = o }
end.parse!

required_options = %i[template host port] # same as [:template,:host,:port]
missing_options = required_options - options.keys
raise "Missing required options: #{missing_options}" unless missing_options.empty?
raise 'One of -a or -c is required' unless options[:alarm] || options[:clear]

unless options[:devs]
  raise '--devs or -s/--start-dev and -e/--end-dev is required' unless options[:s_dev] && options[:e_dev]

  options[:devs] = (options[:s_dev]..options[:e_dev]).to_a.map(&:to_s)

end

a_lines = []
if options[:alarm]
  File.readlines("files/tap_#{options[:template]}_alarm.txt").each do |line|
    a_lines.push(line.strip)
  end
end
c_lines = []
if options[:clear]
  File.readlines("files/tap_#{options[:template]}_clear.txt").each do |line|
    c_lines.push(line.strip)
  end
end

udp_socket = UDPSocket.new
def send_line(udp_socket, line, dev, options)
  msg = "#{line.sub('<DEV>', dev).sub('<PAGE>', options.fetch(:page, 'Button'))}\r"
  puts "#{Time.now.strftime '%H:%M:%S.%L'} >> #{msg}"
  udp_socket.send(msg, 0)
end

udp_socket.connect(options[:host], options[:port])
options[:repeat].times do
  options[:devs].each do |dev|
    options[:steps].times do
      a_lines.each do |line|
        send_line(udp_socket, line, dev, options)
      end
      sleep options[:a_pause] unless a_lines.empty?
      c_lines.each do |line|
        send_line(udp_socket, line, dev, options)
      end
      sleep options[:c_pause] unless c_lines.empty?
    end
  end
end

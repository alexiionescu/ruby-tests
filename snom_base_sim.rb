#!/usr/bin/env ruby

require 'optparse'
require 'nokogiri'
require 'socket'
require 'timeout'

options = {
  port: 1300,
  c_pause: 0.5,
  repeat: 1,
  repeat_pause: 0,
  steps: 1
}

OptionParser.new do |opt|
  opt.on('-s', '--start-dev=DEV', Integer, 'device number to start') { |o| options[:s_dev] = o }
  opt.on('-e', '--end-dev=DEV', Integer, 'device number to end') { |o| options[:e_dev] = o }
  opt.on('--devs=DEV', Array, 'devices list') { |o| options[:devs] = o }
  opt.on('-h', '--host=HOST', 'destination ip/host') { |o| options[:host] = o }
  opt.on('-p', '--port=PORT', 'destination port') { |o| options[:port] = o }
end.parse!

required_options = %i[host]
missing_options = required_options - options.keys
raise "Missing required options: #{missing_options}" unless missing_options.empty?

unless options[:devs]
  raise '--devs or -s/--start-dev and -e/--end-dev is required' unless options[:s_dev] && options[:e_dev]

  options[:devs] = (options[:s_dev]..options[:e_dev]).to_a.map(&:to_s)

end

udp_socket = UDPSocket.new
udp_socket.connect(options[:host], options[:port])

STATUS_INITIATED = 0
STATUS_RUNNING = 1
STATUS_DELIVERED = 1
STATUS_BUSY = 2
STATUS_ERROR = 3
STATUS_ACCEPTED = 4
STATUS_REJECTED = 5
STATUS_CANCELLED = 10
STATUS_NOT_REACHABLE = 11

def prepare_systemdata(xml)
  xml.systemdata do
    xml.name 'SME VoIP'
    xml.datetime Time.now.strftime('%Y-%m-%d %H:%M:%S')
    xml.status STATUS_RUNNING
    xml.timestamp Time.now.strftime('%x')
    xml.statusinfo 'System running'
  end
end

def prepare_sender_data(xml, devs)
  xml.senderdata do
    devs.each do |dev|
      xml.address dev
      xml.name "Snom #{dev}"
    end
  end
end

def prepare_request(options)
  Nokogiri::XML::Builder.new do |xml|
    xml.request(version: '24.0.1.1999', type: 'systeminfo') do
      xml.externalid Time.now.to_i
      prepare_systemdata(xml)
      prepare_sender_data(xml, options[:devs])
    end
  end
end

def prepare_response(dst, eid, status)
  Nokogiri::XML::Builder.new do |xml|
    xml.response(version: '24.0.1.1999', type: 'job') do
      xml.externalid eid
      xml.status status
      prepare_systemdata(xml)
      prepare_sender_data(xml, [dst])
    end
  end
end

def prepare_job_data(xml, status)
  xml.jobdata do
    xml.status status
    xml.statusinfo
    xml.priority 1
    xml.messages do
      xml.message1
      xml.message2
      xml.messageuui
    end
  end
end

def prepare_job_response(dst, eid, status)
  Nokogiri::XML::Builder.new do |xml|
    xml.response(version: '24.0.1.1999', type: 'job') do
      xml.externalid eid
      prepare_systemdata(xml)
      prepare_job_data(xml, status)
      prepare_sender_data(xml, [dst])
    end
  end
end

def process_request(xml, udp_socket) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
  status = xml.xpath('//request//jobdata//status').map(&:text)
  dst = xml.xpath('//request//persondata//address').map(&:text)
  eid = xml.xpath('//request//externalid').map(&:text)
  sid = xml.xpath('//request//jobdata//referencenumber').map(&:text)
  msg_text = xml.xpath('//request//jobdata//messages//messageuui').map(&:text)
  return if msg_text.empty? || sid.empty? || eid.empty? || dst.empty?

  s = status[0].to_i
  if s == STATUS_INITIATED
    puts "#{Time.now.strftime '%H:%M:%S.%L'} #{dst[0]}\tEid:#{eid[0]}\tSid:#{sid[0]}\tShow #{msg_text[0]}"
  elsif s == STATUS_CANCELLED
    puts "#{Time.now.strftime '%H:%M:%S.%L'} #{dst[0]}\tEid:#{eid[0]}\tSid:#{sid[0]}\t Remove #{msg_text[0]}"
  end
  response = prepare_response(dst[0], eid[0], STATUS_DELIVERED)
  udp_socket.send(response.to_xml, 0)
  sleep 0.6
  response = prepare_job_response(dst[0], eid[0], STATUS_DELIVERED)
  udp_socket.send(response.to_xml, 0)
end

send_status = true
loop do
  if send_status
    status_report = prepare_request(options)
    udp_socket.send(status_report.to_xml, 0)
    send_status = false
  end
  Timeout.timeout(60) do
    response, _addr = udp_socket.recvfrom(1024)
    xml_res = Nokogiri::XML response
    request = xml_res.xpath('//request')
    process_request(request[0], udp_socket) unless request.empty?
  end
rescue Timeout::Error
  send_status = true
rescue Interrupt
  puts 'Interrupted. Exiting...'
  break
end

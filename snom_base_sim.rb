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

STATUS_STR = {
  STATUS_INITIATED => 'Show     ',
  STATUS_DELIVERED => 'Delivered',
  STATUS_ACCEPTED => 'Accept   ',
  STATUS_REJECTED => 'Reject   ',
  STATUS_NOT_REACHABLE => 'Unreached',
  STATUS_BUSY => 'Busy     ',
  STATUS_CANCELLED => 'Cleared  '
}.freeze

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

def prepare_status(devs)
  Nokogiri::XML::Builder.new do |xml|
    xml.request(version: '24.0.1.1999', type: 'systeminfo') do
      xml.externalid Time.now.to_i
      prepare_systemdata(xml)
      prepare_sender_data(xml, devs)
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

def time_s
  Time.now.strftime '%H:%M:%S.%L'
end

def process_request(xml, udp_socket, dects) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity,Metrics/MethodLength
  status = xml.xpath('//request//jobdata//status').map(&:text)
  dst = xml.xpath('//request//persondata//address').map(&:text)
  eid = xml.xpath('//request//externalid').map(&:text)
  sid = xml.xpath('//request//jobdata//referencenumber').map(&:text)
  msg_text = xml.xpath('//request//jobdata//messages//messageuui').map(&:text)
  return if msg_text.empty? || sid.empty? || eid.empty? || dst.empty?

  s = status[0].to_i
  sleep 0.2
  if dects.busy?
    res_s = STATUS_BUSY
  else
    res_s = STATUS_DELIVERED
    dects.add_job(JobData.new(dst[0], eid[0], sid[0], s, msg_text[0]))
  end
  response = prepare_response(dst[0], eid[0], res_s)
  udp_socket.send(response.to_xml, 0)
  puts "#{time_s} #{dst[0]} Eid:#{eid[0]} Sid:#{sid[0]} #{STATUS_STR[s]} RS:#{STATUS_STR[s]}\t" + msg_text[0]
end

## JobData class
class JobData
  attr_accessor :dst, :eid, :sid, :time, :text, :req_s

  def initialize(dst, eid, sid, req_s, text)
    @dst = dst
    @eid = eid
    @sid = sid
    @req_s = req_s
    @text = text
    @time = Time.now
  end

  def response(status, duration)
    sleep 0.1 while elapsed < duration
    prepare_job_response(@dst, @eid, status)
  end

  def elapsed
    Time.now - @time
  end
end

## JobProcessing class
# This class is responsible for processing jobs
# - It uses a thread to process jobs in the background
# - It uses a queue to store jobs
# - It uses a set to keep track of active jobs
# - It uses a socket to send responses
# - It uses a timer to check if the job is still active
# - It checks if status need to be sent (60 seconds)
class JobProcessing
  def initialize(socket, devs)
    @job_queue = Thread::Queue.new
    @socket = socket
    @active_jobs = Set.new
    @send_status = nil
    @devs = devs
  end

  def add_job(job)
    @job_queue << job
  end

  def busy?
    @job_queue.size > 1
  end

  # return true if the job was delivered
  def process_job(job)
    status = STATUS_DELIVERED
    @socket.send(job.response(status, 0.8).to_xml, 0)
    puts "#{time_s} #{job.dst} Eid:#{job.eid} Sid:#{job.sid} #{STATUS_STR[job.req_s]} RJ:#{STATUS_STR[status]}" \
         "\t#{job.text}\tElapsed: #{format('%.3f', job.elapsed)}"
    status == STATUS_DELIVERED
  end

  def print_active_jobs
    if @active_jobs.empty?
      puts 'No Active jobs'
    else
      puts "Active jobs #{@active_jobs.join(' ')}"
    end
  end

  def start # rubocop:disable Metrics/MethodLength
    @job_thread = Thread.new do
      loop do
        job = @job_queue.pop
        if process_job(job)
          if job.req_s == STATUS_CANCELLED
            print_active_jobs unless @active_jobs.delete?(job.sid).nil?
          else
            print_active_jobs unless @active_jobs.add?(job.sid).nil?
          end
        end
      end
    end
  end

  def check_send_status
    return unless @send_status.nil? || Time.now - @send_status >= 60

    status_report = prepare_status(@devs)
    @socket.send(status_report.to_xml, 0)
    @send_status = Time.now
    puts "#{time_s} Status sent"
  end
end

dects = JobProcessing.new(udp_socket, options[:devs])
dects.start

loop do
  dects.check_send_status
  Timeout.timeout(60) do
    response, _addr = udp_socket.recvfrom(1024)
    xml_res = Nokogiri::XML response
    request = xml_res.xpath('//request')
    process_request(request[0], udp_socket, dects) unless request.empty?
    dects.check_send_status
  end
rescue Timeout::Error
  # send status if nothing received for 60 seconds
rescue Interrupt
  puts 'Interrupted. Exiting...'
  break
end

#!/usr/bin/env ruby

require 'open3'

puts 'Enter the folder name you want to list files from (Default: Home folder):'
folder = gets.chomp
folder = ENV['HOME'] if folder.empty?

# Dir["#{folder}/*"].each do |file|
#   puts file if File.file?(file)
# end
# Command you want to run
command = "ls #{folder}"

# Run the command and capture the output
stdout, stderr, status = Open3.capture3(command)

# Check if the command was successful
if status.success?
  puts 'Command executed successfully!'
  puts "Output:\n#{stdout}"
else
  puts 'Command failed with error:'
  puts stderr
end

out = `ls #{folder}`
puts "backtick method Output\n#{out.split("\n")}"

#!/usr/bin/env ruby

require 'erb'
require 'optparse'
require 'etc'

LOGIN = Etc.getlogin
# login_info = Etc.getpwnam(LOGIN)
RUBY = File.join(RbConfig::CONFIG['bindir'], RbConfig::CONFIG['ruby_install_name']).sub(/.*\s.*/m, '"\&"')
@options = {
  restart_after: 30,
  restart: 'always',
  user: LOGIN,
  usergr: LOGIN,
  wdir: Dir.getwd,
  ruby: RUBY
}
OptionParser.new do |opt|
  opt.on('-n', '--mame=SERVICE', 'service name') { |o| @options[:name] = o }
  opt.on('-u', '--user=USER', 'running user, default is current user') { |o| @options[:user] = o }
  opt.on('-g', '--user-group=USER_GROUP', 'running user group, default is current user') { |o| @options[:usergr] = o }
  opt.on('-d', '--working-dir=USER_GROUP', 'working directory, default is current dir') { |o| @options[:wdir] = o }
  opt.on('--ruby-path=RUBY_PATH', 'ruby path, default is /usr/bin/ruby') { |o| @options[:wdir] = o }
  opt.on('-r', '--run', 'run systemctl commands') { |o| @options[:run] = o }
end.parse!

required_options = %i[name]
missing_options = required_options - @options.keys
raise "Missing required options: #{missing_options}" unless missing_options.empty?

output = ERB.new(File.read('ruby.service.templ')).result
service_file = "files/#{@options[:name]}.service"
File.write(service_file, output)

if @options[:run]
  system("sudo cp #{service_file} /etc/systemd/system/")
  system('sudo systemctl daemon-reload')
  system("sudo systemctl enable #{@options[:name]}.service")
  system("sudo systemctl start #{@options[:name]}.service")
else
  puts <<~EOUTPUT
    File #{service_file} was written.
    To install service run:
    sudo cp #{service_file} /etc/systemd/system/
    sudo systemctl daemon-reload
    sudo systemctl enable #{@options[:name]}.service
    sudo systemctl start #{@options[:name]}.service
  EOUTPUT
end

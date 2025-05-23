#!/usr/bin/env ruby

require 'optparse'
require 'fileutils'
# puts "running ruby version #{RUBY_VERSION}"
@options = {
  src_dirs: (ENV['SYNC_SRC_DIRS'] || '/').split,
  dst_dirs: (ENV['SYNC_DST_DIRS'] || '/').split,
  glob_patterns: ENV['SYNC_GLOB_PATTERNS'] || []
}
OptionParser.new do |opt|
  opt.on('-s', '--src-base=SRC_BASE', 'source base dir') { |o| @options[:src_base] = o }
  opt.on('-d', '--dst-base=DST_BASE', 'destination base dir') { |o| @options[:dst_base] = o }
  opt.on('--src-dirs=SRC_DIRS', Array, 'source directories') { |o| @options[:src_dirs] = o }
  opt.on('--dst-dirs=DST_DIRS', Array, 'destination directories') { |o| @options[:dst_dirs] = o }
  opt.on('-i', '--include=GLOB_PATTERNS', Array, 'glob patterns to include in each sync') do |o|
    @options[:glob_patterns] = o
  end
  opt.on('-n', '--dry-run', 'dry run, no modifications are made') { |o| @options[:dry_run] = o }
  opt.on('--copy-new', 'copy src to dst if dst does not exist') { |o| @options[:copy_new] = o }
  opt.on('--hg-commit=TEXT', "mercurial commit `hg commit -m 'TEXT' --cwd DIR; hg push --cwd DIR`") do |o|
    @options[:commit] = o
    @options[:ss] = `which hg`.chomp!
    puts 'ERROR: hg not found !!!' unless @options[:ss]
  end
  # opt.on('--git-commit=TEXT', "git commit `git commit -m 'TEXT' --cwd DIR; hg push --cwd DIR`") do |o|
  #   @options[:commit] = o
  #   @options[:ss] = 'git'
  # end
  # git is complicated, requires .git exact dir
  # git --git-dir DIR/.git --work-tree DIR status
end.parse!

required_options = %i[src_base dst_base glob_patterns]
missing_options = required_options - @options.keys
raise "Missing required @options: #{missing_options}" unless missing_options.empty?

raise 'SRC_DIRS and DST_DIRS must have same size' unless @options[:src_dirs].length == @options[:dst_dirs].length
raise 'glob patterns must have a list one element' if @options[:glob_patterns].empty?

if @options[:glob_patterns].length < @options[:src_dirs].length
  (@options[:src_dirs].length - @options[:glob_patterns].length).times do
    @options[:glob_patterns].push @options[:glob_patterns].last
  end
end

@stats = {
  time_modified: 0,
  sync_src_to_dst: 0,
  sync_dst_to_src: 0
}

def sync_file(fname, src_file, dst_file) # rubocop:disable Metrics/AbcSize,Metrics/MethodLength,Metrics/PerceivedComplexity,Metrics/CyclomaticComplexity
  is_dst = File.exist?(dst_file)
  return false unless @options[:copy_new] || is_dst

  if !is_dst || File.mtime(src_file) > (File.mtime(dst_file))
    if is_dst && FileUtils.identical?(src_file, dst_file)
      File.utime(File.mtime(src_file), File.mtime(src_file), dst_file) unless @options[:dry_run]
      @stats[:time_modified] += 1
    else
      if is_dst
        puts "#{fname}: #{File.mtime(src_file)} > #{File.mtime(dst_file)}"
      else
        puts "#{fname}: copy new"
      end
      @stats[:sync_src_to_dst] += 1
      FileUtils.cp(src_file, dst_file) unless @options[:dry_run]
      return true
    end
  elsif File.mtime(src_file) < File.mtime(dst_file)
    if FileUtils.identical?(src_file, dst_file)
      File.utime(File.mtime(dst_file), File.mtime(dst_file), src_file) unless @options[:dry_run]
      @stats[:time_modified] += 1
    else
      puts "#{fname}: #{File.mtime(src_file)} < #{File.mtime(dst_file)}"
      FileUtils.cp(dst_file, src_file) unless @options[:dry_run]
      @stats[:sync_dst_to_src] += 1
    end
  end
  false
end

dirs = Set.new
@options[:src_dirs].each_with_index do |src_dir, idx|
  base_src_folder = File.join(@options[:src_base], src_dir)
  base_dst_folder = File.join(@options[:dst_base], @options[:dst_dirs][idx])
  if @options[:dry_run]
    puts "DRY-RUN: #{@options[:glob_patterns][idx]} : #{base_src_folder} -> #{base_dst_folder}"
  else
    puts "SYNC: #{@options[:glob_patterns][idx]} : #{base_src_folder} -> #{base_dst_folder}"
  end
  Dir.glob(@options[:glob_patterns][idx], base: base_src_folder) do |fname|
    src_file = File.join(base_src_folder, fname)
    dst_file = File.join(base_dst_folder, fname)
    dirs << base_dst_folder if sync_file(fname, src_file, dst_file)
  end
end

puts "#{@options[:dry_run] ? 'DRY-RUN' : 'SYNC'} content src to dst: #{@stats[:sync_src_to_dst]}"
puts "#{@options[:dry_run] ? 'DRY-RUN' : 'SYNC'} content dst to src: #{@stats[:sync_dst_to_src]}"
puts "#{@options[:dry_run] ? 'DRY-RUN' : 'SYNC'} time: #{@stats[:time_modified]}"
if @options[:ss] && @options[:commit] && !dirs.empty?
  dirs.each do |dir|
    commit_cmd = "#{@options[:ss]} --cwd '#{dir}' commit -m '#{@options[:commit]}'"
    push_cmd = "#{@options[:ss]} --cwd '#{dir}' push"
    if @options[:dry_run]
      puts commit_cmd
      puts push_cmd
    else
      system(commit_cmd)
      system(push_cmd)
    end
  end
end

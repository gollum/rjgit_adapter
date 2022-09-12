require 'rubygems'
 
task :default => :rspec

require 'rspec/core/rake_task'

def name
  "rjgit_adapter"
end

def version
  line = File.read("lib/rjgit_adapter/version.rb")[/^\s*VERSION\s*=\s*.*/]
  line.match(/.*VERSION\s*=\s*['"](.*)['"]/)[1]
end

# assumes x.y.z all digit version
def next_version
  # x.y.z
  v = version.split '.'
  # bump z
  v[-1] = v[-1].to_i + 1
  v.join '.'
end

def bump_version
  old_file = File.read("lib/rjgit_adapter/version.rb")
  old_version_line = old_file[/^\s*VERSION\s*=\s*.*/]
  new_version = next_version
  # replace first match of old version with new version
  old_file.sub!(old_version_line, "    VERSION = '#{new_version}'")

  File.write("lib/rjgit_adapter/version.rb", old_file)

  new_version
end

def date
  Date.today.to_s
end

def gemspec
  "gollum-rjgit_adapter.gemspec"
end

def gem_file
  "gollum-#{name}-#{version}-java.gem"
end

def replace_header(head, header_name)
  head.sub!(/(\.#{header_name}\s*= ').*'/) { "#{$1}#{send(header_name)}'"}
end

desc "Run specs."
RSpec::Core::RakeTask.new(:rspec) do |spec|
  ruby_opts = "-w"
  spec.pattern = 'spec/**/*_spec.rb'
  spec.rspec_opts = ['--backtrace --color']
end

desc "Update version number and gemspec"
task :bump do
  puts "Updated version to #{bump_version}"
  # Execute does not invoke dependencies.
  # Manually invoke gemspec then validate.
  Rake::Task[:gemspec].execute
  Rake::Task[:validate].execute
end

desc 'Create a release build'
task :release => :build do
  unless `git branch` =~ /^\* master$/
    puts "You must be on the master branch to release!"
    exit!
  end
  sh "git commit --allow-empty -a -m 'Release #{version}'"
  sh "git pull --rebase origin master"
  sh "git tag v#{version}"
  sh "git push origin master"
  sh "git push origin v#{version}"
  sh "gem push pkg/#{gem_file}"
end

desc 'Publish to rubygems. Same as release'
task :publish => :release

desc 'Build gem'
task :build => :gemspec do
  sh "mkdir -p pkg"
   sh "gem build #{gemspec}"
   sh "mv #{gem_file} pkg"
end

desc 'Update gemspec'
task :gemspec => :validate do
  # read spec file and split out manifest section
  spec = File.read(gemspec)
  head, manifest, tail = spec.split("  # = MANIFEST =\n")

  # replace name version and date
  replace_header(head, :name)
  replace_header(head, :date)

  # determine file list from git ls-files
  files = `git ls-files`.
    split("\n").
    sort.
    reject { |file| file =~ /^\./ }.
    reject { |file| file =~ /^(rdoc|pkg|spec|\.gitattributes|Guardfile)/ }.
    map { |file| "    #{file}" }.
    join("\n")

  # piece file back together and write
  manifest = "  s.files = %w(\n#{files}\n  )\n"
  spec = [head, manifest, tail].join("  # = MANIFEST =\n")
  File.open(gemspec, 'w') { |io| io.write(spec) }
  puts "Updated #{gemspec}"
end

desc 'Validate lib files and version file'
task :validate do
  libfiles = Dir['lib/*'] - ["lib/#{name}.rb", "lib/#{name}"]
  unless libfiles.empty?
    puts "Directory `lib` should only contain a `#{name}.rb` file and `#{name}` dir."
    exit!
  end
end

# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "jira-omnifocus"
  spec.version       = '0.2'
  spec.authors       = ["fairchild", 'devondragon']
  spec.email         = ["fairchild.michael@gmail.com"]
  spec.summary       = %q{Sync jira issues to omnifocus.}
  spec.description   = %q{pulls back all unresolved Jira tickets that are assigned to you and if it hasn't already created a OmniFocus task for that ticket, it creates a new one.}
  spec.homepage      = "https://github.com/fairchild/jira-omnifocus"
  spec.license       = "Apache"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"

  spec.add_runtime_dependency 'hashie', '~>3.3'
  spec.add_runtime_dependency 'highline', '~>1.6'
  spec.add_runtime_dependency 'jira-ruby', '~>0.1.11'
  spec.add_runtime_dependency 'json', '~>1.8'
  spec.add_runtime_dependency 'rb-appscript', '~>0.6.1'
  spec.add_runtime_dependency 'trollop', '~>2.0'

end

  # * activesupport (4.1.5)
  # * bundler (1.7.2)
  # * coderay (1.1.0)
  # * hashie (3.3.1)
  # * highline (1.6.21)
  # * i18n (0.6.11)
  # * jira-ruby (0.1.11 672f06b)
  # * json (1.8.1)
  # * method_source (0.8.2)
  # * minitest (5.4.0)
  # * oauth (0.4.7)
  # * pry (0.10.1)
  # * rb-appscript (0.6.1)
  # * slop (3.6.0)
  # * thread_safe (0.3.4)
  # * trollop (2.0)

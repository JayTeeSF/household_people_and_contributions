# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)
require "household_people_and_contributions/version"

Gem::Specification.new do |s|
  s.name        = "household_people_and_contributions"
  s.version     = HouseholdPeopleAndContributions::VERSION
  s.authors     = ["Jay Tee"]
  s.email       = ["jaytee@jayteesf.com"]
  s.homepage    = ""
  s.summary     = %q{Extract GSP Data from Fellowshipone}
  s.description = %q{Extract GSP Data from Fellowshipone}

  s.rubyforge_project = "household_people_and_contributions"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  s.add_development_dependency 'rspec'

  # specify any dependencies here; for example:
  # s.add_runtime_dependency "rest-client"
  s.add_runtime_dependency 'f1api'
  s.add_runtime_dependency 'fellowshipone-api' #, require: 'fellowshipone'
end

# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

require "rubocop/rake_task"

RuboCop::RakeTask.new

task default: %i[test rubocop]

Rake::TestTask.new do |task|
  task.libs << "test"
  task.pattern = "test/test_all.rb"
end

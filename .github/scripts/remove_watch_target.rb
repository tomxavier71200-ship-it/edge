# The sideload and simulator artifacts intentionally exclude the Watch app.
# Remove its target before Xcode resolves signing: an unsigned Watch target
# still requires a Development Team even when the enclosing iPhone build uses
# --no-codesign.
require 'xcodeproj'

project_path = ARGV.fetch(0, 'ios/Runner.xcodeproj')
watch_name = 'OpenStrapWatch Watch App'
project = Xcodeproj::Project.open(project_path)

runner = project.targets.find { |target| target.name == 'Runner' }
watch = project.targets.find { |target| target.name == watch_name }
abort 'Runner target not found' unless runner
abort "#{watch_name} target not found" unless watch

dependencies = runner.dependencies.select { |dependency| dependency.target == watch }
embed_phases = runner.build_phases.select do |phase|
  phase.respond_to?(:name) && phase.name == 'Embed Watch Content'
end

abort "Expected one Watch dependency, found #{dependencies.length}" unless dependencies.one?
abort "Expected one Watch embed phase, found #{embed_phases.length}" unless embed_phases.one?

dependencies.each(&:remove_from_project)
embed_phases.each(&:remove_from_project)
watch.remove_from_project
project.save

reopened = Xcodeproj::Project.open(project_path)
abort 'Watch target remains after save' if reopened.targets.any? { |target| target.name == watch_name }

saved_runner = reopened.targets.find { |target| target.name == 'Runner' }
abort 'Runner target missing after save' unless saved_runner
if saved_runner.build_phases.any? { |phase| phase.respond_to?(:name) && phase.name == 'Embed Watch Content' }
  abort 'Watch embed phase remains after save'
end

puts 'Removed Watch target from this CI checkout.'

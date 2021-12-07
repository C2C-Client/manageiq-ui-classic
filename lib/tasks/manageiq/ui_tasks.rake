namespace :update do
  task :yarn do
    asset_engines.each do |engine|
      Dir.chdir engine.path do
        next unless File.file? 'package.json'

        if ENV['TEST_SUITE'] == 'spec'
          warn "Skipping yarn install for #{engine.name} on travis #{ENV['TEST_SUITE']}"
          next
        end
        system("yarn") || abort("\n== yarn failed in #{engine.path} ==")
      end
    end
  end

  task :clean do
    # clean up old bower packages
    # FIXME: remove 2018-11 or so, hammer/no
    FileUtils.rm_rf(ManageIQ::UI::Classic::Engine.root.join('vendor', 'assets', 'bower_components'))
    FileUtils.rm_rf(ManageIQ::UI::Classic::Engine.root.join('vendor', 'assets', 'bower'))

    # clean up old webpack packs to prevent stale packs now that we're hashing the filenames
    FileUtils.rm_rf(Rails.root.join('public', 'packs'))
  end

  task :print_engines do
    puts
    puts "JS plugins:"
    asset_engines.each do |engine|
      puts "  #{engine.name}:"
      puts "    namespace: #{engine.namespace}"
      puts "    path: #{engine.path}"
    end
    puts
  end

  task :actual_ui => ['update:clean', 'update:yarn', 'webpack:compile', 'update:print_engines']

  task :ui do
    # when running update:ui from ui-classic, asset_engines won't see the other engines
    # the same goes for Rake::Task#invoke
    if defined?(ENGINE_ROOT) && !ENV["TRAVIS"]
      Dir.chdir Rails.root do
        Bundler.with_clean_env do
          system("bundle exec rake update:actual_ui")
        end
      end
    else
      Rake::Task['update:actual_ui'].invoke
    end
  end
end

namespace :webpack do
  task :server do
    root = ManageIQ::UI::Classic::Engine.root
    webpack_dev_server = root.join("bin", "webpack-dev-server").to_s
    system(webpack_dev_server) || abort("\n== webpack-dev-server failed ==")
  end

  def run_webpack(task)
    if %w(spec spec:jest).include? ENV['TEST_SUITE']
      warn "Skipping webpack:#{task} on travis #{ENV['TEST_SUITE']}"
      return
    end

    # Run the `webpack:compile` tasks without a fully loaded environment,
    # since when doing an appliance/docker build, a database isn't
    # available for the :environment task (prerequisite for
    # 'webpacker:compile') to function.
    EvmRakeHelper.with_dummy_database_url_configuration do
      Dir.chdir ManageIQ::UI::Classic::Engine.root do
        Rake::Task["webpack:paths"].invoke
        Rake::Task["webpacker:#{task}"].invoke
      end
    end
  end

  task :compile do
    run_webpack(:compile)
  end

  task :clobber do
    run_webpack(:clobber)
  end

  task :paths do
    json = JSON.pretty_generate(
      :info    => "This file is autogenerated by rake webpack:paths, do not edit",
      :output  => Rails.root.to_s,
      :engines => asset_engines.map { |p|
                    key = p.namespace
                    value = {:root => p.path,
                             :node_modules => File.join(p.path, 'node_modules')}

                    [key, value]
                  }.to_h
    ) << "\n"

    File.write(ManageIQ::UI::Classic::Engine.root.join('config/webpack/paths.json'), json)
  end
end

# compile and clobber when running assets:* tasks
if Rake::Task.task_defined?("assets:precompile")
  Rake::Task["assets:precompile"].enhance do
    Rake::Task["webpack:compile"].invoke unless ENV["TRAVIS"]
  end

  Rake::Task["assets:precompile"].actions.each do |action|
    if action.source_location[0].include?(File.join("lib", "tasks", "webpacker"))
      Rake::Task["assets:precompile"].actions.delete(action)
    end
  end
end

if Rake::Task.task_defined?("assets:clobber")
  Rake::Task["assets:clobber"].enhance do
    Rake::Task["webpack:clobber"].invoke unless ENV["TRAVIS"]
  end

  Rake::Task["assets:clobber"].actions.each do |action|
    if action.source_location[0].include?(File.join("lib", "tasks", "webpacker"))
      Rake::Task["assets:clobber"].actions.delete(action)
    end
  end
end

namespace :yarn do
  # yarn:install is a rails 5.1 task, webpacker:compile needs it
  task :install do
    puts 'yarn:install called, not doing anything'
  end

  # useful right after upgrading node
  task :clobber do
    puts 'Removing yarn.lock and node_modules in...'
    asset_engines.each do |engine|
      puts "  #{engine.name} (#{engine.path})"
      FileUtils.rm_rf(engine.path.join('node_modules'))
      FileUtils.rm_rf(engine.path.join('yarn.lock'))
    end
  end
end

# need the initializer for the rake tasks to work
require ManageIQ::UI::Classic::Engine.root.join('config/initializers/webpacker.rb')
unless Rake::Task.task_defined?("webpacker")
  load 'tasks/webpacker.rake'
  load 'tasks/webpacker/clobber.rake'
  load 'tasks/webpacker/verify_install.rake'         # needed by compile
  load 'tasks/webpacker/check_node.rake'             # needed by verify_install
  load 'tasks/webpacker/check_yarn.rake'             # needed by verify_install
  load 'tasks/webpacker/check_webpack_binstubs.rake' # needed by verify_install
end

# original webpacker:compile still gets autoloaded during bin/update
if Rake::Task.task_defined?('webpacker:compile')
  Rake::Task['webpacker:compile'].actions.clear
end

# the original webpack:compile fails to output errors, using system instead
require "webpacker/env"
require "webpacker/configuration"
namespace :webpacker do
  task :compile => ["webpacker:verify_install", :environment] do
    asset_host = ActionController::Base.helpers.compute_asset_host
    env = { "NODE_ENV" => Webpacker.env, "ASSET_HOST" => asset_host }.freeze

    system(env, './bin/webpack')

    if $?.success?
      $stdout.puts "[Webpacker] Compiled digests for all packs in #{Webpacker::Configuration.entry_path}:"
      $stdout.puts JSON.parse(File.read(Webpacker::Configuration.manifest_path))
    else
      $stderr.puts "[Webpacker] Compilation Failed"
      exit!
    end
  end
end

def asset_engines
  @asset_engines ||= begin
    require Rails.root.join("lib", "vmdb", "plugins")
    Vmdb::Plugins.asset_paths
  end
end
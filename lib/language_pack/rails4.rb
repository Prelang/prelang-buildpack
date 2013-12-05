require "language_pack"
require "language_pack/rails3"

class UbuntuPackage
  include LanguagePack::ShellHelpers

  attr_accessor :vendor_dir, :name, :deb_filename, :url_prefix

  def initialize(vendor_dir, name, deb_filename, url_prefix)
    @vendor_dir = vendor_dir
    @name = name
    @deb_filename = deb_filename
    @url_prefix = url_prefix
  end

  def deb_url
    "#{@url_prefix}/#{@deb_filename}"
  end

  def install!()
    bin_dir = "vendor/#{@vendor_dir}"
    FileUtils.mkdir_p bin_dir

    Dir.chdir(bin_dir) do |dir|
      run("curl '#{deb_url()}' > #{@deb_filename}")
      run("dpkg -x #{@deb_filename} .")
      FileUtils.rm @deb_filename
    end

  end
end

# Rails 4 Language Pack. This is for all Rails 4.x apps.
class LanguagePack::Rails4 < LanguagePack::Rails3
  ASSETS_CACHE_LIMIT = 52428800 # bytes

  # detects if this is a Rails 4.x app
  # @return [Boolean] true if it's a Rails 4.x app
  def self.use?
    instrument "rails4.use" do
      rails_version = bundler.gem_version('railties')
      return false unless rails_version
      is_rails4 = rails_version >= Gem::Version.new('4.0.0.beta') &&
                  rails_version <  Gem::Version.new('4.1.0.beta1')
      return is_rails4
    end
  end

  def name
    "Ruby/Rails"
  end

  def default_process_types
    instrument "rails4.default_process_types" do
      super.merge({
        "web"     => "bin/rails server -p $PORT -e $RAILS_ENV",
        "console" => "bin/rails console"
      })
    end
  end

  def build_bundler
    instrument "rails4.build_bundler" do
      super
    end
  end

  def compile
    instrument "rails4.compile" do
      super
      install_prelang_dependencies
    end
  end

  private

  def install_prelang_dependencies
    topic("Installing Prelang dependencies")

    # SQLite
    bin_dir = "vendor/sqlite3"
    FileUtils.mkdir_p bin_dir
    FileUtils.mkdir_p "#{bin_dir}/libsqlite3-dev"

    Dir.chdir(bin_dir) do |dir|
      run("curl 'http://mirrors.kernel.org/ubuntu/pool/main/s/sqlite3/libsqlite3-dev_3.6.22-1_amd64.deb' > libsqlite3-dev_3.6.22-1_amd64.deb")
      run("dpkg -x libsqlite3-dev_3.6.22-1_amd64.deb libsqlite3-dev")
    end

    # Install sqlite3 gem
    run("gem install sqlite3 -- --with-sqlite3-dir=/app/vendor/sqlite3")


  end

  def install_plugins
    instrument "rails4.install_plugins" do
      return false if bundler.has_gem?('rails_12factor')
      plugins = ["rails_serve_static_assets", "rails_stdout_logging"].reject { |plugin| bundler.has_gem?(plugin) }
      return false if plugins.empty?

    warn <<-WARNING
Include 'rails_12factor' gem to enable all platform features
See https://devcenter.heroku.com/articles/rails-integration-gems for more information.
WARNING
    # do not install plugins, do not call super
    end
  end

  def public_assets_folder
    "public/assets"
  end

  def default_assets_cache
    "tmp/cache/assets"
  end

  def run_assets_precompile_rake_task
    instrument "rails4.run_assets_precompile_rake_task" do
      log("assets_precompile") do
        if Dir.glob('public/assets/manifest-*.json').any?
          puts "Detected manifest file, assuming assets were compiled locally"
          return true
        end

        precompile = rake.task("assets:precompile")
        return true unless precompile.is_defined?

        topic("Preparing app for Rails asset pipeline")

        @cache.load public_assets_folder
        @cache.load default_assets_cache

        precompile.invoke(env: rake_env)

        if precompile.success?
          log "assets_precompile", :status => "success"
          puts "Asset precompilation completed (#{"%.2f" % precompile.time}s)"

          puts "Cleaning assets"
          rake.task("assets:clean").invoke(env: rake_env)

          cleanup_assets_cache
          @cache.store public_assets_folder
          @cache.store default_assets_cache
        else
          precompile_fail(precompile.output)
        end
      end
    end
  end

  def cleanup_assets_cache
    instrument "rails4.cleanup_assets_cache" do
      LanguagePack::Helpers::StaleFileCleaner.new(default_assets_cache).clean_over(ASSETS_CACHE_LIMIT)
    end
  end
end

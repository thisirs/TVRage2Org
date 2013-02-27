#! /usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'date'
require 'logger'
require 'yaml'
require 'fileutils'
require 'optparse'

class Episode
  attr_accessor :title, :air_date, :season, :episode
end

class Show
  BASE_URL="http://services.tvrage.com/feeds/search.php?show=%s"
  SEARCH_URL="http://services.tvrage.com/feeds/episodeinfo.php?sid=%d"

  # Minimum days between two checks when no next air date
  DAYS_UNTIL_NEXT_CHECK = 15

  # Number of days preceding an air date during which we don't recheck
  DAYS_PRECEDING = 7

  attr_accessor :name, :alt_name, :id, :next_eps, :eps_list, :last_check

  def initialize(name)
    @name = name
    @eps_list = []
    @id = nil
    @last_check = nil
  end

  # Update next air date if needed. Depends on last check and next air
  # date if any.
  def update_next_episode
    $log.debug("Update next episode for show #{@name}")
    $log.debug("Last check date is #{@last_check || "nil"}")

    now = DateTime.now
    $log.debug("Now is #{now}")

    if @next_eps
      $log.debug("Next episode present")
      if @next_eps.air_date < now
        $log.debug("Next episode is past")
        begin
          eps = retrieve_next_episode
          @eps_list << @next_eps
          @last_check = now
          @next_eps = eps
        rescue Exception => e
          $log.error("Unable to retrieve next episode #{e}")
        end
      else
        if @last_check and @next_eps.air_date - now < now - @last_check \
          and @next_eps.air_date > now + DAYS_PRECEDING
          $log.debug("Mid date reached or not too close to next air date")
          begin
            @next_eps = retrieve_next_episode
            @last_check = now
          rescue Exception => e
            $log.error("Unable to retrieve next episode #{e}")
          end
        else
          $log.debug("Not at mid date or show in less than #{DAYS_PRECEDING} days")
        end
      end
    else
      $log.debug("No next episode")
      if not @last_check or now - @last_check > DAYS_UNTIL_NEXT_CHECK
        $log.debug("More than #{DAYS_UNTIL_NEXT_CHECK} days since last check or no last check")
        begin
          @next_eps = retrieve_next_episode
          @last_check = now
        rescue Exception => e
          $log.error("Unable to retrieve next episode #{e}")
        end
      else
        $log.debug("No need to check again")
      end
    end
  end

  def retrieve_next_episode
    $log.debug("Retrieving next #{name} episode...")

    unless @id
      $log.debug("No ID, retrieving...")
      doc = Nokogiri::XML(open(BASE_URL % CGI::escape(name)))
      @id = doc.xpath("/Results/show[1]/showid").text.to_i
    end

    $log.debug("Id is #{@id}")
    doc = Nokogiri::XML(open(SEARCH_URL % @id))
    eps = Episode.new

    sec = doc.xpath("/show/nextepisode/airtime[@format='GMT+0 NODST']").text.to_i
    eps.air_date = Time.at(sec).to_datetime
    $log.debug("Air date is #{eps.air_date || "nil"}")

    eps.title = doc.xpath("/show/nextepisode/title").text
    $log.debug("Title is #{eps.title || "nil"}")

    number = doc.xpath("/show/nextepisode/number").text
    if number =~ /(\d)+x(\d)+/
      eps.season = $1.to_i
      eps.episode = $2.to_i
    end
    $log.debug("Season is #{eps.season || "nil"}")
    $log.debug("Episode is #{eps.episode || "nil"}")

    eps
  end

  def to_org(prev = nil)
    if @next_eps
      episodes = [@next_eps]
    else
      episodes = []
    end
    episodes = episodes + @eps_list if prev

    episodes.map do |e|
      time_str = e.air_date.strftime("%Y-%m-%d")
      template = $config["org_template"]
      template.gsub("%N", name)
        .gsub("%n", alt_name)
        .gsub("%U", time_str)
        .gsub("%T", e.title)
        .gsub("%S", "%02d" % e.season)
        .gsub("%E", "%02d" % e.episode)
    end.join("\n")
  end
end

if __FILE__ == $PROGRAM_NAME

  CONFIG_PATH = File.expand_path("~/.config/TVrage2org")
  DATABASE_FILE = "database.yaml"
  DATABASE_PATH = CONFIG_PATH + "/" + DATABASE_FILE

  $log = Logger.new(STDERR)

  options = {}

  options_parser = OptionParser.new do |opts|
    opts.banner = "Usage: TVrage2org.rb [OPTIONS]"

    opts.on("-f", "--config CONFIG-FILE", "YAML conf file") do |f|
      options[:conf_file] = File.expand_path(f) || "/etc/TVrage2org.conf"
    end

    opts.on("-o", "--org-file ORG-FILE", "Org output file") do |f|
      options[:org_file] = File.expand_path(f)
    end

    levels = [:fatal, :error, :warn, :info, :debug]
    opts.on("-d", "--debug LEVEL", levels, "Debug level") do |level|
      options[:level] = Logger::const_get(level) || Logger::UNKNOWN
    end

    opts.on( '-h', '--help', 'Display this screen' ) do
      puts opts
      exit
    end
  end

  options_parser.parse!

  begin
    $log.debug("Loading \"#{options[:conf_file]}\"")
    $config = YAML.load_file(options[:conf_file])
  rescue
    $log.error("Unable to load file \"#{options[:conf_file]}\"")
    begin
      $log.debug("Loading \"/etc/TVrage2org.conf\"")
      $config = YAML.load_file("/etc/TVrage2org.conf")
    rescue
      $log.error("Unable to load file \"/etc/TVrage2org.conf\"")
      $config = {"shows" => [], "org_template" => "** <%U> %N S%SE%E %T"}
    end
  end

  begin
    database = YAML.load_file(DATABASE_PATH)
  rescue
    $log.error("Unable to load file \"#{DATABASE_PATH}\"")
  ensure
    database = [] unless database.is_a?(Array)
  end

  # Where Org file contents will be written
  output =
    if options[:org_file]
      File.open(options[:org_file], "w")
    else
      STDOUT
    end

  # Write org file header
  contents = File.read(CONFIG_PATH + "/head.org")
  output.puts(contents)

  $config["shows"].each do |names|
    if names.is_a? Array
      name = names.first
      alt_name = names[1]
    else
      name = names
      alt_name = names
    end

    show = database.select { |s| s.name == name }.first

    # Add if not in database
    unless show
      $log.debug("Adding #{name} to database")
      show = Show.new(name)
      show.alt_name = alt_name
      database << show
    end

    # Update next episode if necessary
    show.update_next_episode

    # Write air dates
    $log.debug("Org heading is #{show.to_org}")
    output.puts show.to_org(:all)
  end

  output.close if output.is_a? File

  # Save database
  FileUtils.mkdir_p(CONFIG_PATH)
  File.open(DATABASE_PATH, "w") { |f| f.write(database.to_yaml) }
end

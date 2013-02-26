#! /usr/bin/env ruby

require 'nokogiri'
require 'open-uri'
require 'cgi'
require 'date'
require 'logger'
require 'yaml'
require 'fileutils'
require 'optparse'

class Show
  BASE_URL="http://services.tvrage.com/feeds/search.php?show=%s"
  SEARCH_URL="http://services.tvrage.com/feeds/episodeinfo.php?sid=%d&ep=1x01"

  # Minimum days between two checks when no next air date
  DAYS_UNTIL_NEXT_CHECK = 15

  # Number of days preceding an air date during which we don't recheck
  DAYS_PRECEDING = 7

  attr_accessor :name, :id, :next_air_date, :past_air_dates, :last_check

  def initialize(name)
    @name = name
    @past_air_dates = []
    @id = nil
    @next_air_date = nil
    @last_check = nil
  end

  # Update next air date if needed. Depends on last check and next air
  # date if any.
  def update_next_air_date
    $log.debug("Update next air date for show #{@name}")
    $log.debug("Next air date is #{@next_air_date || "nil"}")
    $log.debug("Last check date is #{@last_check || "nil"}")

    now = DateTime.now
    $log.debug("Now is #{now}")

    if @next_air_date
      if @next_air_date < now
        $log.debug("Next air date is past")
        begin
          date = retrieve_next_air_date
          @past_air_dates << @next_air_date
          @last_check = now
          @next_air_date = date
        rescue
          $log.error("Unable to retrieve next air date")
        end
      else
        if @last_check and @next_air_date - now < now - @last_check \
          and @next_air_date > now + DAYS_PRECEDING
          $log.debug("Mid date reached or not too close to next air date")
          begin
            @next_air_date = retrieve_next_air_date
            @last_check = now
          rescue
            $log.error("Unable to retrieve next air date")
          end
        else
          $log.debug("Not at mid date or show in less than #{DAYS_PRECEDING} days")
        end
      end
    else
      $log.debug("No next air date")
      if not @last_check or now - @last_check > DAYS_UNTIL_NEXT_CHECK
        $log.debug("More than #{DAYS_UNTIL_NEXT_CHECK} days since last check or no last check")
        begin
          @next_air_date = retrieve_next_air_date
          @last_check = now
        rescue
          $log.error("Unable to retrieve next air date")
        end
      else
        $log.debug("No need to check again")
      end
    end
  end

  def retrieve_next_air_date
    $log.debug("Retrieving next air date for show #{name}...")
    unless @id
      $log.debug("Retrieving ID")
      doc = Nokogiri::XML(open(BASE_URL % CGI::escape(name)))
      @id = doc.xpath("/Results/show[1]/showid").text.to_i
    end
    $log.debug("Id is #{@id}")
    doc = Nokogiri::XML(open(SEARCH_URL % @id))
    sec = doc.xpath("/show/nextepisode/airtime[@format='GMT+0 NODST']").text.to_i
    $log.debug("Raw date is #{sec}")
    date = Time.at(sec).to_datetime
    $log.debug("Next air date is #{date || nil}")
    date
  end

  def to_org(prev = nil)
    dates = [@next_air_date]
    dates = dates + past_air_dates if prev

    dates.map do |d|
      time_str = d.strftime("%Y-%m-%d")
      $config["org_template"] % [time_str, name]
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
      $config = {"shows" => [], "org_template" => "** <%s> %s"}
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

  $config["shows"].each do |name|
    show = database.select { |s| s.name == name }.first

    # Add if not in database
    unless show
      $log.debug("Adding #{name} to database")
      show = Show.new(name)
      database << show
    end

    # Update next_air_date if necessary
    show.update_next_air_date

    # Write air dates
    output.puts show.to_org
  end

  output.close if output.is_a? File

  # Save database
  FileUtils.mkdir_p(CONFIG_PATH)
  File.open(DATABASE_PATH, "w") { |f| f.write(database.to_yaml) }
end

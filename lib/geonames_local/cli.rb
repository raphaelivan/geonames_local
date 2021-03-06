#
# Geonames Local
#
require 'optparse'
module Geonames
  class CLI
    def self.parse_options(argv)
      options = {}

      argv.options do |opts|
        opts.banner = <<BANNER
Geonames Command Line Usage:

geonames <country code(s)> <opts>

geonames
BANNER
        opts.on("-l", "--level LEVEL", String, "The level of logging to report" ) { |level| options[:level] = level }
        opts.on("-d", "--dump", "Dump DB before all" ) { options[:dump] = true }
        opts.separator ""
        opts.separator "Config file:"
        opts.on("-c", "--config CONFIG", String, "Geonames Config file path" ) { |file|  options[:config] = file }
        opts.on("-i", "--import CONFIG", String, "Geonames Import SHP/DBF/GPX" ) { |file|  options[:shp] = file }
        opts.separator ""
        opts.separator "SHP Options:"
        opts.on("--map TYPE", Array, "Use zone/road to import" ) { |s| options[:map] = s.map(&:to_sym) }
        opts.on("--type TYPE", String, "Use zone/road to import" ) { |s| options[:type] = s }
        opts.on("--city CITY", String, "Use city gid to import" ) { |s| options[:city] = s }
        opts.on("--country COUNTRY", String, "Use country gid to import" ) { |s| options[:country] = s }
        opts.separator ""
        opts.separator "Common Options:"
        opts.on("-h", "--help", "Show this message" ) { puts opts; exit }
        opts.on("-v", "--verbose", "Turn on logging to STDOUT" ) { |bool| options[:verbose] = bool }
        opts.on("-V", "--version", "Show version") {  puts Geonames::VERSION;  exit }
        opts.separator ""
        begin
          opts.parse!
          if argv.empty? && !options[:config]
            puts opts
            exit
          end
        rescue
          puts opts
          exit
        end
      end
      options
    end
    private_class_method :parse_options

    class << self

    # Ugly but works?
    def work(argv)
      trap(:INT) { stop! }
      trap(:TERM) { stop! }
      Opt.merge! parse_options(argv)

      if Opt[:config]
        Opt.merge! YAML.load(File.read(Opt[:config]))
      end

      if shp = Opt[:shp]
        SHP.import(shp)
        exit
      end

      if argv[0] =~ /list|codes/
         Codes.each do |key,val|
          str = [val.values, key.to_s].join(" ").downcase
          if s = argv[1]
            next unless str =~ /#{s.downcase}/
          end
          puts "#{val[:en_us]}: #{key}"
        end
        exit
      end

      #
      # If arguments scaffold, config, write down yml.
      #
      if argv[0] =~ /scaff|conf/
        fname = (argv[1] || "geonames") + ".yml"
        if File.exist?(fname)
          puts "File exists."
        else
          puts "Writing to #{fname}"
          `cp #{File.join(File.dirname(__FILE__), 'config', 'geonames.yml')} #{fname}`
        end
        exit
      end
      require "geo_ruby" if Opt[:mapping] && Opt[:mapping][:geom]

      if argv[0] =~ /csv|json/
        Geonames::Export.new(Country.all).to_csv
      else
        db = load_adapter(Opt[:store])
        info "Using adapter #{Opt[:store]}.."
        Geonames::Dump.work(Opt[:codes], :zip) #rescue puts "Command not found: #{comm} #{@usage}"
        Geonames::Dump.work(Opt[:codes], :dump) #rescue puts "Command not found: #{comm} #{@usage}"
        info "\n---\nTotal #{Cache[:dump].length} parsed. #{Cache[:zip].length} zips."
        info "Join dump << zip"
        unify!
        write_to_store!(db)
      end
    end

    def load_adapter(name)
      begin
        require "geonames_local/adapters/#{name}"
        Geonames.class_eval(name.capitalize).new(Opt[:db])
      rescue LoadError
        puts "Can't find adapter #{name}"
        stop!
      end
    end

    def write_to_store!(db)
      groups = Cache[:dump].group_by(&:kind)
      Cache[:provinces] = groups[:provinces]
      # ensure this order....
      do_write(db, groups[:provinces])
      do_write(db, groups[:cities])
    end

    def do_write(db, values)
      return if values.empty?
      key = values[0].table
      start = Time.now
      writt = 0
      info "\nWriting #{values.length} #{key}..."
      values.each do |val|
        meth = val.respond_to?(:gid) ? [val.gid] : [val.name, true]
        unless db.find(val.table, *meth)
          db.insert(val.table, val)
          writt += 1
        end
      end
      total = Time.now - start
      info "#{writt} #{key} written in #{total} sec (#{(writt/total).to_i}/s)"
    end

    def unify!
      start = Time.now
      Cache[:dump].map! do |spot|
        if other = Cache[:zip].find { |d| d.code == spot.code }
          spot.zip = other.zip
          spot
        else
          spot
        end
      end
      info "Done. #{(Time.now-start).to_i}s"
    end

    def stop!
      puts "Closing Geonames..."
      exit
    end
    end

  end

end

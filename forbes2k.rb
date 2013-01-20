#!/usr/bin/env ruby
require_relative 'smtp_enc_check'
require 'net/http'
require 'json'
require 'terminal-table'
require 'actionpool'
require 'csv'
FORBES2K_URI=URI("http://www.forbes.com/ajax/load_list/?type=organization&uri=global2000&year=2012")
LEVELS=%w(DEBUG INFO WARN ERROR FATAL)
OUTPUTS=%w(table csv)
class AnalyzeForbes2000
  def initialize
    @logger=setupDefaulLogger
  end

  def setupDefaulLogger
    l = Log4r::Logger.new self.class.to_s
    l.outputters = Log4r::Outputter.stdout
    return l
  end

  def getCompanies
  	@logger.debug "Fetching companies"
    JSON.parse (Net::HTTP.get(FORBES2K_URI))
  end

  def getWebsiteURI (company)
  	@logger.debug "Fetching website for #{company}"
    html=Net::HTTP.get(URI("http://www.forbes.com/companies/#{company}/"))
    begin 
    website=((html.match /<li>Website: <a href="\s*([^"]+)\s*"/m)[1]).strip
	rescue
		@logger.error "No website for #{company} found!"
		return nil
	end
    @logger.debug "Website for #{company} is '#{website}'"
    return website
  end

# 
  def main
  	opts = Trollop::options do
      version "Forbes 2000 SMTP encryption analyzer v0.1 by Konrads Smelkovs, (c) 2013"
      opt :threads, "How many threads to use ", :type => :int, :default =>10
      opt :log_level, "log level, valid options are " + LEVELS.join(", "), :type => :string, :default=>'INFO'
      opt :sample_size, "How many companies to sample", :type => :int, :default => 0
      opt :output, "What output format to use: " + OUTPUTS.join(", "), :type => :string, :default => 'table'
    end
    Trollop::die :threads , "must be larger than 0" if opts[:threads]<1
    Trollop::die :log_level, "unknown log level #{opts[:log_level]}" if not LEVELS.include? opts[:log_level]
    Trollop::die :sample_size, "Sample size must be between 1 and 2000 (It's Forbes TWO THOUSAND not Galaxy survery!" \
    	if not opts[:sample_size].between? 1,2000
    Trollop::die :output, "unknown output type #{opts[:output]}" if not OUTPUTS.include? opts[:output].downcase
    @logger.level=Log4r.const_get(opts[:log_level])
  	results={}
  	companies=getCompanies
  	pool = ActionPool::Pool.new(
       # :min_threads => 1,
       :max_threads => opts[:threads],
       # :a_to => 180
     )
  	(companies.sample opts[:sample_size]).each do |c|
  		pool.queue Proc.new {
	  		longname=c[2]
	  		shortname=c[1]
	  		website=getWebsiteURI shortname
	  		if website.nil?
	  			next
	  		end
	  		results[shortname]={:longname => longname}
		    d=Domainatrix.parse website.strip
	        domain="#{d.domain}.#{d.public_suffix}"
	        # pool.proc
	        checker=SMTPEncryptionChecker.new @logger
	        checks=checker.checkDomain domain
	        results[shortname][:totalmx]=checks.count
	        if checks.empty?
	        	
	         	next
	        end
	        accepts=0
	        failures=[]
	        # puts ">>>>>>" + (checks.join ":")
	        checks.each do |server,result| 
	        
		        if result===true
		        	accepts+=1
		        else
		        	failures << "#{server} said: #{result}"
		        end
	    	end
	    	if accepts == checks.count
		        	results[shortname][:starttls_accepted]="Fully"
		    elsif accepts == 0
		    	results[shortname][:starttls_accepted]= "Never"
		    else
		        	results[shortname][:starttls_accepted]="Partially"
		    end
		    results[shortname][:errors]=failures.join "\n"
	    	results[shortname][:supportingmx]=accepts
    	}
  	end
 #  	require 'pry'
	# binding.pry
  	while pool.working >0
  		@logger.debug "Waiting for tasks to finish, #{pool.working} threads active, #{pool.action_size} left"
  		sleep 1
  	end
  	@logger.debug("Shutting down pool")
  	pool.shutdown

  	case opts[:output].downcase
  	when "table"
	  	rows=[]
	  	results.each do |name,r|
	  		row=[]
	  		# require 'pry'
	  		# binding.pry
	  		row << r[:longname]
	  		row << r[:starttls_accepted]
	  		row << "#{r[:supportingmx]}/#{r[:totalmx]||0}"
	  		row << r[:errors]
	  		rows << row
	  	end
	  	puts Terminal::Table.new :title => "Forbes 2000 survey results", 
	  	:headings => ["Company","STARTTLS Support","MX Accept","Errors"],
	  	:rows => rows
	when "csv"
		csv_options={:headers => ["Company","STARTTLS Support","MX Accept","Total MX", "Errors"],
					:write_headers => true }
		txt=CSV.generate csv_options do |csv|
			results.each do |name, r|
				csv << [r[:longname],r[:starttls_accepted],r[:starttls_accepted],r[:totalmx]||0,r[:errors]]
			end
		end
		
		puts txt
	end
  	

  end # def main


  end #AnalyzeForbes2000
  if __FILE__ == $0
    AnalyzeForbes2000.new().main
  end

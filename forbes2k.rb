#!/usr/bin/env ruby
require_relative 'smtp_enc_check'
require 'net/http'
require 'json'
require 'terminal-table'
# require 'actionpool'
FORBES2K_URI=URI("http://www.forbes.com/ajax/load_list/?type=organization&uri=global2000&year=2012")

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
  	results={}
  	companies=getCompanies
  	 # pool = ActionPool::Pool.new(
    #   :min_threads => 1,
    #   :max_threads => 5,
    #   :a_to => 180
    # )
  	(companies.sample 25).each do |c|
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
	        	failures << result
	        end
    	end
		# require 'pry'
  #       binding.pry
    	if accepts == checks.count
	        	results[shortname][:starttls_accepted]="Fully"
	    elsif accepts == 0
	    	results[shortname][:starttls_accepted]= "Never"
	    else
	        	results[shortname][:starttls_accepted]="Partially"
	    end
	    results[shortname][:errors]=failures.join "\n"
    	results[shortname][:supportingmx]=accepts
  	end
  	rows=[]
  	results.each do |name,r|
  		row=[]
  		# require 'pry'
  		# binding.pry
  		row << r[:longname]
  		row << r[:starttls_accepted]
  		row << "#{r[:supportingmx]||0}/#{r[:totalmx]}"
  		row << r[:errors]
  		rows << row
  	end
  	puts Terminal::Table.new :title => "Forbes 2000 survey results", 
  	:headings => ["Compnay","STARTTLS Support","MX Accept","Errors"],
  	:rows => rows

  end # def main


  end #AnalyzeForbes2000
  if __FILE__ == $0
    AnalyzeForbes2000.new().main
  end

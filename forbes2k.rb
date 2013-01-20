#!/usr/bin/env ruby
require_relative 'smtp_enc_check'
require 'net/http'
require 'json'
require 'terminal-table'
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
    website=((html.match /<li>Website: <a href="\s*([^"]+)\s*"/m)[1]).strip
    @logger.debug "Website for #{company} is '#{website}'"
    return website
  end

# 
  def main
  	results={}
  	companies=getCompanies
  	(companies.sample 10).each do |c|
  		longname=c[2]
  		shortname=c[1]
  		website=getWebsiteURI shortname
  		results[shortname]={:longname => longname}
	    d=Domainatrix.parse website.strip
        domain="#{d.domain}.#{d.public_suffix}"
        checker=SMTPEncryptionChecker.new @logger
        checks=checker.checkDomain domain
        results[shortname][:totalmx]=checks.count
        if checks.empty?
        	results[shortname][:starttls_accepted]= "Never"
        end
        accepts=0
        failures=[]
        checks.each do |mx| 
	        if mx===true
	        	accepts+=1
	        else
	        	failures << mx
	        end

	        if accepts == mx.count
	        	results[shortname][:starttls_accepted]="Fully"
	        else
	        	results[shortname][:starttls_accepted]="Partially"
	        	results[shortname][:errors]=failures.join "\n"
	        end

    	end
    	results[shortname][:supportingmx]=accepts
  	end
  	rows=[]
  	results.each do |r|
  		rows << [r[:longname],r[:starttls_accepted],"#{r[:supportingmx]}/#{r[:totalmx]}",r[:errors]]
  	end
  	Terminal::Table.new :title => "Forbes 2000 survey results", 
  	:headings => ["Compnay","STARTTLS Support","MX Accept","Errors"],
  	:rows => rows

  end # def main


  end #AnalyzeForbes2000
  if __FILE__ == $0
    AnalyzeForbes2000.new().main
  end

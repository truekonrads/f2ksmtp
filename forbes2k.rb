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
class String
	# Wrap string by the given length, and join it with the given character.
	# The method doesn't distinguish between words, it will only work based on
	# the length. The method will also strip and whitespace.
	#
	def wrap(length = 80, character = $/)
		scan(/.{#{length}}|.+/).map { |x| x.strip }.join(character)
	end
end

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
  	begin
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
	rescue
		@logger.error("Unhandled exception in getWebsiteURI: #{$!}")
		return nil
	end
   end


               #
   def main
     opts = Trollop::options do
       version "Forbes 2000 SMTP encryption analyzer v0.1 by Konrads Smelkovs, (c) 2013"
       opt :threads, "How many threads to use ", :type => :int, :default =>10
       opt :log_level, "log level, valid options are " + LEVELS.join(", "), :type => :string, :default=>'INFO'
       opt :sample_size, "How many companies to sample", :type => :int, :default => 0
       opt :output, "What output format to use: " + OUTPUTS.join(", "), :type => :string, :default => 'table'
       opt :company, "Pick a specific company", :type => :string
       opt :hostname, "Specify host name with which to HELO", :type => :string, :short => "-n"
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
       if opts[:company]
       	targets=companies.find_all {|c| c[1]==opts[:company] or c[2]==opts[:company]}
       else 
       	targets=companies.sample opts[:sample_size]
       end
       targets.each do |c|
         pool.queue Proc.new {
           longname=c[2]
           shortname=c[1]
           website=getWebsiteURI shortname
           if website.nil?
             next
           end
           results[shortname]={:longname => longname, :mx=>[]}
           d=Domainatrix.parse website.strip
           domain="#{d.domain}.#{d.public_suffix}"
           # pool.proc
           checker=SMTPEncryptionChecker.new @logger, opts[:hostname]
           checks=checker.checkDomain domain
           if checks.empty?
             next
           end
           results[shortname][:mx] = checks

         }
       end
       #  	require 'pry'
       # binding.pry
       while pool.working >0
         @logger.debug "Waiting for tasks to finish, #{pool.working} threads still active, #{pool.action_size} actions left"
         sleep 1
       end
       @logger.debug("Shutting down pool")
       pool.shutdown




       #    accepts=0
       #    failures=[]
       #    # puts ">>>>>>" + (checks.join ":")
       #    checks.each do |server,result|

       #     if result===true
       #     	accepts+=1
       #     else
       #     	failures << "#{server} said: #{result}"
       #     end
       # end
       # if accepts == checks.count
       #     	results[shortname][:starttls_accepted]="Fully"
       # elsif accepts == 0
       # 	results[shortname][:starttls_accepted]= "Never"
       # else
       #     	results[shortname][:starttls_accepted]="Partially"
       # end
       # results[shortname][:errors]=failures.join "\n"
       # results[shortname][:supportingmx]=accepts
       results.each { |shortname,v|
         v[:starttls_support]="N/A"
         v[:mx]=v[:mx].delete_if {|x| x.nil?}
          
         v[:good_mx]=v[:mx].find_all {|mx| mx[:starttls] == true and mx[:verification]==true} 
         v[:partial_mx]=v[:mx].find_all {|mx| mx[:starttls] == true and mx[:verification]==false} 
         v[:connected_mx]=v[:mx].find_all {|mx| mx[:connection_success]==true }

         if v[:connected_mx].count > 0
           if v[:good_mx].count == v[:connected_mx].count and v[:partial_mx].count == 0
             v[:starttls_support]="Full"
           elsif v[:partial_mx].count >0
             v[:starttls_support]="Eavesdropping"
           else
             v[:starttls_support]="None"
           end
           # require 'pry'
           # binding.pry
           errors=[]
           v[:mx].each {|mx| errors << mx[:error] if mx[:error]}
           v[:errors]=errors.join("\n")
          end
          }
           case opts[:output].downcase
           when "table"
             rows=[]
             results.each do |name,r|
               row=[]
               # require 'pry'
               # binding.pry
               row << (r[:longname] + "/" + name)
               row << r[:starttls_support]
               row << "#{r[:good_mx].count}/#{r[:partial_mx].count}/#{r[:connected_mx].count}/#{r[:mx].count}"
               row << (r[:errors] || "").wrap(50)
               rows << row
             end
             puts Terminal::Table.new :title => "Forbes 2000 survey results",
               :headings => ["Company","Support Level","MX Accept\n(G/P/C/T)","Errors"],
               :rows => rows
               # :style => {:width => 76}
           when "csv"
             csv_options={:headers => ["Company","Support Level","Full MX","Partial MX", "Total MX", "Errors"],
                          :write_headers => true }
             txt=CSV.generate csv_options do |csv|
               results.each do |name, r|
                 csv << [r[:longname],r[:starttls_support],r[:good_mx].count,r[:partial_mx].count,r[:mx].count,r[:errors]]
               end
             end

             puts txt
           end


         end # def main


end #AnalyzeForbes2000
if __FILE__ == $0
	AnalyzeForbes2000.new().main
end

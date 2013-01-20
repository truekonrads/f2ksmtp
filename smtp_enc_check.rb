#!/usr/bin/env ruby
require 'net/smtp'
require 'trollop'
require 'log4r'
require 'domainatrix'
require 'resolv'
require 'openssl'
require 'socket'
# require 'dnsruby'
#include Dnsrub"


class SMTPEncryptionChecker
  def initialize (logger=nil, hostname = nil)
  	if hostname.nil?
  		@hostname = Socket::gethostname
  	else
  		@hostname = hostname
  	end
    if not logger
      @logger=setupDefaulLogger
    else
      @logger=logger
    end
  end



    def setupDefaulLogger
      l = Log4r::Logger.new 'SMTPEncryptionChecker'
      l.outputters = Log4r::Outputter.stdout
      return l
    end



    def ensureDomain(host_or_domain)
      d=Domainatrix.parse "mockfix://#{host_or_domain}"
      domain="#{d.domain}.#{d.public_suffix}"
      return domain
    end

    def checkDomain(domain)
      mxservers=getExchangesForDomain(ensureDomain(domain))
      res=[]
      if not mxservers.empty?
	      mxservers.each do |s|
	        res<< (checkServer (s))
	      end
	  else
	  	@logger.error "No MX found for #{domain}"
	  end
	  return res
    end

    

    def checkServer(server)
      ret={:mx => server, :error => nil, :connection_success => false}
      @logger.debug("Probing #{server}")
      s=Net::SMTP.new(server,25)
      s.enable_starttls
      begin
        s.start @hostname
        s.finish
        @logger.info("Hurray! #{server} supports STARTTLS")
        ret.update ({:starttls =>true, :verification => true, :connection_success => true})
        # return ret
      rescue Errno::ECONNREFUSED, Timeout::Error, SocketError
      	err="Could not connect to #{server}: #{$!}"
        @logger.warn(err)
        ret.update ({:starttls => false, :verification => false , :error => err, :connection_success => false})
      rescue Net::SMTPFatalError
      	err="The server refused to receive messages: #{$!}"
        @logger.warn(err)
        ret.update ({:starttls => false, :verification => false , :error => err, :connection_success => true})
      rescue Net::SMTPUnsupportedCommand
      	err="#{server} does not support STARTTLS"
        @logger.info("#{server} does not support STARTTLS")
        ret.update ({:starttls => false, :verification => false, :connection_success => true })
      rescue OpenSSL::SSL::SSLError
      	err="STARTTLS is supported, but could not negotiate secure transmission: #{$!}"
        @logger.info(err)
        ret.update ({:starttls => true, :verification => false, :connection_success => true    }  )
      rescue
      	err="Unknwon error caught: #{$!}"
        @logger.error("Unknwon error caught: #{$!.class.to_s}/#{$!}")
        return nil
      end
      return ret
    end

    def getExchangesForDomain(domain)
      ex=[]
      @logger.debug("Fetching exchanges for #{domain}")
      resolver=Resolv::DNS.new
      # ans=resolver.query domain , Dnsruby::Types::MX
      resolver.getresources(domain,Resolv::DNS::Resource::IN::MX).each  {|a| ex << a.exchange.to_s}
      return ex
    end

    def main
      opts = Trollop::options do
        version "SMTP Encryption Checker v0.1 by (c) Konrads Smelkovs, 2013"
        opt :smtp_server, "SMTP server to check", :type => :string
        opt :domain , "Domain who's MX to check", :type => :string
        opt :forbes2k, "Go for forbes 2000 list", :type => :bool
      end
      Trollop::die "You must specify either smtp_server or domain" if not opts[:smtp_server] and not opts[:domain]
      Trollop::die "You must not specify both smtp_server  and domain " if  opts[:smtp_server] and  opts[:domain]
      #@logger=setupDefaulLogger
      #@logger=setupDefaulLogger
      servers=[]
      if opts[:smtp_server]
        servers<<opts[:smtp_server]
      end
      if opts[:domain]
        servers.concat (getExchangesForDomain(opts[:domain]))
      end

      servers.each do |s|

        checkServer s
      end
    end

  end #SMTPEncryptionChecker

  if __FILE__ == $0
    SMTPEncryptionChecker.new().main
  end

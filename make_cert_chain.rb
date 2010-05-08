require 'fileutils'
require 'erb'



#
# initialize all cert directories.
#
class Sslfun 

  @prv_key='private/ca-key.pem'
  @csr='ca.csr'
  @makefile = 'Makefile'
  @conf='openssl.cnf'
  @conf_erb="#{@conf}.erb"

  def self.init_certs(cas, ca_root)
    country = 'US'
    state = 'Oregon'
    city = 'Portland'
    org = 'Puppetlabs'
    unit = 'PS'

    cas.each do |ca|
      is_ca = 'true'
      FileUtils.mkdir ca unless File.exists? ca
      FileUtils.cp([@conf_erb, @makefile], ca)
      FileUtils.cd(ca) do |dir|
        cname = ca
        template = ERB.new(File.read(@conf_erb))
        File.open(@conf, 'w') do |fh|
          fh.write(template.result(binding))
        end
        `make init`
        unless ca == ca_root
          `openssl req -new -nodes -key #{@prv_key} -config #{@conf} -out #{@csr}`
        end
      end
    end
  end


  def self.sign_certs(root, ca_2)
    FileUtils.cd(root) do |dir|
      ca_2.each do |ca|
        FileUtils.cp("../#{ca}/#{@csr}", "#{ca}.csr")
        `openssl ca -config #{@conf} -extfile #{@conf} -extensions v3_ca -in #{ca}.csr -out ../#{ca}/ca-cert.pem`
      end 
    end  
    `cat **/ca-cert.pem > ca-bundle.pem` 
  end

  def self.ssl_certs(hosts)
    country = 'US'
    state = 'Oregon'
    city = 'Portland'
    org = 'Puppetlabs'
    unit = 'PS'
    hosts.each do |ca, host|
      is_ca='false'
      FileUtils.mkdir(host) unless File.exists? host
      FileUtils.cp(@conf_erb, host)
      FileUtils.cd(host) do |dir1|
        FileUtils.mkdir('newcerts') unless File.exists? 'newcerts'
        cname = host
        template = ERB.new(File.read(@conf_erb))
        File.open(@conf, 'w') do |fh|
          fh.write(template.result(binding))
        end
        `openssl req -new -nodes -newkey rsa:2048 -keyout #{host}.key.pem -config #{@conf} -out #{host}.csr`
        FileUtils.cp("#{host}.csr",  "../#{ca}")
        FileUtils.cd "../#{ca}" do |d|
          `make sign`
        end
        #`openssl ca -batch -config ../#{ca}/#{@conf} -in #{host}.csr -out #{host}.cert -keyfile ../#{ca}/#{@prv_key} -cert ../#{ca}/ca-cert.pem`
      end
    end
  end
end


masters = {'ca1' => 'puppetserver1', 'ca2' => 'puppetserver2'} 
ca_root = 'ca_root'
cas = masters.keys + ca_root.to_a
#Sslfun.init_certs(cas, ca_root)
#Sslfun.sign_certs(ca_root, masters.keys)
Sslfun.ssl_certs(masters)

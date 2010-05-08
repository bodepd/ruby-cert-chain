require 'fileutils'
require 'erb'



#
# initialize all cert directories.
#
class Sslfun 

  def initialize(opts)
    @prv_key = 'private/ca-key.pem'
    @csr = 'ca.csr'
    @makefile = 'Makefile'
    @conf = 'openssl.cnf'
    @bundle= 'ca-bundle.pem'
    @conf_erb = "#{@conf}.erb"
    @country = opts[:country] || 'US'
    @state = opts[:state]
    @city = opts[:city]
    @org = opts[:org]
    @unit = opts[:unit] || 'gunit'
  end

  def generate_openssl_cnf(cname, outfile, is_ca=true, conf_erb=@conf_erb)
    template = ERB.new(File.read(conf_erb))
    File.open(outfile, 'w') do |fh|
      fh.write(template.result(binding))
    end
  end

  def init_certs(ca_2s, ca_root)
    cas = ca_2s + ca_root.to_a
    cas.each do |ca|
      FileUtils.mkdir ca unless File.exists? ca
      FileUtils.cp(@makefile, ca)
      generate_openssl_cnf(ca, "#{ca}/#{@conf}")
      FileUtils.cd(ca) do |dir|
        `make init`
      end
    end
  end

  def gen_req(cas)
    cas.each do |ca|
      FileUtils.cd(ca) do |dir|
        `openssl req -new -nodes -key #{@prv_key} -config #{@conf} -out #{@csr}`
      end
    end
  end

  def sign_certs(root, ca_2)
    FileUtils.cd(root) do |dir|
      ca_2.each do |ca|
        FileUtils.cp("../#{ca}/#{@csr}", "#{ca}.csr")
        `openssl ca -batch -config #{@conf} -extfile #{@conf} -extensions v3_ca -in #{ca}.csr -out ../#{ca}/ca-cert.pem`
      end 
    end  
    `cat **/ca-cert.pem > #{@bundle}` 
  end

  def ssl_certs(hosts)
    hosts.each do |ca, host|
      FileUtils.mkdir(host) unless File.exists? host
      generate_openssl_cnf(host, "#{host}/#{@conf}", is_ca=false)
      FileUtils.cd(host) do |dir1|
        FileUtils.mkdir('newcerts') unless File.exists? 'newcerts'
        `openssl req -new -nodes -newkey rsa:2048 -keyout #{host}.key.pem -config #{@conf} -out #{host}.csr`
        FileUtils.cp("#{host}.csr",  "../#{ca}")
        FileUtils.cd "../#{ca}" do |d|
          `make sign`
        end
        #`openssl ca -batch -config ../#{ca}/#{@conf} -in #{host}.csr -out #{host}.cert -keyfile ../#{ca}/#{@prv_key} -cert ../#{ca}/ca-cert.pem`
      end
    end
  end


  def puppet_conf_ssl(host, ca)
    ssldir = `pwd`
    host_prv_key = "#{host}/#{host}.key.pem"
    host_cert = "#{ca}/#{host}.pem"
    host_pub = "#{host}/"
    ca_prv_key = "#{ca}/private/ca-key.pem"
    ca_cert = "#{ca}/ca.cert"
    ca_pub = "#{ca}/"
    template = ERB.new(File.read('puppet.conf.erb'))
    File.open('puppet.conf', 'w') do |fh|
      fh.write(template.result(binding))
    end
  end

end

opts = {
  :country => 'US',
  :state => 'Oregon',
  :city => 'Portland',
  :org => 'Puppetlabs',
  :unit => 'PS'
}
masters = {'ca1' => 'puppetserver1', 'ca2' => 'puppetserver2'} 
ca_root = 'ca_root'

fun = Sslfun.new(opts)
#fun.init_certs(masters.keys, ca_root)
#fun.gen_req(masters.keys)
#fun.sign_certs(ca_root, masters.keys)
#fun.ssl_certs(masters)
fun.puppet_conf_ssl(masters['ca1'], 'ca1')

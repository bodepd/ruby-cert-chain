require 'fileutils'
require 'erb'



#
# initialize all cert directories.
#
class Sslfun 

  def initialize(opts)
    @crl_dir = 'crl'
    @signed_cert_dir = 'signed'
    @req_dir = 'requests'
    @prv_key_dir = 'private'

    @prv_key = "ca_key.pem"
    @cert = 'ca_crt.pem'
    @csr_file = 'ca.csr'
    @serial_file = 'serial'
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

  #
  # set up dir for CA
  #
  def ca_init(dir)
    FileUtils.mkdir dir unless File.exists? dir
    # I am not sure if we need this openssl.cnf file
    generate_openssl_cnf(dir, "#{dir}/#{@conf}")
    FileUtils.cd(dir) do |d|
      unless File.exists? @serial_file
        File.open(@serial_file, 'w') do |fh|
          fh.print '01'
        end
        FileUtils.mkdir([@crl_dir, @signed_cert_dir, @req_dir, @prv_key_dir, 'newcerts']) 
        FileUtils.chmod(0770, @prv_key_dir) 
        FileUtils.touch('index')
        # touch index
        # this is what make init does : `openssl req -nodes -config openssl.cnf -days 1825 -x509 -newkey rsa:2048 -out ca-cert.pem -outform PEM`
      end
    end
  end

  #
  # create and self-sign a new CA
  #
  #
  def self_sign_ca(dir)
    FileUtils.cd(dir) do |dir|
      `openssl req -nodes -config #{@conf} -days 1825 -x509 -newkey rsa:2048 -out #{@cert} -keyout #{@prv_key} -outform PEM` 
    end
  end
    
  #
  # generates cert requests
  #
  def gen_req(ca)
    FileUtils.cd(ca) do |dir|
      `openssl req -new -nodes -newkey rsa:2048 -keyout #{@prv_key} -config #{@conf} -out #{@csr_file}`
    end
  end

  def sign_certs(ca, root)
    FileUtils.cd(root) do |d|
      conf = "-config #{@conf}"
      ext = "-extfile #{@conf}"
      key = "-keyfile #{@prv_key}"
      ca_cert = "-cert #{@cert}" 
      cert = "-out ../#{ca}/#{@cert}"
      req = "-in ../#{ca}/#{@csr_file}"
      `openssl ca -batch #{conf} #{key} #{ca_cert} #{ext} -extensions v3_ca #{req} #{cert}`
    end
  end

  def create_bundle()
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
    ca_prv_key = "#{ca}/#{prv_key}"
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

# create root CA
#fun.ca_init(ca_root)
#fun.self_sign_ca(ca_root)
# create secondary CAs
masters.each do |k, v|
  fun.ca_init(k)
  fun.gen_req(k)
  fun.sign_certs(k, ca_root)
end


#fun.gen_req(masters.keys)
#fun.sign_certs(ca_root, masters.keys)
#fun.ssl_certs(masters)
#fun.puppet_conf_ssl(masters['ca1'], 'ca1')

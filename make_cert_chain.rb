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
    @pub_key = 'ca_pub.pem'
    @cert = 'ca_crt.pem'
    @csr_file = 'ca.csr'
    @serial_file = 'serial'
    @conf = 'openssl.cnf'
    @bundle= 'ca-bundle.pem'

    @ssl_certs = 'cert'
    @ssl_prv_keys = 'private_keys'
    @ssl_pub_keys = 'public_keys'

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
      puts "openssl req -nodes -config #{@conf} -days 1825 -x509 -newkey rsa:2048 -out #{@cert} -keyout #{@prv_key} -pubkey #{@pub_key} -outform PEM" 
      `openssl req -nodes -config #{@conf} -days 1825 -x509 -newkey rsa:2048 -out #{@cert} -keyout #{@prv_key} -pubkey -outform PEM` 
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

  #
  # specify the root cert to sign your cert req
  #   - there are some pretty specific requirements for when 
  #       all of the cert files need to be stored.
  def sign_certs(ca, root)
    FileUtils.cd(root) do |d|
      conf = "-config #{@conf}"
      ext = "-extfile #{@conf}"
      key = "-keyfile #{@prv_key}"
      ca_cert = "-cert #{@cert}" 
      cert = "-out ../#{ca}/#{@cert}"
      req = "-in ../#{ca}/#{@csr_file}"
      puts "openssl ca -batch #{conf} #{key} #{ca_cert} #{ext} -extensions v3_ca #{req} #{cert}"
      `openssl ca -batch #{conf} #{key} #{ca_cert} #{ext} -extensions v3_ca #{req} #{cert}`
    end
  end


  #
  # creates a single file by concating all of the trusted certs together
  #
  def create_bundle()
    `cat **/#{@cert} > #{@bundle}` 
  end

  #
  # gen non-CA keys and have them signed by the CA
  #
  def gen_ssl_certs(ca, host)
    FileUtils.mkdir(host) unless File.exists? host
    FileUtils.mkdir("#{host}/certs") unless File.exists? "#{host}/certs"
    FileUtils.mkdir("#{host}/private_keys") unless File.exists? "#{host}/private_keys"
    FileUtils.mkdir("#{host}/public_keys") unless File.exists? "#{host}/publib_keys"
    generate_openssl_cnf(host, "#{host}/#{@conf}", is_ca=false)
    gen_req(host)
    sign_certs(host, ca)
    FileUtils.cp("#{host}/#{@prv_key}", "#{host}/private_keys/#{host}.pem")
    FileUtils.cp("#{host}/#{@cert}", "#{host}/certs/#{host}.pem")
      #FileUtils.cd(host) do |dir1|
      #  FileUtils.mkdir('newcerts') unless File.exists? 'newcerts'
      #  `openssl req -new -nodes -newkey rsa:2048 -keyout #{host}.key.pem -config #{@conf} -out #{host}.csr`
      #  FileUtils.cp("#{host}.csr",  "../#{ca}")
      #  FileUtils.cd "../#{ca}" do |d|
      #    `make sign`
      #  end
        #`openssl ca -batch -config ../#{ca}/#{@conf} -in #{host}.csr -out #{host}.cert -keyfile ../#{ca}/#{@prv_key} -cert ../#{ca}/ca-cert.pem`
  end


  def puppet_conf_ssl(host, ca)
    ssldir = `pwd`
    host_prv_key = "#{host}/#{host}.key.pem"
    host_cert = "#{ca}/#{host}.pem"
    host_pub = "#{host}/#{@pub_key}"
    ca_prv_key = "#{ca}/#{prv_key}"
    ca_cert = "#{ca}/ca.cert"
    ca_pub = "#{ca}/#{@pub_key}"
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
masters = {'ca1' => 'mypuppetmaster', 'ca2' => 'puppetserver2'} 
ca_root = 'ca_root'

fun = Sslfun.new(opts)

task = ARGV[0] || 'gen'

# by default create all of the CERT dirs.
if task =~ /gen/
  # create root CA
  fun.ca_init(ca_root)
  fun.self_sign_ca(ca_root)
  # create secondary CAs
  masters.each do |k, v|
    fun.ca_init(k)
    # generate csr's for CA
    fun.gen_req(k)
    # have root_ca sign
    fun.sign_certs(k, ca_root)
    # make puppet master ssl certs
    fun.gen_ssl_certs(k,v)
  end
  fun.create_bundle
# task to clean our dir
elsif task =~ /clean/
  masters.each do |k, v|
    if k && v
      FileUtils.rm_rf k
      FileUtils.rm_rf v
    else
      puts 'I will not wipe out all my work!!'
    end
  end
  if ca_root
    FileUtils.rm_rf ca_root
  else
    puts 'I will not wipe out all my work!!'
  end
  FileUtils.rm('ca-bundle.pem')
end
#fun.puppet_conf_ssl(masters['ca1'], 'ca1')

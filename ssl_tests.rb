require 'openssl'

def generate_self_signed # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
  key = OpenSSL::PKey::RSA.new 2048

  File.write 'files/private_key.pem', key.private_to_pem
  File.write 'files/public_key.pem', key.public_to_pem

  name = OpenSSL::X509::Name.parse '/CN=nobody/DC=example'

  cert = OpenSSL::X509::Certificate.new
  cert.version = 2
  cert.serial = 0
  cert.not_before = Time.now
  cert.not_after = Time.now + 3600

  cert.public_key = key.public_key
  cert.subject = name
  cert.issuer = name
  cert.sign key, OpenSSL::Digest.new('SHA1')

  # File.write 'files/certificate.pem', cert.to_pem
  open 'files/certificate.pem', 'w' do |io|
    io.write cert.to_pem
  end
  key
end

# key = generate_self_signed
# openssl rsa -in files/private_key.pem -pubout > files/public_key.pem
key = OpenSSL::PKey.read File.read 'files/public_key.pem'
# puts "public: #{key.public?}, private:#{key.private?}"

OpenSSL.debug = true
cert2 = OpenSSL::X509::Certificate.new File.read 'files/certificate.pem'
puts cert2.inspect
raise 'certificate can not be verified' unless cert2.verify key

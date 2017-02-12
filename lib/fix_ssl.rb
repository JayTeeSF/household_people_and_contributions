require 'open-uri'
require 'net/https'

module Net
  class HTTP
    alias_method :original_use_ssl=, :use_ssl=

    def use_ssl=(flag)
      _ssl_dir = $OPENSSLDIR || ENV['OPENSSLDIR'] || '/usr/lib/ssl/'
      _ssl_dir = '/usr/lib/ssl/' if _ssl_dir.nil? || _ssl_dir.empty?
      self.ca_file = "#{_ssl_dir}/certs/ca-certificates.crt"
      self.verify_mode = OpenSSL::SSL::VERIFY_PEER
      self.original_use_ssl = flag
    end
  end
end

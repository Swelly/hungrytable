# Modified from simple_oauth (https://github.com/laserlemon/simple_oauth)
module Hungrytable
  class RequestHeader

    ATTRIBUTE_KEYS = %w(consumer_key nonce signature_method timestamp token version).map(&:to_sym)

    def self.default_options
      {
        :nonce => OpenSSL::Random.random_bytes(16).unpack('H*')[0],
        :signature_method => 'HMAC-SHA1',
        :timestamp => Time.now.to_i.to_s,
        :version => '1.0',
        :consumer_key => Hungrytable::Config.oauth_key,
        :consumer_secret => Hungrytable::Config.oauth_secret,
        :token => ''
      }
    end

    def self.encode(value)
      URI.encode(value.to_s, /[^a-z0-9\-\.\_\~]/i)
    end

    def self.decode(value)
      URI.decode(value.to_s)
    end

    attr_reader :method, :params, :options

    def initialize(method, url, params, oauth = {})
      @method = method.to_s.upcase
      @uri = URI.parse(url.to_s)
      @uri.scheme = @uri.scheme.downcase
      @uri.normalize!
      @uri.fragment = nil
      @params = params
      @options =  self.class.default_options.merge(oauth) 
    end

    def url
      uri = @uri.dup
      uri.query = nil
      uri.to_s
    end

    def to_s
      %Q(OAuth realm="http://www.opentable.com/", #{normalized_attributes})
    end

    def valid?(secrets = {})
      original_options = options.dup
      options.merge!(secrets)
      valid = options[:signature] == signature
      options.replace(original_options)
      valid
    end

    def signed_attributes
      attributes.merge(:oauth_signature => signature)
    end

    private

    def normalized_attributes
      signed_attributes.sort_by{|k,v| k.to_s }.map{|k,v| %(#{k}="#{self.class.encode(v)}") }.join(', ')
    end

    def attributes
      ATTRIBUTE_KEYS.inject({}){|a,k| options.key?(k) ? a.merge(:"oauth_#{k}" => options[k]) : a }
    end

    def signature
      send(options[:signature_method].downcase.tr('-', '_') + '_signature')
    end

    def hmac_sha1_signature
      Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::SHA1.new, secret, signature_base)).chomp.gsub(/\n/, '')
    end

    def secret
      options.values_at(:consumer_secret, :token_secret).map{|v| self.class.encode(v) }.join('&')
    end
    alias_method :plaintext_signature, :secret

    def signature_base
      [method, url, normalized_params].map{|v| self.class.encode(v) }.join('&')
    end

    def normalized_params
      signature_params.map{|p| p.map{|v| self.class.encode(v) } }.sort.map{|p| p.join('=') }.join('&')
    end

    def signature_params
      attributes.to_a + params.to_a + url_params
    end

    def url_params
      CGI.parse(@uri.query || '').inject([]){|p,(k,vs)| p + vs.sort.map{|v| [k, v] } }
    end

    def rsa_sha1_signature
      Base64.encode64(private_key.sign(OpenSSL::Digest::SHA1.new, signature_base)).chomp.gsub(/\n/, '')
    end

    def private_key
      OpenSSL::PKey::RSA.new(options[:consumer_secret])
    end

  end
end

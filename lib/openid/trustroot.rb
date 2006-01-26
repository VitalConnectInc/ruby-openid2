require 'uri'

TOP_LEVEL_DOMAINS = 'com|edu|gov|int|mil|net|org|biz|info|name|museum|coop|aero|ac|ad|ae|af|ag|ai|al|am|an|ao|aq|ar|as|at|au|aw|az|ba|bb|bd|be|bf|bg|bh|bi|bj|bm|bn|bo|br|bs|bt|bv|bw|by|bz|ca|cc|cd|cf|cg|ch|ci|ck|cl|cm|cn|co|cr|cu|cv|cx|cy|cz|de|dj|dk|dm|do|dz|ec|ee|eg|eh|er|es|et|fi|fj|fk|fm|fo|fr|ga|gd|ge|gf|gg|gh|gi|gl|gm|gn|gp|gq|gr|gs|gt|gu|gw|gy|hk|hm|hn|hr|ht|hu|id|ie|il|im|in|io|iq|ir|is|it|je|jm|jo|jp|ke|kg|kh|ki|km|kn|kp|kr|kw|ky|kz|la|lb|lc|li|lk|lr|ls|lt|lu|lv|ly|ma|mc|md|mg|mh|mk|ml|mm|mn|mo|mp|mq|mr|ms|mt|mu|mv|mw|mx|my|mz|na|nc|ne|nf|ng|ni|nl|no|np|nr|nu|nz|om|pa|pe|pf|pg|ph|pk|pl|pm|pn|pr|ps|pt|pw|py|qa|re|ro|ru|rw|sa|sb|sc|sd|se|sg|sh|si|sj|sk|sl|sm|sn|so|sr|st|sv|sy|sz|tc|td|tf|tg|th|tj|tk|tm|tn|to|tp|tr|tt|tv|tw|tz|ua|ug|uk|um|us|uy|uz|va|vc|ve|vg|vi|vn|vu|wf|ws|ye|yt|yu|za|zm|zw'.split('|')

module OpenID

  class TrustRoot
    
    def TrustRoot._parse_url(url)
      begin
        parsed = URI::parse(url)
      rescue
        return nil
      end
      
      return [parsed.scheme, parsed.host, parsed.port, parsed.path]
    end

    def TrustRoot.parse(trust_root)
      return nil unless trust_root.instance_of?(String)

      unparsed = trust_root.dup

      # look for wildcard
      wildcard = (not trust_root.index('://*.').nil?)
      trust_root.sub!('*.', '') if wildcard

      parts = TrustRoot._parse_url(trust_root)
      return nil if parts.nil?

      proto, host, port, path = parts
      
      return nil unless ['http', 'https'].member?(proto)
      return new(unparsed, proto, wildcard, host, port, path)
    end

    def TrustRoot.check_sanity(trust_root)
      tr = TrustRoot.parse(trust_root)
      return false if tr.nil?
      return tr.sane?
    end
      

    def initialize(unparsed, proto, wildcard, host, port, path)
      @unparsed = unparsed
      @proto = proto
      @wildcard = wildcard
      @host = host
      @port = port
      @path = path
    end

    def sane?
      return true if @host == 'localhost'
      
      host_parts = @host.split('.')
      return false unless TOP_LEVEL_DOMAINS.member?(host_parts[-1])
      
      # wacky heurestic for extracting a sane tld
      host = []
      if host_parts[-1].length == 2 and host_parts.length > 1
        if host_parts[-2].length <= 3
          host = host_parts[0...-2]
        end
      elsif host_parts[-1].length == 3
        host = host_parts[0...-1]
      end
      
      return (host.length > 0)
    end
    
    def validate_url(url)
      parts = TrustRoot._parse_url(url)
      return false if parts.nil?

      proto, host, port, path = parts
      
      return false unless proto == @proto
      return false unless port == @port
      return false unless path.index(@path) == 0

      if @wildcard
        return (not host.rindex(@host).nil?)
      else
        return (host == @host)
      end
    end

  end
end

# Code extracted from https://github.com/marks/truevault.rb
require 'httparty'

module CarrierWave
  module Sharefile
    # Custom parser class for TrueVault API
    class Parser < HTTParty::Parser
      SupportedFormats.merge!({"application/octet-stream" => :octet_stream})

      def parse
        case format
          when :html
            body
          when :json
            JSON.parse(body)
          when :octet_stream
            # TODO find a better way of doing this
            # The issue is that no matter what it gets frmo TV
            # the ContentType is always octet_stream
            begin
              JSON.parse(Base64.decode64(body))
            rescue JSON::ParserError
              file = Tempfile.new('blob')
              file.binmode
              file.write(body)
              file.rewind
              file
            end
          else
            body
        end
      end

    end

    class Client
      require 'faraday'
      require 'faraday_middleware'
      require 'json'
      require 'uri'
      require 'open-uri'
      require 'tempfile'

      def initialize(client_id, client_secret, username, password)
        @client_id = client_id
        @client_secret = client_secret
        @username = username
        @password = password
        instance_variables.each do |variable|
          raise ArgumentError, "#{variable} should not be nil or blank" if instance_variable_get(variable.to_sym).to_s == ""
        end
        access_token
      end

      def access_token
        params = {
          :grant_type => :password,
          :client_id => @client_id,
          :client_secret => @client_secret,
          :username => @username,
          :password => @password
        }
        response = connection("sharefile").post 'oauth/token', params
        @access_token = response.body['access_token']
        @refresh_token = response.body['refresh_token']
      end


      def get_document(identifier)
        response = get_item_by_id(identifier)
      end

      def store_document(store_path, file)
        folder = get_item_by_path(store_path)
        upload_config = upload_file_to_folder(folder)
        res = upload_media(upload_config.body['ChunkUri'], remote_file)
      end

      private

      def upload_media(url, tmpfile)
        newline = "\r\n"
        filename = File.basename(tmpfile.path)
        boundary = "ClientTouchReceive----------#{Time.now.usec}"
           
        uri = URI.parse(url)
         
        post_body = []
        post_body << "--#{boundary}#{newline}"
        post_body << "Content-Disposition: form-data; name=\"File1\"; filename=\"#{filename}\"#{newline}"
        post_body << "Content-Type: application/octet-stream#{newline}"
        post_body << "#{newline}"
        post_body << File.read(tmpfile.path)
        post_body << "#{newline}--#{boundary}--#{newline}"
         
        request = Net::HTTP::Post.new(uri.request_uri)
        request.body = post_body.join
        request["Content-Type"] = "multipart/form-data, boundary=#{boundary}"
        request['Content-Length'] = request.body().length
       
        http = Net::HTTP.new uri.host, uri.port
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_NONE
         
        response = http.request request
        return {:response => response, :id => filename}
      end

      def upload_file_to_folder(folder)
        headers = {"Authorization" => "Bearer #{@access_token}"}
        body = {:method => 'standard', :fileName => 'testitout', :title => 'test upload', :details => 'test description'}
        response = connection.post "sf/v3/Items(#{folder.body['Id']})/Upload", body, headers
      end

      def get_item_by_path(path = '/')
        headers = {"Authorization" => "Bearer #{@access_token}"}
        response = connection.get "sf/v3/Items/ByPath?path=#{path}", {}, headers
      end

      def get_item_by_id(identifier)
        headers = {"Authorization" => "Bearer #{@access_token}"}
        response = connection.get "sf/v3/Items/(#{identifier})?includeDeleted=false", {}, headers
      end

      def connection(endpoint = "sf-api")
        Faraday.new(:url => "https://#{@subdomain}.#{endpoint}.com/") do |faraday|
          faraday.request  :url_encoded             # form-encode POST params
          faraday.use FaradayMiddleware::ParseJson
          faraday.adapter  Faraday.default_adapter  # make requests with Net::HTTP
        end
      end

    end
  end
end

module Paperclip
    module Storage
        module Ipfs
            def self.extended(base)
                base.instance_eval do
                    @ipfs_pin_endpoint = @options[:ipfs_endpoint]
                    @ipfs_gateway = @options[:ipfs_gateway]
                    @pinata_key = @options[:pinata_key]
                end
            end

            def exists?(style_name = default_style)
                true
                # path(style) ? request_get?(path(style)) : false
            end

            def request_get(file_path)
                uri = URI(filepath)
                res = Net::HTTP.get_response(uri)
                false
            end

            def flush_writes #:nodoc:
                @queued_for_write.each do |style, file|
                    retries = 0
                    begin
                        log("saving #{path(style)}")

                        write_options = {
                            content_type: file.content_type,
                        }

                        cid = pin_file(file.path)
                        instance.update_column(:file_cid, cid) if instance.respond_to?(:file_cid)
                    rescue Net::HTTPError => e
                        if e.status_code == 404
                            create_container
                            retry
                        else
                            raise
                        end
                    ensure
                        file.rewind
                    end
                end

                after_flush_writes # allows attachment to clean up temp files

                @queued_for_write = {}
            end

            def pin_file(filepath)
                uri = URI.parse(@ipfs_pin_endpoint + "pinFileToIPFS")
                boundary = "AaB03x"
                post_body = []
                # Add the file Data
                post_body << "--#{boundary}\r\n"
                post_body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(filepath)}\"\r\n"
                post_body << "Content-Type: #{MIME::Types.type_for(filepath)}\r\n\r\n"
                post_body << File.read(filepath)
                post_body << "\r\n\r\n--#{boundary}--\r\n"


                # Create the HTTP objects
                http = Net::HTTP.new(uri.host, uri.port)
                http.use_ssl = true
                request = Net::HTTP::Post.new(uri.request_uri)
                request['content-type'] = "multipart/form-data; boundary=#{boundary}"
                jwt_key = "Bearer #{@pinata_key}"
                request['Authorization'] = jwt_key
                # request['pinata_secret_api_key'] = Pinata.secret_api_key
                request.body = post_body.join

                # Send the request
                response = http.request(request)
                resp_body = JSON.parse(response.body)

                return resp_body["IpfsHash"]
            end

            def flush_deletes #:nodoc:
                # No delete in IPFS world :)
            end

            def copy_to_local_file(style, local_dest_path)
                local_file = ::File.open(local_dest_path, 'wb')
                # remote_file_str = oss_connection.get path(style)
                uri = URI(local_file)
                res = Net::HTTP.get_response(uri)
                local_file.write(res.body)
                local_file.close
            end
        end
    end
end
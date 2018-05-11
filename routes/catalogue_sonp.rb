##
## Copyright (c) 2015 SONATA-NFV, 2017 5GTANGO [, ANY ADDITIONAL AFFILIATION]
## ALL RIGHTS RESERVED.
##
## Licensed under the Apache License, Version 2.0 (the "License");
## you may not use this file except in compliance with the License.
## You may obtain a copy of the License at
##
##     http://www.apache.org/licenses/LICENSE-2.0
##
## Unless required by applicable law or agreed to in writing, software
## distributed under the License is distributed on an "AS IS" BASIS,
## WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
## See the License for the specific language governing permissions and
## limitations under the License.
##
## Neither the name of the SONATA-NFV, 5GTANGO [, ANY ADDITIONAL AFFILIATION]
## nor the names of its contributors may be used to endorse or promote
## products derived from this software without specific prior written
## permission.
##
## This work has been performed in the framework of the SONATA project,
## funded by the European Commission under Grant number 671517 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the SONATA
## partner consortium (www.sonata-nfv.eu).
##
## This work has been performed in the framework of the 5GTANGO project,
## funded by the European Commission under Grant number 761493 through
## the Horizon 2020 and 5G-PPP programmes. The authors would like to
## acknowledge the contributions of their colleagues of the 5GTANGO
## partner consortium (www.5gtango.eu).

# @see SonCatalogue
# class SonataCatalogue < Sinatra::Application
class CatalogueV1 < SonataCatalogue
  # require 'addressable/uri'

  ### SONP API METHODS ###

  # @method get_son_package_list
  # @overload get '/catalogues/son-packages/?'
  #	Returns a list of son-packages
  #	-> List many son-packages
  get '/son-packages/?' do
    params['page_number'] ||= DEFAULT_PAGE_NUMBER
    params['page_size'] ||= DEFAULT_PAGE_SIZE

    # uri = Addressable::URI.new
    # uri.query_values = params
    # puts 'params', params
    # puts 'query_values', uri.query_values
    logger.info "Catalogue: entered GET /son-packages?#{query_string}"

    # Transform 'string' params Hash into keys
    keyed_params = keyed_hash(params)
    # puts 'keyed_params', keyed_params

    # Set headers
    case request.content_type
      when 'application/x-yaml'
        headers = { 'Accept' => 'application/x-yaml', 'Content-Type' => 'application/x-yaml' }
      else
        headers = { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }
    end
    headers[:params] = params unless params.empty?

    # Get rid of :page_number and :page_size
    [:page_number, :page_size].each { |k| keyed_params.delete(k) }
    # puts 'keyed_params(1)', keyed_params

    # Do the query
    file_list = FileContainer.where(keyed_params)
    logger.info "Catalogue: leaving GET /son-packages?#{query_string} with #{file_list}"

    # Paginate results
    file_list = file_list.paginate(page_number: params[:page_number], page_size: params[:page_size])

    response = ''
    case request.content_type
      when 'application/json'
        response = file_list.to_json
      when 'application/x-yaml'
        response = json_to_yaml(file_list.to_json)
      else
        halt 415
    end
    halt 200, response
  end

  # @method get_son_package_id
  # @overload get '/catalogues/sonp-packages/:id/?'
  #	  Get a son-package
  #	  @param :id [Symbol] son-package ID
  # son-package internal database identifier
  get '/son-packages/:id/?' do
    # Dir.chdir(File.dirname(__FILE__))
    logger.debug "Catalogue: entered GET /son-packages/#{params[:id]}"
    # puts 'ID: ', params[:id]
    begin
      sonp = FileContainer.find_by({ '_id' => params[:id] })
      # p 'FileContainer FOUND'
      p 'Filename: ', sonp['package_name']
      p 'grid_fs_id: ', sonp['grid_fs_id']
    rescue Mongoid::Errors::DocumentNotFound => e
      logger.error e
      halt 404
    end

    grid_fs = Mongoid::GridFs
    grid_file = grid_fs.get(sonp['grid_fs_id'])

    # grid_file.data # big huge blob
    # temp=Tempfile.new("../#{sonp['package_name'].to_s}", 'wb')
    # grid_file.each do |chunk|
    #  temp.write(chunk) # streaming write
    # end
    ## Client file recovery
    # temp=File.new("../#{sonp['package_name']}", 'wb')
    # temp.write(grid_file.data)
    # temp.close

    logger.debug "Catalogue: leaving GET /son-packages/#{params[:id]}"
    halt 200, grid_file.data
  end

  # @method post_son_package
  # @overload post '/catalogues/son-package'
  # Post a son Package in binary-data
  post '/son-packages' do
    logger.debug 'Catalogue: entered POST /son-packages/'
    # Return if content-type is invalid
    halt 415 unless request.content_type == 'application/zip'

    # puts "headers", request.env["HTTP_CONTENT_DISPOSITION"]
    att = request.env['HTTP_CONTENT_DISPOSITION']

    unless att
      error = "HTTP Content-Disposition is missing"
      halt 400, error.to_json
    end

    filename = att.match(/filename=(\"?)(.+)\1/)[2]
    # puts "filename", filename
    # JSON.pretty_generate(request.env)

    # Reads body data
    file, errors = request.body
    halt 400, errors.to_json if errors

    ### Implemented here the MD5 checksum for the file
    # p "TEST", file.string
    # file_hash = checksum file.string
    # p "FILE HASH is: ", file_hash

    # Check duplicates
    # -> package_name
    # Check if son-package already exists in the catalogue by filename (grid-fs-name identifier)
    begin
      sonpkg = FileContainer.find_by({ 'package_name' => filename })
      json_return 200, 'Duplicated son-package Filename'
    rescue Mongoid::Errors::DocumentNotFound => e
      # Continue
    end

    # Save to DB
    # return 400, 'ERROR: Package Name not found' unless sonp.has_key?('package_name')
    # return 400, 'ERROR: Package Vendor not found' unless sonp.has_key?('package_group')
    # return 400, 'ERROR: Package Version not found' unless sonp.has_key?('package_version')

    # file = File.open('../package_example.zip')
    # Content-Disposition: attachment; filename=FILENAME

    grid_fs = Mongoid::GridFs
    grid_file = grid_fs.put(file,
                            filename: filename,
                            content_type: 'application/zip',
                            # _id: SecureRandom.uuid,
    # :file_hash   => file_hash,
    # :chunk_size   => 100 * 1024,
    # :metadata     => {'description' => "SONATA zip package"}
    )

    sonp_id = SecureRandom.uuid
    FileContainer.new.tap do |file_container|
      file_container._id = sonp_id
      file_container.grid_fs_id = grid_file.id
      file_container.package_name = filename
      file_container.md5 = grid_file.md5
      file_container.save
    end
    logger.debug "Catalogue: leaving POST /son-packages/ with #{grid_file.id}"
    response = {"uuid" => sonp_id}
    # halt 201, grid_file.id.to_json
    halt 201, response.to_json
  end

  # @method update_son_package_id
  # @overload put '/catalogues/son-packages/:id/?'
  #	Update a son-package in JSON or YAML format
  ## Catalogue - UPDATE
  put '/son-packages/:id/?' do
    # Work in progress
    halt 501
  end

  # @method delete_son_package_id
  # @overload delete '/catalogues/son-packages/:id/?'
  #	  Delete a son-package by its ID
  #	  @param :id [Symbol] son-package ID
  delete '/son-packages/:id/?' do
    unless params[:id].nil?
      logger.debug "Catalogue: entered DELETE /son-packages/#{params[:id]}"
      begin
        sonp = FileContainer.find_by('_id' => params[:id])
      rescue Mongoid::Errors::DocumentNotFound => e
        logger.error e
        json_error 404, "The son-package ID #{params[:id]} does not exist" unless sonp
      end

      # Remove files from grid
      grid_fs = Mongoid::GridFs
      grid_fs.delete(sonp['grid_fs_id'])
      sonp.destroy

      logger.debug "Catalogue: leaving DELETE /son-packages/#{params[:id]}\" with son-package #{sonp}"
      halt 200, 'OK: son-package removed'
    end
    logger.debug "Catalogue: leaving DELETE /son-packages/#{params[:id]} with 'No son-package ID specified'"
    json_error 400, 'No son-package ID specified'
  end
end

class CatalogueV2 < SonataCatalogue
  ### TGOP API METHODS ###
  #

  get '/ping/?' do
    halt 200, "{OK: 5GTANGO Catalogue is instanced}"
  end

  # @method get_tgo_package_list
  # @overload get '/catalogues/tgo-packages/?'
  #	Returns a list of tgo-packages
  #	-> List many tgo-packages
  get '/tgo-packages/?' do
    params['page_number'] ||= DEFAULT_PAGE_NUMBER
    params['page_size'] ||= DEFAULT_PAGE_SIZE

    logger.info "Catalogue: entered GET /v2/tgo-packages?#{query_string}"

    #Delete key "captures" if present
    params.delete(:captures) if params.key?(:captures)

    # Transform 'string' params Hash into keys
    keyed_params = keyed_hash(params)

    # Set headers
    case request.content_type
      when 'application/x-yaml'
        headers = { 'Accept' => 'application/x-yaml', 'Content-Type' => 'application/x-yaml' }
      else
        headers = { 'Accept' => 'application/json', 'Content-Type' => 'application/json' }
    end
    headers[:params] = params unless params.empty?
    # Get rid of :page_number and :page_size
    [:page_number, :page_size].each { |k| keyed_params.delete(k) }

    # Translate 'uuid' field to '_id'
    new_params = {}
    keyed_params.each { |k, v|
        if k == :'uuid'
          new_params.store( '_id', v)
        else
          new_params.store( k, v)
        end
    }

    # Do the query
    file_list = FileContainer.where(new_params)
    # Set total count for results
    headers 'Record-Count' => file_list.count.to_s
    logger.info "Catalogue: leaving GET /v2/tgo-packages?#{query_string} with #{file_list}"

    # Paginate results
    file_list = file_list.paginate(page_number: params[:page_number], page_size: params[:page_size])

    response = ''
    case request.content_type
      when 'application/json'
        response = file_list.to_json
      when 'application/x-yaml'
        response = json_to_yaml(file_list.to_json)
      else
        halt 415
    end
    halt 200, {'Content-type' => request.content_type}, response
  end

  # @method get_tgo_package_id
  # @overload get '/catalogues/tgo-packages/:id/?'
  #	  Get a tgo-package
  #	  @param :id [Symbol] tgo-package ID
  # tgo-package internal database identifier
  get '/tgo-packages/:id/?' do
    # Dir.chdir(File.dirname(__FILE__))
    logger.debug "Catalogue: entered GET /v2/tgo-packages/#{params[:id]}"

    # Check headers
    case request.content_type
      when 'application/zip'
        begin
          tgop = FileContainer.find_by({ '_id' => params[:id] })
          p 'Filename: ', tgop['package_name']
          p 'grid_fs_id: ', tgop['grid_fs_id']
        rescue Mongoid::Errors::DocumentNotFound => e
          logger.error e
          halt 404
        end

        grid_fs = Mongoid::GridFs
        grid_file = grid_fs.get(tgop['grid_fs_id'])

        # Set custom header with package Filename
        headers 'Filename' => (tgop['package_name'].to_s)

        # grid_file.data # big huge blob
        # temp = Tempfile.new("#{tgop['package_name'].to_s}", 'wb')
        # path_file = File.basename(temp.path)
        # grid_file.each do |chunk|
        #   temp.write(chunk) # streaming write
        # end
        # temp.close
        # Client file recovery
        # str_name = tgop['package_name'].split('.')
        # str_name[0] << "_" + Time.now.to_i.to_s.delete(" ")
        # temp = File.new("../" + str_name.join("."), 'wb')
        # temp.write(grid_file.data)
        # temp.close

        logger.debug "Catalogue: leaving GET /tgo-packages/#{params[:id]}"
        halt 200, grid_file.data
        # halt 200, "{Name => #{File.basename(temp.path)}}"

      when 'application/json'
        begin
          tgop = FileContainer.find_by('_id' => params[:id])
        rescue Mongoid::Errors::DocumentNotFound => e
          logger.error e
          json_error 404, "The tgo-package ID #{params[:id]} does not exist" unless tgop
        end

        logger.debug "Catalogue: leaving GET /v2/tgo-packages/#{params[:id]}"
        halt 200, {'Content-type' => 'application/json'}, tgop.to_json

      else
        halt 415
    end
  end

  # @method post_tgo_package
  # @overload post '/catalogues/tgo-package'
  # Post a tgo Package in binary-data
  post '/tgo-packages' do
    logger.debug "Catalogue: entered POST /v2/tgo-packages?#{query_string}"
    # Return if content-type is invalid
    halt 415 unless request.content_type == 'application/zip'

    att = request.env['HTTP_CONTENT_DISPOSITION']
    # tgop_vendor = request.env['HTTP_VENDOR']
    # tgop_name = request.env['HTTP_NAME']
    # tgop_version = request.env['HTTP_VERSION']
    # tgop_username = request.env['HTTP_USERNAME']

    unless att
      error = "HTTP Content-Disposition is missing"
      halt 400, error.to_json
    end
    if request.env['HTTP_SIGNATURE']
      signature = request.env['HTTP_SIGNATURE']
    else
      signature = nil
    end

    #Delete key "captures" if present
    params.delete(:captures) if params.key?(:captures)

    # Transform 'string' params Hash into keys
    keyed_params = keyed_hash(params)
    filename = att.match(/filename=(\"?)(.+)\1/)[2]

    # Reads body data
    file, errors = request.body
    halt 400, errors.to_json if errors

    ### Implemented here the MD5 checksum for the file
    # file_hash = checksum file.string

    # Check duplicates
    # -> vendor, name, version
    # Check if tgo-package already exists in the catalogue by vendor, name, version (name convention identifier)
    # begin
    #   tgopkg = FileContainer.find_by({ 'vendor' => tgop_vendor, 'name' => tgop_name, 'version' => tgop_version })
    #   json_return 200, 'Duplicated tgo-package Filename'
    # rescue Mongoid::Errors::DocumentNotFound => e
      # Continue
    # end
    # -> package_name
    # Check if tgo-package already exists in the catalogue by filename (grid-fs-name identifier)
    begin
      tgopkg = FileContainer.find_by({ 'package_name' => filename })
      halt 409, "Duplicated tgo-package ID => #{tgopkg['_id']}"
    rescue Mongoid::Errors::DocumentNotFound => e
      # Continue
    end

    grid_fs = Mongoid::GridFs

    grid_file = grid_fs.put(file,
                            filename: filename,
                            content_type: 'application/zip',
                            # _id: SecureRandom.uuid,
    )

    if keyed_params.key?(:username)
      username = keyed_params[:username]
    else
      username = nil
    end

    tgop_id = SecureRandom.uuid
    FileContainer.new.tap do |file_container|
      file_container._id = tgop_id
      file_container.grid_fs_id = grid_file.id
      file_container.mapping = nil
      file_container.package_name = filename
      file_container.md5 = grid_file.md5
      file_container.username = username
      file_container.signature = signature
      file_container.save
    end
    logger.debug "Catalogue: leaving POST /v2/tgo-packages/ with #{grid_file.id}"
    response = {"uuid" => tgop_id}

    # # Requirements:
    # # tgop_id, pd_name.trio, nsds_name.trio, vnfds_name.trio
    # begin
    #   Dependencies_mapping.create!(son_package_dep_mapping(file, tgop_id))
    # rescue => e
    #   logger.error e.message
    #   halt 400, {'Content-type' => 'text/plain'}, e.message
    # end
    halt 201, {'Content-type' => 'application/json'}, response.to_json
  end

  # @method post_tgo_package/mappings
  post '/tgo-packages/mappings' do
    logger.debug "Catalogue: entered POST /v2/tgo-packages/mappings"
    halt 415 unless request.content_type == 'application/x-yaml' or request.content_type == 'application/json'

    # Compatibility support for YAML content-type
    case request.content_type
      when 'application/x-yaml'
        # Validate YAML format
        mapping, errors = parse_yaml(request.body.read)
        halt 400, 'Error in parsing file' if errors

        # Translate from YAML format to JSON format
        new_mapping_json = yaml_to_json(mapping)

        # Validate JSON format
        new_mapping, errors = parse_json(new_mapping_json)

      else
        # Compatibility support for JSON content-type
        # Parses and validates JSON format
        new_mapping, errors = parse_json(request.body.read)
    end
    halt 400, 'Error in parsing file' if errors

    # Check if a package matches with the uuid with the uuid from the mapping file
    begin
      tgopkg = FileContainer.find_by('_id' => new_mapping['tgo_package_uuid'])
    rescue Mongoid::Errors::DocumentNotFound
      halt 400, "Package with {id => #{new_mapping['tgo_package_uuid']}} not found"
    end

    begin
      if tgo_package_dep_mapping(new_mapping, tgopkg)
        new_mapping.delete('tgo_package_uuid')
        tgopkg.update_attributes(mapping: new_mapping)
      end
    rescue Moped::Errors::OperationFailure => e
      json_error 400, 'ERROR: Operation of updating mappings failed'
    end
    halt 200, "Updated mappings of tgo-package with {id => #{tgopkg['_id']}}"
  end

  # @method update_son_package_id
  # @overload put '/catalogues/son-packages/:id/?'
  #	Update a son-package in JSON or YAML format
  ## Catalogue - UPDATE
  put '/tgo-packages/:id/?' do
    # Return if content-type is invalid
    halt 415 unless request.content_type == 'application/x-yaml' or request.content_type == 'application/json'

    unless params[:id].nil?
      logger.debug "Catalogue: PUT /tgo-packages/#{params[:id]}"

      #Delete key "captures" if present
      params.delete(:captures) if params.key?(:captures)

      # Transform 'string' params Hash into keys
      keyed_params = keyed_hash(params)
      if [:vendor, :name, :version].all? {|s| keyed_params.key? s }
        # if keyed_params.key?(:vendor, :name, :version)
        # Do update of Son-Package meta-data
        logger.info "Catalogue: entered PUT /tgo-packages/#{query_string}"

        # Validate tgo-package uuid
        begin
          puts 'Searching ' + params[:tgop_uuid].to_s
          tgop = FileContainer.find_by({ '_id' => params[:id] })
          p 'Filename: ', tgop['package_name']
          puts 'tgo-package is found'
        rescue Mongoid::Errors::DocumentNotFound => e
          json_error 404, 'Submitted tgo-package UUID not exists'
        end

        # begin
        #   puts 'Searching ' + params[:id].to_s
        #   tgo_dep_mapping = Dependencies_mapping.find_by({ 'tgo_package_uuid' => params[:id]})
        #   p 'Dependencies mapping ', params[:id]
        #   puts 'Dependencies mapping found'
        # rescue Mongoid::Errors::DocumentNotFound => e
        #   json_error 404, 'Submitted dependencies mapping not exists'
        # end

        # Add new son-package attribute fields
        begin
          tgop.update_attributes(vendor: keyed_params[:vendor], name: keyed_params[:name],
                                 version: keyed_params[:version])
          # tgo_dep_mapping.update('pd' => {vendor: keyed_params[:vendor], name: keyed_params[:name],
          #                                 version: keyed_params[:version]})
        rescue Moped::Errors::OperationFailure => e
          json_error 400, 'ERROR: Operation failed'
        end

        halt 200, "File tgo-package updated attributes: #{keyed_params[:vendor]}, #{keyed_params[:name]}, #{keyed_params[:version]}"
      end
    end
  end

  # @method delete_tgo_package_id
  # @overload delete '/catalogues/tgo-packages/:id/?'
  #	  Delete a tgo-package by its ID
  #	  @param :id [Symbol] tgo-package ID
  delete '/tgo-packages/:id/?' do
    unless params[:id].nil?
      logger.debug "Catalogue: entered DELETE /v2/tgo-packages/#{params[:id]}"
      begin
        tgop = FileContainer.find_by('_id' => params[:id])
      rescue Mongoid::Errors::DocumentNotFound => e
        logger.error e
        json_error 404, "The son-package ID #{params[:id]} does not exist" unless tgop
      end

      # Remove files from grid
      grid_fs = Mongoid::GridFs
      grid_fs.delete(tgop['grid_fs_id'])
      tgop.destroy

      logger.debug "Catalogue: leaving DELETE /v2/son-packages/#{params[:id]}\" with tgo-package #{tgop}"
      halt 200, 'OK: tgo-package removed'
    end
    logger.debug "Catalogue: leaving DELETE /v2/son-packages/#{params[:id]} with 'No tgo-package ID specified'"
    json_error 400, 'No tgo-package ID specified'
  end
end

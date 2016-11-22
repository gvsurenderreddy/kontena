require_relative '../../../util'

module Kontena::Cli::Stacks
  module YAML
    class Reader
      include Kontena::Util

      attr_reader :file, :raw_content, :result, :errors, :notifications, :variables, :yaml

      def initialize(file, skip_validation = false)
        require 'yaml'
        require_relative 'service_extender'
        require_relative 'validator_v3'
        require 'opto'
        require_relative 'opto/vault_resolver'
        require_relative 'opto/prompt_resolver'
        require_relative 'opto/secret_type'

        @file = file
        @raw_content = File.read(File.expand_path(file))
        @errors = []
        @notifications = []
        @skip_validation = skip_validation
        parse_yaml
      end

      # @return [Opto::Group]
      def variables
        return @variables if @variables
        yaml = ::YAML.load(interpolate(raw_content, 'filler'))
        if yaml && yaml.has_key?('variables')
          @variables = Opto::Group.new(yaml['variables'])
        else
          @variables = Opto::Group.new
        end
        @variables
      end

      ##
      # @param [String] service_name
      # @return [Hash]
      def execute(service_name = nil)
        result = {}
        Dir.chdir(File.dirname(File.expand_path(file))) do
          result[:stack]         = yaml['stack']
          result[:version]       = self.stack_version
          result[:name]          = self.stack_name
          result[:expose]        = yaml['expose']
          result[:errors]        = errors
          result[:notifications] = notifications
          result[:services]      = parse_services(service_name) unless errors.count > 0
          result[:variables]     = variables.to_h(values_only: true).reject {|k,_| variables.option(k).type == 'secret'}
        end
        result
      end

      def reload
        @errors = []
        @notifications = []
        parse_yaml
      end

      def stack_name
        yaml['stack'].split('/').last.split(':').first if yaml['stack']
      end

      def stack_version
        yaml['version'] || yaml['stack'][/:(.*)/, 1] || '1'
      end

      # @return [String]
      def raw
        read_content
      end

      private

      # A hash such as { "${MYSQL_IMAGE}" => "MYSQL_IMAGE } where the key is the
      # string to be substituted and value is the pure name part
      # @return [Hash]
      def yaml_substitutables
        @content_variables ||= raw_content.scan(/((?<!\$)\$(?!\$)\{?(\w+)\}?)/m)
      end

      def load_yaml
        @yaml = ::YAML.load(replace_dollar_dollars(interpolate(raw_content)))
      rescue Psych::SyntaxError => e
        raise "Error while parsing #{file}".colorize(:red)+ " "+e.message
      end

      # @return [Array] array of validation errors
      def validate
        result = validator.validate(yaml)
        store_failures(result)
        result
      end

      def skip_validation?
        @skip_validation == true
      end

      def store_failures(data)
        errors << { file => data[:errors] } unless data[:errors].empty?
        notifications << { file => data[:notifications] } unless data[:notifications].empty?
      end

      # @return [Kontena::Cli::Stacks::YAML::ValidatorV3]
      def validator
        @validator ||= YAML::ValidatorV3.new
      end

      ##
      # @param [String] service_name - optional service to parse
      # @return [Hash]
      def parse_services(service_name = nil)
        if service_name.nil?
          services.each do |name, config|
            services[name] = process_config(config)
          end
          services
        else
          raise ("Service '#{service_name}' not found in #{file}") unless services.has_key?(service_name)
          process_config(services[service_name])
        end
      end

      # @param [Hash] service_config
      def process_config(service_config)
        normalize_env_vars(service_config)
        merge_env_vars(service_config)
        expand_build_context(service_config)
        normalize_build_args(service_config)
        if service_config.has_key?('extends')
          service_config = extend_config(service_config)
          service_config.delete('extends')
        end
        service_config
      end

      # @return [Hash] - services from YAML file
      def services
        yaml['services']
      end

      ##
      # @param [String] text - content of YAML file
      def interpolate(text, filler = nil)
        text.gsub(/(?<!\$)\$(?!\$)\{?\w+\}?/) do |v| # searches $VAR and ${VAR} and not $$VAR
          if filler
            filler
          else
            var = v.tr('${}', '')
            opt = variables.option(var)
            if opt
              if opt.valid?
                val = opt.value
              elsif skip_validation?
                puts "Invalid value for #{var}: #{opt.errors.inspect}"
              else
                errors << { file => opt.errors }
              end
            elsif ENV[var]
              val = ENV[var]
            else
              puts "Value for #{var} is not set. Substituting with an empty string."
            end
            val
          end
        end
      end

      ##
      # @param [String] text - content of yaml file
      def replace_dollar_dollars(text)
        text.gsub('$$', '$')
      end

      # @param [Hash] service_config
      # @return [Hash] updated service config
      def extend_config(service_config)
        extended_service = extended_service(service_config['extends'])
        return unless extended_service
        filename = service_config['extends']['file']
        if filename
          parent_config = from_external_file(filename, extended_service)
        else
          raise ("Service '#{extended_service}' not found in #{file}") unless services.has_key?(extended_service)
          parent_config = process_config(services[extended_service])
        end
        ServiceExtender.new(service_config).extend_from(parent_config)
      end

      def extended_service(extend_config)
        if extend_config.kind_of?(Hash)
          extend_config['service']
        elsif extend_config.kind_of?(String)
          extend_config
        else
          nil
        end
      end

      def from_external_file(filename, service_name)
        outcome = Reader.new(filename, @skip_validation).execute(service_name)
        errors.concat outcome[:errors] unless errors.any? { |item| item.has_key?(filename) }
        notifications.concat outcome[:notifications] unless notifications.any? { |item| item.has_key?(filename) }
        outcome[:services]
      end

      # @param [Hash] options - service config
      def normalize_env_vars(options)
        if options['environment'].kind_of?(Hash)
          options['environment'] = options['environment'].map { |k, v| "#{k}=#{v}" }
        end
      end

      # @param [Hash] options
      def merge_env_vars(options)
        return options['environment'] unless options['env_file']

        options['env_file'] = [options['env_file']] if options['env_file'].kind_of?(String)
        options['environment'] = [] unless options['environment']
        options['env_file'].each do |env_file|
          options['environment'].concat(read_env_file(env_file))
        end
        options.delete('env_file')
        options['environment'].uniq! { |s| s.split('=').first }
      end

      # @param [String] path
      def read_env_file(path)
        File.readlines(path).map { |line| line.strip }.delete_if { |line| line.start_with?('#') || line.empty? }
      end

      def expand_build_context(options)
        if options['build'].kind_of?(String)
          options['build'] = File.expand_path(options['build'])
        elsif context = safe_dig(options, 'build', 'context')
          options['build']['context'] = File.expand_path(context)
        end
      end

      # @param [Hash] options - service config
      def normalize_build_args(options)
        if safe_dig(options, 'build', 'args').kind_of?(Array)
          args = options['build']['args'].dup
          options['build']['args'] = {}
          args.each do |arg|
            k,v = arg.split('=')
            options['build']['args'][k] = v
          end
        end
      end
    end
  end
end

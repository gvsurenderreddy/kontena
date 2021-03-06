require 'yaml'
require 'shellwords'
require_relative '../services/services_helper'

module Kontena::Cli::Stacks
  class ServiceGenerator
    include Kontena::Cli::Services::ServicesHelper

    attr_reader :service_config

    def initialize(service_config)
      @service_config = service_config
    end

    ##
    # @return [Hash]
    def generate
      parse_data(service_config)
    end

    private

    ##
    # @param [Hash] options
    # @return [Hash]
    def parse_data(options)
      data = {}
      data['container_count'] = options['instances']
      data['image'] = parse_image(options['image'])
      data['env'] = options['environment'] if options['environment']
      data['container_count'] = options['instances']
      data['links'] = parse_links(options['links'] || [])
      data['external_links'] = parse_links(options['external_links'] || [])
      data['ports'] = parse_stringified_ports(options['ports'] || [])
      data['memory'] = parse_memory(options['mem_limit'].to_s) if options['mem_limit']
      data['memory_swap'] = parse_memory(options['memswap_limit'].to_s) if options['memswap_limit']
      data['cpu_shares'] = options['cpu_shares'] if options['cpu_shares']
      data['volumes'] = options['volumes'] || []
      data['volumes_from'] = options['volumes_from'] || []
      data['cmd'] = Shellwords.split(options['command']) if options['command']
      data['affinity'] = options['affinity'] || []
      data['user'] = options['user'] if options['user']
      data['stateful'] = options['stateful'] == true
      data['privileged'] = options['privileged'] unless options['privileged'].nil?
      data['cap_add'] = options['cap_add'] if options['cap_add']
      data['cap_drop'] = options['cap_drop'] if options['cap_drop']
      data['net'] = options['net'] if options['net']
      data['pid'] = options['pid'] if options['pid']
      data['log_driver'] = options['log_driver'] if options['log_driver']
      data['log_opts'] = options['log_opt'] if options['log_opt'] && !options['log_opt'].empty?
      deploy_opts = options['deploy'] || {}
      data['strategy'] = deploy_opts['strategy'] if deploy_opts['strategy']
      deploy = {}
      deploy['wait_for_port'] = deploy_opts['wait_for_port'] if deploy_opts.has_key?('wait_for_port')
      deploy['min_health'] = deploy_opts['min_health'] if deploy_opts.has_key?('min_health')
      deploy['interval'] = parse_relative_time(deploy_opts['interval']) if deploy_opts.has_key?('interval')
      unless deploy.empty?
        data['deploy_opts'] = deploy
      end
      data['hooks'] = options['hooks'] || {}
      data['secrets'] = options['secrets'] if options['secrets']
      data['build'] = parse_build_options(options) if options['build']
      health_check = {}
      health_opts = options['health_check'] || {}
      health_check['protocol'] = health_opts['protocol'] if health_opts.has_key?('protocol')
      health_check['uri'] = health_opts['uri'] if health_opts.has_key?('uri')
      health_check['port'] = health_opts['port'] if health_opts.has_key?('port')
      health_check['timeout'] = health_opts['timeout'] if health_opts.has_key?('timeout')
      health_check['interval'] = health_opts['interval'] if health_opts.has_key?('interval')
      health_check['initial_delay'] = health_opts['initial_delay'] if health_opts.has_key?('initial_delay')
      unless health_check.empty?
        data['health_check'] = health_check
      end
      data
    end

    # @param [Array<String>] port_options
    # @return [Array<Hash>]
    def parse_stringified_ports(port_options)
      parse_ports(port_options).map {|p|
        {
          'ip' => p[:ip],
          'container_port' => p[:container_port],
          'node_port' => p[:node_port],
          'protocol' => p[:protocol]
        }
      }
    end

    # @param [Array<String>] link_options
    # @return [Array<Hash>]
    def parse_links(link_options)
      link_options.map{|l|
        service_name, alias_name = l.split(':')
        if service_name.nil?
          raise ArgumentError.new("Invalid link value #{l}")
        end
        alias_name = service_name if alias_name.nil?
        {
            'name' => service_name,
            'alias' => alias_name
        }
      }
    end

    # @param [Hash] options
    # @return [Hash]
    def parse_build_options(options)
      build = {}
      build['context'] = options['build'] if options['build']
      build['dockerfile'] = options['dockerfile'] if options['dockerfile']
      build
    end
  end
end

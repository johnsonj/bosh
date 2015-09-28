module Bosh::Director::DeploymentPlan
  class NetworkSettings
    include Bosh::Director::DnsHelper

    def initialize(job, desired_reservations, state, availability_zone, instance_index)
      @job = job
      @desired_reservations = desired_reservations
      @state = state
      @availability_zone = availability_zone
      @instance_index = instance_index
    end

    def to_hash
      default_properties = {}
      @job.default_network.each do |key, value|
        (default_properties[value] ||= []) << key
      end

      network_settings = {}
      @desired_reservations.each do |reservation|
        network_name = reservation.network.name
        network_settings[network_name] = reservation.network.network_settings(reservation, default_properties[network_name], @availability_zone)

        # Temporary hack for running errands.
        # We need to avoid RunErrand task thinking that
        # network configuration for errand VM differs
        # from network configuration for its Instance.
        #
        # Obviously this does not account for other changes
        # in network configuration that errand job might need.
        # (e.g. errand job desires static ip)
        if @job.starts_on_deploy?
          network_settings[network_name]['dns_record_name'] = dns_record_name(@instance_index, network_name, @job)
        end

        # Somewhat of a hack: for dynamic networks we might know IP address, Netmask & Gateway
        # if they're featured in agent state, in that case we put them into network spec to satisfy
        # ConfigurationHasher in both agent and director.
        if @state.is_a?(Hash) &&
          @state['networks'].is_a?(Hash) &&
          @state['networks'][network_name].is_a?(Hash) &&
          network_settings[network_name]['type'] == 'dynamic'
          %w(ip netmask gateway).each do |key|
            network_settings[network_name][key] = @state['networks'][network_name][key]
          end
        end
      end

      network_settings
    end

    private

    def dns_record_name(hostname, network_name, job)
      [hostname, job.canonical_name, canonical(network_name), job.deployment.canonical_name, dns_domain_name].join('.')
    end
  end
end
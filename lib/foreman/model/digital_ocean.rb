module Foreman::Model
  class DigitalOcean < ComputeResource
    
    validates_presence_of :user, :password

    def to_label
      "#{name} (#{region}-#{provider_friendly_name})"
    end

    def provided_attributes
      super.merge({ :ip => :public_ip_address })
    end

    def self.model_name
      ComputeResource.model_name
    end

    def capabilities
      [:image]
    end

    def vms
      client.servers
    end

    def find_vm_by_uuid uuid
      client.servers.get(uuid)
    rescue Fog::Compute::AWS::Error
      raise(ActiveRecord::RecordNotFound)
    end

    def create_vm args = { }
      args = vm_instance_defaults.merge(args.to_hash.symbolize_keys)
      if (name = args[:name])
        args.merge!(:tags => {:Name => name})
      end
      if (image_id = args[:image_id])
        image = images.find_by_uuid(image_id)
        iam_hash = image.iam_role.present? ? {:iam_instance_profile_name => image.iam_role} : {}
        args.merge!(iam_hash)
      end
      super(args)
    end

    def security_groups
      client.security_groups.map(&:name)
    end

    def regions
      return [] if user.blank? or password.blank?
      @regions ||= client.list_regions.body["regions"].map { |r| r["name"] }
    end

    def zones
      @zones ||= client.describe_availability_zones.body["availabilityZoneInfo"].map { |r| r["zoneName"] if r["regionName"] == region }.compact
    end

    def flavors
      client.flavors
    end

    def test_connection
      super
      errors[:user].empty? and errors[:password] and regions
    rescue Fog::Compute::AWS::Error => e
      errors[:base] << e.message
    end

    def region= value
      self.url = value
    end

    def region
      @region ||= url.present? ? url : nil
    end

    def console(uuid)
      vm = find_vm_by_uuid(uuid)
      vm.console_output.body.merge(:type=>'log', :name=>vm.name)
    end

    def destroy_vm(uuid)
      vm = find_vm_by_uuid(uuid)
      vm.destroy if vm
      true
    end

    # not supporting update at the moment
    def update_required?(old_attrs, new_attrs)
      false
    end

    private

    def client
      @client ||= ::Fog::Compute.new(:provider => "DigitalOcean", :digitalocean_client_id => user, :digitalocean_api_key => password)
    end

    def vm_instance_defaults
      {
        :flavor_id => "512",
        :name      => "foreman-#{Foreman.uuid}"
      }
    end
  end
end

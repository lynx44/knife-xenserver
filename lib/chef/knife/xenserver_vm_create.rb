#
# Author:: Sergio Rubio (<rubiojr@bvox.net>)
# Copyright:: Copyright (c) 2012 BVox S.L.
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/knife/xenserver_base'
require 'singleton'

class Chef
  class Knife
    class XenserverVmCreate < Knife

      include Knife::XenserverBase

      deps do
        require 'readline'
        require 'chef/json_compat'
        require 'chef/knife/bootstrap'
        Chef::Knife::Bootstrap.load_deps
      end

      banner "knife xenserver vm create (options)"

      option :vm_template,
        :long => "--vm-template NAME",
        :description => "The Virtual Machine Template to use"
      
      option :vm_name,
        :long => "--vm-name NAME",
        :description => "The Virtual Machine name"

      option :vm_hostname,
             :long => "--vm-hostname HOSTNAME",
             :description => "The Virtual Machine hostname"

      option :vm_tags,
        :long => "--vm-tags tag1[,tag2..]",
        :description => "Comma separated list of tags"
      
      option :chef_node_name,
        :short => "-N NAME",
        :long => "--node-name NAME",
        :description => "The Chef node name for your new node"
      
      option :vm_memory,
        :long => "--vm-memory AMOUNT",
        :description => "The memory limits of the Virtual Machine",
        :default => '512'
      
      option :vm_cpus,
        :long => "--vm-cpus AMOUNT",
        :description => "The VCPUs of the Virtual Machine",
        :default => '1'

      option :bootstrap_version,
        :long => "--bootstrap-version VERSION",
        :description => "The version of Chef to install",
        :proc => Proc.new { |v| Chef::Config[:knife][:bootstrap_version] = v }

      option :distro,
        :short => "-d DISTRO",
        :long => "--distro DISTRO",
        :description => "Bootstrap a distro using a template; default is 'ubuntu10.04-gems'",
        :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d },
        :default => "ubuntu10.04-gems"

      option :template_file,
        :long => "--template-file TEMPLATE",
        :description => "Full path to location of template to use",
        :proc => Proc.new { |t| Chef::Config[:knife][:template_file] = t },
        :default => false

      option :run_list,
        :short => "-r RUN_LIST",
        :long => "--run-list RUN_LIST",
        :description => "Comma separated list of roles/recipes to apply",
        :proc => lambda { |o| o.split(/[\s,]+/) },
        :default => []
        
      option :first_boot_attributes,
        :short => "-j JSON_ATTRIBS",
        :long => "--json-attributes",
        :description => "A JSON string to be added to the first run of chef-client",
        :proc => lambda { |o| JSON.parse(o) },
        :default => {}

      option :ssh_user,
        :short => "-x USERNAME",
        :long => "--ssh-user USERNAME",
        :description => "The ssh username; default is 'root'",
        :default => "root"
      
      option :ssh_password,
        :short => "-P PASSWORD",
        :long => "--ssh-password PASSWORD",
        :description => "The ssh password"

      option :use_sudo_password,
        :long => "--use-sudo-password PASSWORD",
        :description => "The sudo password on the vm"

      option :identity_file,
        :short => "-i IDENTITY_FILE",
        :long => "--identity-file IDENTITY_FILE",
        :description => "The SSH identity file used for authentication"
      
      option :host_key_verify,
        :long => "--[no-]host-key-verify",
        :description => "Disable host key verification",
        :boolean => true,
        :default => true
      
      option :skip_bootstrap,
        :long => "--skip-bootstrap",
        :description => "Skip bootstrap process (Deploy only mode)",
        :boolean => true,
        :default => false,
        :proc => Proc.new { true }
      
      option :keep_template_networks,
        :long => "--keep-template-networks",
        :description => "Do no remove template inherited networks (VIFs)",
        :boolean => true,
        :default => false,
        :proc => Proc.new { true }
      
      option :batch,
        :long => "--batch script.yml",
        :description => "Use a batch file to deploy multiple VMs",
        :default => nil
      
      option :vm_networks,
        :short => "-N network[,network..]",
        :long => "--vm-networks",
        :description => "Network where nic is attached to"

      option :mac_addresses,
        :short => "-M mac[,mac..]",
        :long => "--mac-addresses",
        :description => "Mac address list",
        :default => nil

      option :vm_ip,
        :long => '--vm-ip IP',
        :description => 'IP address to set in xenstore'

      option :vm_gateway,
        :long => '--vm-gateway GATEWAY',
        :description => 'Gateway address to set in xenstore'

      option :vm_netmask,
        :long => '--vm-netmask NETMASK',
        :description => 'Netmask to set in xenstore'

      option :vm_dns,
        :long => '--vm-dns NAMESERVER',
        :description => 'DNS servers to set in xenstore'

      option :vm_domain,
        :long => '--vm-domain DOMAIN',
        :description => 'DOMAIN of host to set in xenstore'

      option :vm_domain_username,
             :long => '--vm-domain-username DOMAINUSERNAME',
             :description => 'DOMAINUSERNAME of host to set in xenstore'

      option :vm_domain_password,
             :long => '--vm-domain-password DOMAINPASSWORD',
             :description => 'DOMAINPASSWORD of host to set in xenstore'

      option :extra_vdis,
        :long => '--extra-vdis "SR name":size1[,"SR NAME":size2,..]',
        :description => 'Create and attach additional VDIs (size in MB)'

      option :environment,
        :short => '-E ENV',
        :long => '--environment ENV',
        :description => 'Sets the chef environment to add the vm to'

      def tcp_test_ssh(hostname)
        tcp_socket = TCPSocket.new(hostname, 22)
        readable = IO.select([tcp_socket], nil, nil, 5)
        if readable
          Chef::Log.debug("sshd accepting connections on #{hostname}, banner is #{tcp_socket.gets}")
          yield
          true
        else
          false
        end
      rescue Errno::ETIMEDOUT, Errno::EPERM
        false
      rescue Errno::ECONNREFUSED, Errno::EHOSTUNREACH, Errno::ENETUNREACH
        sleep 2
        false
      ensure
        tcp_socket && tcp_socket.close
      end

      def run
        $stdout.sync = true

        unless config[:vm_template]
          raise "You have not provided a valid template name. (--vm-template)"
        end
        
        vm_name = config[:vm_name]
        if not vm_name
          raise "Invalid Virtual Machine name (--vm-name)"
        end

        unless config[:vm_gateway]
          if config[:vm_ip]
            last_octet = Chef::Config[:knife][:xenserver_default_vm_gateway_last_octet] || 1
            config[:vm_gateway] = config[:vm_ip].gsub(/\.\d+$/, ".#{last_octet}")
          end
        end

        config[:vm_netmask] ||= Chef::Config[:knife][:xenserver_default_vm_netmask]
        config[:vm_dns] ||= Chef::Config[:knife][:xenserver_default_vm_dns]
        config[:vm_domain] ||= Chef::Config[:knife][:xenserver_default_vm_domain]

        template = connection.servers.templates.find do |s| 
          (s.name == config[:vm_template]) or (s.uuid == config[:vm_template])
        end

        if template.nil?
          raise "Template #{config[:vm_template]} not found."
        end

        puts "Creating VM #{config[:vm_name].yellow}..."
        puts "Using template #{template.name.yellow} [uuid: #{template.uuid}]..."
        
        vm = connection.servers.new :name => config[:vm_name],
                                    :template_name => config[:vm_template]
        vm.save :auto_start => false
        # Useful for the global exception handler
        @created_vm = vm

        if not config[:keep_template_networks]
          vm.vifs.each do |vif|
            vif.destroy
          end 
          vm.reload
        end
        if config[:vm_networks]
          create_nics(config[:vm_networks], config[:mac_addresses], vm)
        end
        mem = (config[:vm_memory].to_i * 1024 * 1024).to_s
        vm.set_attribute 'memory_limits', mem, mem, mem, mem
        vm.set_attribute 'VCPUs_max', config[:vm_cpus]
        vm.set_attribute 'VCPUs_at_startup', config[:vm_cpus]

        # network configuration through xenstore
        attrs = {}
        if ip_addresses.length > 0 then
          ips = ip_addresses
          gateways = config[:vm_gateway].split(',')
          netmasks = config[:vm_netmask].split(',')

          if !(ips.length == netmasks.length) then
            puts "Network configuration values do not match. You must provide the same number of IP Addresses, Gateways and Netmasks."
            return
          end

          ips.each_with_index do |ip, index|
            (attrs["vm-data/ifs/#{index}/ip"] = ips[index])
            (attrs["vm-data/ifs/#{index}/gateway"] = gateways[index]) if gateways.length > index
            (attrs["vm-data/ifs/#{index}/netmask"] = netmasks[index])
          end
        end
        if config[:vm_dns] then
          nameservers = config[:vm_dns].split(',')
          (attrs['vm-data/nameservers'] = nameservers.join(' '))
          (attrs['vm-data/nameserver1'] = config[:vm_dns]) unless nameservers.length == 0
          (attrs['vm-data/nameserver2'] = config[:vm_dns]) unless nameservers.length <= 1
          (attrs['vm-data/nameserver3'] = config[:vm_dns]) unless nameservers.length <= 2
        end

        (attrs['vm-data/hostname'] = config[:vm_hostname]) if config[:vm_hostname]
        (attrs['vm-data/domain'] = config[:vm_domain]) if config[:vm_domain]
        (attrs['vm-data/domainusername'] = config[:vm_domain_username]) if config[:vm_domain_username]
        (attrs['vm-data/domainpassword'] = config[:vm_domain_password]) if config[:vm_domain_password]
        if !attrs.empty?
          puts "Adding attributes to xenstore..."
          vm.set_attribute 'xenstore_data', attrs
        end

        if config[:vm_tags]
          vm.set_attribute 'tags', config[:vm_tags].split(',')
        end

        vm.provision
        # Create additional VDIs (virtual disks)
        create_extra_vdis(vm)
        vm.start
        vm.reload

        puts "#{ui.color("VM Name", :cyan)}: #{vm.name}"
        puts "#{ui.color("VM Memory", :cyan)}: #{bytes_to_megabytes(vm.memory_static_max)} MB"

        if !config[:skip_bootstrap]
          # wait for it to be ready to do stuff
          print "\n#{ui.color("Waiting server... ", :magenta)}"
          timeout = 180
          found = connection.servers.all.find { |v| v.name == vm.name }
          servers = connection.servers
          if config[:vm_ip]
            vm.refresh
            print "\nTrying to #{'SSH'.yellow} to #{ip_addresses[0].yellow}... "
            print(".") until tcp_test_ssh(ip_addresses[0]) do
              sleep @initial_sleep_delay ||= 10; puts(" done")
              @ssh_ip = config[:vm_ip]
            end
          else
            loop do
              begin
                vm.refresh
                if not vm.guest_metrics.nil? and not vm.guest_metrics.networks.empty?
                  networks = []
                  vm.guest_metrics.networks.each do |k,v|
                    networks << v
                  end
                  networks = networks.join(",")
                  puts
                  puts "\n#{ui.color("Server IPs:", :cyan)} #{networks}"
                  break
                end
              rescue Fog::Errors::Error
                print "\r#{ui.color('Waiting a valid IP', :magenta)}..." + "." * (100 - timeout)
              end
              sleep 1
              timeout -= 1
              if timeout == 0
                puts
                raise "Timeout trying to reach the VM. Couldn't find the IP address."
              end
            end
            print "\n#{ui.color("Waiting for sshd... ", :magenta)}"
            vm.guest_metrics.networks.each do |k,v|
              print "\nTrying to #{'SSH'.yellow} to #{v.yellow}... "
              print(".") until tcp_test_ssh(v) do
                sleep @initial_sleep_delay ||= 10; puts(" done")
                @ssh_ip = v
              end
              break if @ssh_ip
            end
          end

          bootstrap_for_node(vm).run 
          puts "\n"
          puts "#{ui.color("Name", :cyan)}: #{vm.name}"
          puts "#{ui.color("IP Address", :cyan)}: #{@ssh_ip}"
          puts "#{ui.color("Environment", :cyan)}: #{config[:environment] || '_default'}"
          puts "#{ui.color("Run List", :cyan)}: #{config[:run_list].join(', ')}"
          puts "#{ui.color("Done!", :green)}"
        else
          ui.warn "Skipping bootstrapping as requested."
        end

      end

      def ip_addresses
        config[:vm_ip] ? config[:vm_ip].split(',') : []
      end

      def bootstrap_for_node(vm)
        bootstrap = Chef::Knife::Bootstrap.new
        bootstrap.name_args = [@ssh_ip]
        bootstrap.config[:run_list] = config[:run_list]
        bootstrap.config[:first_boot_attributes] = config[:first_boot_attributes]
        bootstrap.config[:ssh_user] = config[:ssh_user] 
        bootstrap.config[:identity_file] = config[:identity_file]
        bootstrap.config[:chef_node_name] = config[:chef_node_name] || vm.name
        bootstrap.config[:bootstrap_version] = locate_config_value(:bootstrap_version)
        bootstrap.config[:distro] = locate_config_value(:distro)
        # bootstrap will run as root...sudo (by default) also messes up Ohai on CentOS boxes
        bootstrap.config[:use_sudo] = true unless config[:ssh_user] == 'root'
        bootstrap.config[:template_file] = locate_config_value(:template_file)
        bootstrap.config[:environment] = config[:environment]
        bootstrap.config[:host_key_verify] = config[:host_key_verify]
        bootstrap.config[:ssh_password] = config[:ssh_password]
        bootstrap.config[:use_sudo_password] = config[:use_sudo_password]
        bootstrap
      end

      def create_extra_vdis(vm)
        # Return if no extra VDIs were specified
        return unless config[:extra_vdis]
        count = 0

        vdis = config[:extra_vdis].strip.chomp.split(',')
        vdis.each do |vdi|
          count += 1
          # if options is "Storage Repository":size
          if vdi =~ /.*:.*/
            sr, size = vdi.split(':')
          else #only size was specified
            sr = nil
            size = vdi
          end
          unless size =~ /^\d+$/
            raise "Invalid VDI size. Not numeric."
          end
          # size in bytes
          bsize = size.to_i * 1024 * 1024

          # If the storage repository has been omitted,
          # use the default SR from the first pool, othewise
          # find the SR required
          if sr.nil?
            sr = connection.pools.first.default_sr 
            ui.warn "No storage repository defined for extra VDI #{count}."
            ui.warn "Using default SR from Pool: #{sr.name}"
          else
            found = connection.storage_repositories.find { |s| s.name == sr }
            unless found
              raise "Storage Repository #{sr} not available"
            end
            sr = found
          end
          
          # Name of the VDI
          name = "#{config[:vm_name]}-extra-vdi-#{count}"

          puts "Creating extra VDI (#{size} MB, #{name}, #{sr.name || 'Default SR'})"
          vdi = connection.vdis.create :name => name,
                                       :storage_repository => sr,
                                       :description => name,
                                       :virtual_size => bsize.to_s

          begin
            # Attach the VBD
            connection.vbds.create :server => vm, 
                                   :vdi => vdi,
                                   :userdevice => count.to_s,
                                   :bootable => false
          rescue => e
            ui.error "Could not attach the VBD to the server"
            # Try to destroy the VDI
            vdi.destroy rescue nil
            raise e
          end
        end
      end
      
      def create_nics(networks, macs, vm)
        net_arr = networks.split(/,/).map { |x| { :network => x } }
        nics = []
        if macs
          mac_arr = macs.split(/,/)
          nics = net_arr.each_index { |x| net_arr[x][:mac_address] = mac_arr[x] if mac_arr[x] and !mac_arr[x].empty? }
        else
          nics = net_arr
        end
        networks = connection.networks
        highest_device = -1
        vm.vifs.each { |vif| highest_device = vif.device.to_i if vif.device.to_i > highest_device }
        nic_count = 0
        nics.each do |n|
          net = networks.find { |net| net.name == n[:network] }
          if net.nil?
            raise "Network #{n[:network]} not found"
          end
          nic_count += 1
          c = {
           'MAC_autogenerated' => n[:mac_address].nil? ? 'True':'False',
           'VM' => vm.reference,
           'network' => net.reference,
           'MAC' => n[:mac_address] || '',
           'device' => (highest_device + nic_count).to_s,
           'MTU' => '0',
           'other_config' => {},
           'qos_algorithm_type' => 'ratelimit',
           'qos_algorithm_params' => {}
          }
          connection.create_vif_custom c
        end
      end

    end
  end
end

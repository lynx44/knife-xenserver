#
# Author:: Sergio Rubio (<rubiojr@bvox.net>)
# Copyright:: Copyright (c) 2012 Sergio Rubio
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
require 'erb'

module VmNetworkReader
  def get_addresses
    @connection.servers.all.select{ |vm| vm.name == config[:vm_name]}.map { |vm| vm.guest_metrics.networks.map { |k,v| v} }.flatten
  end

  # def verify_interfaces(interfaces)
  #   current = get_addresses
  #
  #   not_found_addresses = (interfaces.map { |interface| interface.ipaddress }) - current
  #   puts not_found_addresses
  #
  #   not_found_addresses.empty?
  # end
end

class Chef
  class Knife
    class XenserverVmConfigure < Knife
      include VmNetworkReader

      include Knife::XenserverBase

      banner "knife xenserver vm configure (options)"

      option :vm_name,
             :long => "--vm-name NAME",
             :description => "The template name"

      option :username,
             :long => "--username USERNAME",
             :description => "The Username for the machine"

      option :password,
             :long => "--password PASSWORD",
             :description => "The Password for the machine"

      option :use_sudo_password,
             :long => "--use-sudo-password PASSWORD",
             :description => "The sudo password on the vm"

      option :distro,
             :short => "-d DISTRO",
             :long => "--distro DISTRO",
             :description => "Bootstrap a distro using a template; default is 'ubuntu10.04-gems'",
             :proc => Proc.new { |d| Chef::Config[:knife][:distro] = d },
             :default => "ubuntu10.04-gems"

      option :vm_networks,
             :short => "-N network[,network..]",
             :long => "--vm-networks",
             :description => "Network where nic is attached to"

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

      def run
        @connection = connection
        get_addresses().each do |ipaddress|
          begin
            puts "attempting to connect to #{ipaddress}"
            host = create_host(nil, ipaddress)
            host.interfaces = interfaces
            host.configure
            break
          rescue Exception => e
            puts e
            puts "could not connect to #{ipaddress}"
          end
        end
      end

      private
      def create_host(distro, ipaddress)
        DebianHost.new(ipaddress, config, connection)
      end

      def interfaces
        @interfaces = []
        ip_addresses.each_with_index do |address, index|
          interface = Interface.new
          interface.ipaddress = address
          interface.netmask = netmasks[index]
          interface.gateway = gateways.length > index ? gateways[index] : nil
          interface.nameservers = dns.length > 0 ? dns : nil
          @interfaces.push(interface)
        end

        @interfaces
      end

      def ip_addresses
        config[:vm_ip] ? config[:vm_ip].split(',') : []
      end

      def netmasks
        config[:vm_netmask] ? config[:vm_netmask].split(',') : []
      end

      def gateways
        config[:vm_gateway] ? config[:vm_gateway].split(',') : []
      end

      def dns
        config[:vm_dns] ? config[:vm_dns].split(',') : []
      end

      class Interface
        attr_accessor :ipaddress,
                      :netmask,
                      :gateway,
                      :nameservers
      end

      module TemplateProvider
        attr_accessor :interfaces

        def generate_text_from_template(local_file_path)
          erb_contents = File.open(File.expand_path(local_file_path, __FILE__)).read
          contents = ERB.new(erb_contents).result(self.instance_eval { binding })
          puts "ERB Contents:"
          puts contents
          contents
        end

        def generate_file_name()
          (0...8).map { (65 + rand(26)).chr }.join
        end
      end

      module SshHost
        include TemplateProvider

        def ssh_run(command)
          puts command
          output = ''
          @ssh.run(command).each { |line|
            puts line.stdout
            output += line.stdout
          }

          output
        end
      end

      class DebianHost
        include SshHost
        include VmNetworkReader

        def initialize(ipaddress, config, connection)
          @ssh = Fog::SSH.new(ipaddress, config[:username], {:password => config[:password]})
          @connection = connection
        end

        def configure()
          remote_file_path = '/etc/network/interfaces'
          local_file_path = '../files/debian/interfaces.erb'
          contents = generate_text_from_template(local_file_path)
          temp_file_name = "~/#{generate_file_name}"
          copy_command = "sudo printf \"#{contents.gsub(/\n/, '\\n')}\" > #{temp_file_name} && sudo mv #{temp_file_name} #{remote_file_path}"
          ssh_run(copy_command)
          begin
            t = Thread.start { ssh_run('sudo /etc/init.d/networking restart') }
            # wait for the above command to complete. it hangs since we're restarting networking
            sleep(5)
            Thread.kill(t)
          end
        end
      end
    end
  end
end


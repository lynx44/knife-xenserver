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

class Chef
  class Knife
    class XenserverVmConfigure < Knife

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

      def run
        ssh = Fog::SSH.new(config[:fqdn], config[:username], {:password => config[:password]})
        # puts ssh.run('ls')[0].stdout
        connection.servers.all.each { |vm| puts vm.name }
      end

    end
  end
end

#
# Cookbook Name:: apache2
# Recipe:: default
#
# Copyright 2008-2013, Opscode, Inc.
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

package 'apache2' do
  package_name node['apache']['package']
end

service 'apache2' do
  case node['platform_family']
  when 'rhel', 'fedora', 'suse'
    service_name 'httpd'
    # If restarted/reloaded too quickly httpd has a habit of failing.
    # This may happen with multiple recipes notifying apache to restart - like
    # during the initial bootstrap.
    restart_command '/sbin/service httpd restart && sleep 1'
    reload_command '/sbin/service httpd reload && sleep 1'
  when 'debian'
    service_name 'apache2'
    restart_command '/usr/sbin/invoke-rc.d apache2 restart && sleep 1'
    reload_command '/usr/sbin/invoke-rc.d apache2 reload && sleep 1'
  when 'arch'
    service_name 'httpd'
  when 'freebsd'
    service_name 'apache22'
  end
  supports [:start, :restart, :reload, :status]
  action [:enable, :start]
end

%w(sites-available sites-enabled mods-available mods-enabled conf-available conf-enabled).each do |dir|
  directory "#{node['apache']['dir']}/#{dir}" do
    mode '0755'
    owner 'root'
    group node['apache']['root_group']
  end
end

file "#{node['apache']['dir']}/sites-available/default" do
  action :delete
  backup false
end

file "#{node['apache']['dir']}/sites-enabled/000-default" do
  action :delete
  backup false
end

directory "#{node['apache']['dir']}/conf.d" do
  action :delete
  recursive true
end

if platform_family?('rhel', 'fedora', 'arch', 'suse', 'freebsd')
  directory node['apache']['log_dir'] do
    mode '0755'
  end

  package node['apache']['perl_pkg']

  cookbook_file '/usr/local/bin/apache2_module_conf_generate.pl' do
    source 'apache2_module_conf_generate.pl'
    mode '0755'
    owner 'root'
    group node['apache']['root_group']
  end

  execute 'generate-module-list' do
    command "/usr/local/bin/apache2_module_conf_generate.pl #{node['apache']['lib_dir']} #{node['apache']['dir']}/mods-available"
    action :nothing
  end

  %w(a2ensite a2dissite a2enmod a2dismod a2enconf a2disconf).each do |modscript|
    template "/usr/sbin/#{modscript}" do
      source "#{modscript}.erb"
      mode '0700'
      owner 'root'
      group node['apache']['root_group']
      action :create
    end
  end

  # enable mod_deflate for consistency across distributions
  include_recipe 'apache2::mod_deflate'
end

if platform_family?('freebsd')

  directory "#{node['apache']['dir']}/Includes" do
    action :delete
    recursive true
  end

  directory "#{node['apache']['dir']}/extra" do
    action :delete
    recursive true
  end
end

if node['apache']['version'] == '2.2' && platform_family?('debian')
  %w(a2enconf a2disconf).each do |modscript|
    template "/usr/sbin/#{modscript}" do
      source "#{modscript}.erb"
      mode '0700'
      owner 'root'
      group node['apache']['root_group']
      action :create
    end
  end
end

%W(
  #{node['apache']['dir']}/ssl
  #{node['apache']['cache_dir']}
).each do |path|
  directory path do
    mode '0755'
    owner 'root'
    group node['apache']['root_group']
  end
end

# Set the preferred execution binary - prefork or worker
template '/etc/sysconfig/httpd' do
  source 'etc-sysconfig-httpd.erb'
  owner 'root'
  group node['apache']['root_group']
  mode '0644'
  notifies :restart, 'service[apache2]', :delayed
  only_if  { platform_family?('rhel', 'fedora') }
end

template 'apache2.conf' do
  if platform_family?('rhel', 'fedora', 'arch', 'freebsd')
    path "#{node['apache']['conf_dir']}/httpd.conf"
  elsif platform_family?('debian')
    path "#{node['apache']['conf_dir']}/apache2.conf"
  end
  action :create
  source 'apache2.conf.erb'
  owner 'root'
  group node['apache']['root_group']
  mode '0644'
  notifies :reload, 'service[apache2]', :delayed
end

%w(security charset).each do |conf|
  apache_conf conf do
    enable true
  end
end

apache_conf 'ports' do
  enable false
  conf_path node['apache']['dir']
end

if node['apache']['version'] == '2.4'
  # in apache 2.4 on ubuntu, you need to explicitly load the mpm you want to use, it is no longer compiled in.
  include_recipe "apache2::mpm_#{node['apache']['mpm']}"
end

node['apache']['default_modules'].each do |mod|
  module_recipe_name = mod =~ /^mod_/ ? mod : "mod_#{mod}"
  include_recipe "apache2::#{module_recipe_name}"
end

web_app 'default' do
  template 'default-site.conf.erb'
  path "#{node['apache']['dir']}/sites-available/default.conf"
  enable node['apache']['default_site_enabled']
end

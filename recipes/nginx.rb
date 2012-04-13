service 'apache2' do
  action :stop
end


via_pkg = value_for_platform(
  %w(centos redhat scientific fedora) => {
    %w(5.0 5.1 5.2 5.3 5.4 5.5 5.6 5.7 5.8) => false,
    "default" => true
  },
  "default" => true
)

unless(via_pkg)
  node.set[:nginx][:install_method] = 'source'
  node.set['nagios']['nginx_dispatch'] = :both
end
include_recipe "nginx"

%w(default 000-default).each do |disable_site|
  nginx_site disable_site do
    enable false
    notifies :reload, "service[nginx]"
  end
end

if node['public_domain']
  public_domain = node['public_domain']
else
  public_domain = node['domain']
end

case dispatch_type = node['nagios']['nginx_dispatch'].to_sym
when :cgi
  node.set[:nginx_simplecgi][:cgi] = true
  include_recipe 'nginx_simplecgi::setup'
when :php
  node.set[:nginx_simplecgi][:php] = true
  include_recipe 'nginx_simplecgi::setup'
when :both
  node.set[:nginx_simplecgi][:php] = true
  node.set[:nginx_simplecgi][:cgi] = true
  include_recipe 'nginx_simplecgi::setup'
else
  Chef::Log.warn "NAGIOS: NGINX setup does not have a dispatcher provided"
end

template File.join(node['nginx']['dir'], 'sites-available', 'nagios3.conf') do
  source 'nginx.conf.erb'
  mode 0644
  pem = File.join(
    node['nagios']['conf_dir'],
    'certificates',
    'nagios-server.pem'
  )
  variables(
    :public_domain => public_domain,
    :listen_port => node['nagios']['http_port'],
    :https => node['nagios']['https'],
    :cert_file => pem,
    :cert_key => pem,
    :docroot => node['nagios']['docroot'],
    :log_dir => node['nagios']['log_dir'],
    :fqdn => node['fqdn'],
    :chef_env =>  node.chef_environment == '_default' ? 'default' : node.chef_environment,
    :htpasswd_file => File.join(
      node['nagios']['conf_dir'],
      'htpasswd.users'
    ),
    :cgi => [:cgi, :both].include?(dispatch_type.to_sym),
    :php => [:php, :both].include?(dispatch_type.to_sym)
  )
  if(::File.symlink?(File.join(node['nginx']['dir'], 'sites-enabled', 'nagios3.conf')))
    notifies :reload, 'service[nginx]', :immediately
  end
end

nginx_site "nagios3.conf" do
  notifies :reload, "service[nginx]"
end


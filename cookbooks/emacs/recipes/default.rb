#
# Cookbook Name:: emacs
# Recipe:: default
#

execute "install_emacs" do
  command "emerge app-editors/emacs"
  not_if { FileTest.exists?("/usr/bin/emacs-22") }
end

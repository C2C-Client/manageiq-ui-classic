class ApplicationHelper::Button::NewCloudTenant < ApplicationHelper::Button::ButtonNewDiscover
  def disabled?
    super || ManageIQ::Providers::Openstack::CloudManager.count == 0 || ManageIQ::Providers::Telefonica::CloudManager.count == 0
  end
end

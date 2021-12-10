class ApplicationHelper::Button::NewCloudTenant < ApplicationHelper::Button::ButtonNewDiscover
  def disabled?
    # Click2Cloud: Added telefonica cloudmanager condition
    super || ManageIQ::Providers::Openstack::CloudManager.count == 0 || ManageIQ::Providers::Telefonica::CloudManager.count == 0
  end
end

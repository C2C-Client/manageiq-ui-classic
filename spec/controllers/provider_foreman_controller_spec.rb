describe ProviderForemanController do
  render_views

  let(:tags) { ["/managed/quota_max_memory/2048"] }
  before do
    allow(controller).to receive(:data_for_breadcrumbs).and_return({})
    @zone = EvmSpecHelper.local_miq_server.zone
    Tag.find_or_create_by(:name => tags.first)

    @provider = ManageIQ::Providers::Foreman::Provider.create(:name => "testForeman", :url => "10.8.96.102", :zone => @zone)
    @config_mgr = ManageIQ::Providers::Foreman::ConfigurationManager.find_by(:provider_id => @provider.id)
    @config_profile = ManageIQ::Providers::Foreman::ConfigurationManager::ConfigurationProfile.create(:name        => "testprofile",
                                                                                                      :description => "testprofile",
                                                                                                      :manager_id  => @config_mgr.id)
    @config_profile2 = ManageIQ::Providers::Foreman::ConfigurationManager::ConfigurationProfile.create(:name        => "testprofile2",
                                                                                                       :description => "testprofile2",
                                                                                                       :manager_id  => @config_mgr.id)
    @configured_system = ManageIQ::Providers::Foreman::ConfigurationManager::ConfiguredSystem.create(:hostname                 => "test_configured_system",
                                                                                                     :configuration_profile_id => @config_profile.id,
                                                                                                     :manager_id               => @config_mgr.id)
    @configured_system2a = ManageIQ::Providers::Foreman::ConfigurationManager::ConfiguredSystem.create(:hostname                 => "test2a_configured_system",
                                                                                                       :configuration_profile_id => @config_profile2.id,
                                                                                                       :manager_id               => @config_mgr.id)
    @configured_system2b = ManageIQ::Providers::Foreman::ConfigurationManager::ConfiguredSystem.create(:hostname                 => "test2b_configured_system",
                                                                                                       :configuration_profile_id => @config_profile2.id,
                                                                                                       :manager_id               => @config_mgr.id)
    @configured_system_unprovisioned =
      ManageIQ::Providers::Foreman::ConfigurationManager::ConfiguredSystem.create(:hostname                 => "configured_system_unprovisioned",
                                                                                  :configuration_profile_id => nil,
                                                                                  :manager_id               => @config_mgr.id)

    @provider2 = ManageIQ::Providers::Foreman::Provider.create(:name => "test2Foreman", :url => "10.8.96.103", :zone => @zone)
    @config_mgr2 = ManageIQ::Providers::Foreman::ConfigurationManager.find_by(:provider_id => @provider2.id)
    @configured_system_unprovisioned2 =
      ManageIQ::Providers::Foreman::ConfigurationManager::ConfiguredSystem.create(:hostname                 => "configured_system_unprovisioned2",
                                                                                  :configuration_profile_id => nil,
                                                                                  :manager_id               => @config_mgr2.id)
    controller.instance_variable_set(:@sb, :active_tree => :configuration_manager_providers_tree)

    [@configured_system, @configured_system2a, @configured_system2b, @configured_system_unprovisioned2].each do |cs|
      cs.tag_with(tags, :namespace => '')
    end
  end

  it "renders index" do
    stub_user(:features => :all)
    get :index
    expect(response.status).to eq(302)
    expect(response).to redirect_to(:action => 'explorer')
  end

  it "renders explorer" do
    login_as user_with_feature(%w(providers_accord configured_systems_filter_accord))

    get :explorer
    accords = controller.instance_variable_get(:@accords)
    expect(accords.size).to eq(2)
    breadcrumbs = controller.instance_variable_get(:@breadcrumbs)
    expect(breadcrumbs[0]).to include(:url => '/provider_foreman/show_list')
    expect(response.status).to eq(200)
    expect(response.body).to_not be_empty
  end

  it "renders explorer sorted by url" do
    login_as user_with_feature(%w(providers_accord configured_systems_filter_accord))
    FactoryBot.create(:provider_foreman, :name => "foremantest1", :url => "z_url")
    FactoryBot.create(:provider_foreman, :name => "foremantest2", :url => "a_url")

    get :explorer, :params => {:sortby => '2'}
    expect(response.status).to eq(200)
    expect(response.body).to include("modelName: 'ManageIQ::Providers::ConfigurationManager'")
    expect(response.body).to include("activeTree: 'configuration_manager_providers_tree'")
    expect(response.body).to include("gtlType: 'list'")
    expect(response.body).to include("isExplorer: 'true' === 'true' ? true : false")
    expect(response.body).to include("showUrl: '/provider_foreman/x_show/'")
  end

  context "renders explorer based on RBAC" do
    it "renders explorer based on RBAC access to feature 'configured_system_tag'" do
      login_as user_with_feature %w(configured_system_tag)

      get :explorer
      accords = controller.instance_variable_get(:@accords)
      expect(accords.size).to eq(1)
      expect(accords[0][:name]).to eq("configuration_manager_cs_filter")
      expect(response.status).to eq(200)
      expect(response.body).to_not be_empty
    end

    it "renders explorer based on RBAC access to feature 'provider_foreman_add_provider'" do
      login_as user_with_feature %w(provider_foreman_add_provider)

      get :explorer
      accords = controller.instance_variable_get(:@accords)
      expect(accords.size).to eq(1)
      expect(accords[0][:name]).to eq("configuration_manager_providers")
      expect(response.status).to eq(200)
      expect(response.body).to_not be_empty
    end
  end

  context "asserts correct privileges" do
    before do
      login_as user_with_feature %w(configured_system_provision)
    end

    it "should not raise an error for feature that user has access to" do
      expect { controller.send(:assert_privileges, "configured_system_provision") }.not_to raise_error
    end

    it "should raise an error for feature that user has access to" do
      expect { controller.send(:assert_privileges, "provider_foreman_add_provider") }
        .to raise_error(MiqException::RbacPrivilegeException)
    end
  end

  it "renders show_list" do
    stub_user(:features => :all)
    get :show_list
    expect(response.status).to eq(302)
    expect(response.body).to_not be_empty
  end

  it "renders a new page" do
    post :new, :format => :js
    expect(response.status).to eq(200)
  end

  context "Verify the provisionable flag for CSs" do
    it "Provision action should not be allowed only for a Configured System marked as not provisionable" do
      allow(controller).to receive(:x_node).and_return("root")
      allow(controller).to receive(:x_tree).and_return(:type => :filter)
      controller.params = {:id => "configuration_manager_cs_filter"}
      allow(controller).to receive(:replace_right_cell)
      allow(controller).to receive(:render)
      controller.params = {:id => @configured_system2a.id}
      controller.send(:provision)
      expect(controller.send(:flash_errors?)).to_not be_truthy
    end
  end

  it "#save_provider_foreman will not save with a duplicate name" do
    ManageIQ::Providers::Foreman::Provider.create(:name => "test2Foreman", :url => "server1", :zone => @zone)
    provider2 = ManageIQ::Providers::Foreman::Provider.new(:name => "test2Foreman", :url => "server2", :zone => @zone)
    controller.instance_variable_set(:@provider, provider2)
    allow(controller).to receive(:render_flash)
    controller.save_provider
    expect(assigns(:flash_array).last[:message]).to include("Name has already been taken")
  end

  context "#edit" do
    before do
      stub_user(:features => :all)
    end

    it "renders the edit page when the configuration manager id is supplied" do
      post :edit, :params => { :id => @config_mgr.id }
      expect(response.status).to eq(200)
      right_cell_text = controller.instance_variable_get(:@right_cell_text)
      expect(right_cell_text).to eq("Edit Provider")
    end

    it "should display the zone field" do
      new_zone = FactoryBot.create(:zone, :name => "TestZone")
      controller.instance_variable_set(:@provider, @provider)
      post :edit, :params => { :id => @config_mgr.id }
      expect(response.status).to eq(200)
      expect(response.body).to include("option value=\\\"#{new_zone.name}\\\"")
    end

    it "should save the zone field" do
      new_zone = FactoryBot.create(:zone, :name => "TestZone")
      controller.instance_variable_set(:@provider, @provider)
      allow(controller).to receive(:leaf_record).and_return(false)
      post :edit, :params => { :button     => 'save',
                               :id         => @config_mgr.id,
                               :zone       => new_zone.name,
                               :url        => @provider.url,
                               :verify_ssl => @provider.verify_ssl }
      expect(response.status).to eq(200)
      expect(@provider.zone).to eq(new_zone)
    end

    it "should save the verify_ssl flag" do
      controller.instance_variable_set(:@provider, @provider)
      allow(controller).to receive(:leaf_record).and_return(false)
      [true, false].each do |verify_ssl|
        post :edit, :params => { :button     => 'save',
                                 :id         => @config_mgr.id,
                                 :url        => @provider.url,
                                 :verify_ssl => verify_ssl.to_s }
        expect(response.status).to eq(200)
        expect(@provider.verify_ssl).to eq(verify_ssl ? 1 : 0)
      end
    end

    it "renders the edit page when the configuration manager id is selected from a list view" do
      post :edit, :params => { :miq_grid_checks => @config_mgr.id }
      expect(response.status).to eq(200)
    end

    it "renders the edit page when the configuration manager id is selected from a grid/tile" do
      post :edit, :params => { "check_#{@config_mgr.id}" => "1" }
      expect(response.status).to eq(200)
    end
  end

  context "#refresh" do
    before do
      stub_user(:features => :all)
      allow(controller).to receive(:x_node).and_return("root")
      allow(controller).to receive(:rebuild_toolbars).and_return("true")
    end

    it "renders the refresh flash message for Foreman" do
      post :refresh, :params => {:miq_grid_checks => @config_mgr.id}
      expect(response.status).to eq(200)
      expect(assigns(:flash_array).first[:message]).to include("Refresh Provider initiated for 1 provider")
    end

    it "refreshes the provider when the configuration manager id is supplied" do
      allow(controller).to receive(:replace_right_cell)
      post :refresh, :params => { :id => @config_mgr.id }
      expect(assigns(:flash_array).first[:message]).to include("Refresh Provider initiated for 1 provider")
    end

    it "it refreshes a provider when the configuration manager id is selected from a grid/tile" do
      allow(controller).to receive(:replace_right_cell)
      post :refresh, :params => { "check_#{@config_mgr.id}"  => "1",
                                  "check_#{@config_mgr2.id}" => "1" }
      expect(assigns(:flash_array).first[:message]).to include("Refresh Provider initiated for 2 providers")
    end
  end

  context "#delete" do
    before do
      stub_user(:features => :all)
    end

    it "deletes the provider when the configuration manager id is supplied" do
      allow(controller).to receive(:replace_right_cell)
      post :delete, :params => { :id => @config_mgr.id }
      expect(assigns(:flash_array).first[:message]).to include("Delete initiated for 1 Provider")
    end

    it "it deletes a provider when the configuration manager id is selected from a list view" do
      allow(controller).to receive(:replace_right_cell)
      post :delete, :params => { :miq_grid_checks => "#{@config_mgr.id}, #{@config_mgr2.id}"}
      expect(assigns(:flash_array).first[:message]).to include("Delete initiated for 2 Providers")
    end

    it "it deletes a provider when the configuration manager id is selected from a grid/tile" do
      allow(controller).to receive(:replace_right_cell)
      post :delete, :params => { "check_#{@config_mgr.id}" => "1" }
      expect(assigns(:flash_array).first[:message]).to include("Delete initiated for 1 Provider")
    end
  end

  context "renders right cell text" do
    before do
      right_cell_text = nil
      login_as user_with_feature(%w(providers_accord configured_systems_filter_accord))
      controller.instance_variable_set(:@right_cell_text, right_cell_text)
      allow(controller).to receive(:get_view_calculate_gtl_type)
      allow(controller).to receive(:get_view_pages)
      allow(controller).to receive(:build_listnav_search_list)
      allow(controller).to receive(:load_or_clear_adv_search)
      allow(controller).to receive(:replace_search_box)
      allow(controller).to receive(:update_partials)
      allow(controller).to receive(:render)

      allow(controller).to receive(:items_per_page).and_return(20)
      allow(controller).to receive(:gtl_type).and_return("list")
      allow(controller).to receive(:current_page).and_return(1)
      controller.send(:build_accordions_and_trees)
    end

    it "renders right cell text for root node" do
      key = ems_key_for_provider(@provider)
      controller.send(:get_node_info, "root")
      right_cell_text = controller.instance_variable_get(:@right_cell_text)
      expect(right_cell_text).to eq("All Configuration Management Providers")
    end

    it "renders right cell text for ConfigurationManagerForeman node" do
      controller.instance_variable_set(:@in_report_data, true)
      ems_id = ems_key_for_provider(@provider)
      controller.params = {:id => ems_id}
      controller.send(:tree_select)
      right_cell_text = controller.instance_variable_get(:@right_cell_text)
      expect(right_cell_text).to eq("Configuration Profiles under Foreman Provider \"testForeman Configuration Manager\"")
    end
  end

  it "builds foreman child tree" do
    tree_builder = TreeBuilderConfigurationManager.new("root", controller.instance_variable_get(:@sb))
    objects = tree_builder.send(:x_get_tree_custom_kids, {:id => "fr"}, false, {})
    expected_objects = [@config_mgr, @config_mgr2]
    expect(objects).to match_array(expected_objects)
  end

  context "renders tree_select" do
    before do
      get :explorer
      right_cell_text = nil
      login_as user_with_feature(%w(providers_accord configured_systems_filter_accord))
      controller.instance_variable_set(:@right_cell_text, right_cell_text)
      allow(controller).to receive(:get_view_calculate_gtl_type)
      allow(controller).to receive(:get_view_pages)
      allow(controller).to receive(:build_listnav_search_list)
      allow(controller).to receive(:load_or_clear_adv_search)
      allow(controller).to receive(:replace_search_box)
      allow(controller).to receive(:update_partials)
      allow(controller).to receive(:render)

      allow(controller).to receive(:items_per_page).and_return(20)
      allow(controller).to receive(:gtl_type).and_return("list")
      allow(controller).to receive(:current_page).and_return(1)
      controller.send(:build_accordions_and_trees)
    end

    pending "renders the list view based on the nodetype(root,provider,config_profile) and the search associated with it" do
      controller.params = {:id => "root"}
      controller.instance_variable_set(:@search_text, "manager")
      controller.instance_variable_set(:@in_report_data, true)
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data.size).to eq(2)

      controller.params = {:id => "xx-fr"}
      controller.instance_variable_set(:@search_text, "manager")
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data.size).to eq(2)

      ems_id = ems_key_for_provider(@provider)
      controller.params = {:id => ems_id}
      controller.send(:tree_select)
      gtl_init_data = controller.init_report_data('reportDataController')
      expect(gtl_init_data[:data][:model_name]).to eq("manageiq/providers/configuration_managers")
      expect(gtl_init_data[:data][:activeTree]).to eq("configuration_manager_providers_tree")
      expect(gtl_init_data[:data][:parentId]).to eq(ems_id)
      expect(gtl_init_data[:data][:isExplorer]).to eq(true)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0].description).to eq("testprofile")

      controller.instance_variable_set(:@search_text, "2")
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0].description).to eq("testprofile2")
      config_profile_id2 = config_profile_key(@config_profile2)
      controller.params = {:id => config_profile_id2}
      controller.send(:tree_select)
      gtl_init_data = controller.init_report_data('reportDataController')
      expect(gtl_init_data[:data][:model_name]).to eq("manageiq/providers/configuration_managers")
      expect(gtl_init_data[:data][:activeTree]).to eq("configuration_manager_providers_tree")
      expect(gtl_init_data[:data][:parentId]).to eq(config_profile_id2)
      expect(gtl_init_data[:data][:isExplorer]).to eq(true)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0].hostname).to eq("test2a_configured_system")

      controller.instance_variable_set(:@search_text, "2b")
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0].hostname).to eq("test2b_configured_system")

      allow(controller).to receive(:x_node).and_return("root")
      allow(controller).to receive(:x_tree).and_return(:type => :filter)
      controller.params = {:id => "configuration_manager_cs_filter"}
      controller.send(:accordion_select)
      controller.instance_variable_set(:@search_text, "brew")
      allow(controller).to receive(:x_tree).and_return(:type => :providers)
      controller.params = {:id => "configuration_manager_providers"}
      controller.send(:accordion_select)

      controller.params = {:id => "root"}
      controller.send(:tree_select)
      search_text = controller.instance_variable_get(:@search_text)
      expect(search_text).to eq("manager")
      view = controller.instance_variable_get(:@view)
      expect(view.table.data.size).to eq(2)
    end

    pending "renders tree_select for a ConfigurationManagerForeman node that contains an unassigned profile" do
      ems_id = ems_key_for_provider(@provider)
      controller.instance_variable_set(:@in_report_data, true)
      controller.params = {:id => ems_id}
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      gtl_init_data = controller.init_report_data('reportDataController')
      expect(gtl_init_data[:data][:model_name]).to eq("manageiq/providers/configuration_managers")
      expect(gtl_init_data[:data][:activeTree]).to eq("configuration_manager_providers_tree")
      expect(gtl_init_data[:data][:parentId]).to eq(ems_id)
      expect(gtl_init_data[:data][:isExplorer]).to eq(true)
      expect(view.table.data[0].data).to include('description' => "testprofile")
      expect(view.table.data[2]).to include('description' => "Unassigned Profiles Group",
                                            'name'        => "Unassigned Profiles Group")
    end

    pending "renders tree_select for a ConfigurationManagerForeman node that contains only an unassigned profile" do
      ems_id = ems_key_for_provider(@provider2)
      controller.instance_variable_set(:@in_report_data, true)
      controller.params = {:id => ems_id}
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0]).to include('description' => "Unassigned Profiles Group",
                                            'name'        => "Unassigned Profiles Group")
    end

    pending "renders tree_select for an 'Unassigned Profiles Group' node for the first provider" do
      controller.params = {:id => "-#{ems_id_for_provider(@provider)}-unassigned"}
      controller.instance_variable_set(:@in_report_data, true)
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0].data).to include('hostname' => "configured_system_unprovisioned")
    end

    pending "renders tree_select for an 'Unassigned Profiles Group' node for the second provider" do
      controller.instance_variable_set(:@in_report_data, true)
      controller.params = {:id => "-#{ems_id_for_provider(@provider2)}-unassigned"}
      controller.send(:tree_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data[0].data).to include('hostname' => "configured_system_unprovisioned2")
    end

    it "calls get_view with the associated dbname for the Configuration Management Providers accordion" do
      stub_user(:features => :all)
      allow(controller).to receive(:x_active_tree).and_return(:configuration_manager_providers_tree)
      allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_providers)
      allow(controller).to receive(:build_listnav_search_list)
      controller.params = {:id => "configuration_manager_providers_accord"}
      expect(controller).to receive(:get_view).with("ManageIQ::Providers::ConfigurationManager",
                                                    :gtl_dbname => :cm_providers, :dbname => :cm_providers).and_call_original
      controller.send(:accordion_select)
    end

    it "calls get_view with the associated dbname for the Configuration Profiles list" do
      stub_user(:features => :all)
      allow(controller).to receive(:x_active_tree).and_return(:configuration_manager_providers_tree)
      allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_providers)
      ems_id = ems_id_for_provider(@provider)
      controller.instance_variable_set(:@in_report_data, true)
      controller.params = {:id => ems_key_for_provider(@provider)}
      allow(controller).to receive(:build_listnav_search_list)
      allow(controller).to receive(:apply_node_search_text)
      expect(controller).to receive(:get_view).with("ConfigurationProfile", :match_via_descendants => "ConfiguredSystem",
                                                                            :named_scope           => [[:with_manager, ems_id]],
                                                                            :dbname                => :cm_configuration_profiles,
                                                                            :gtl_dbname            => :cm_configuration_profiles).and_call_original
      controller.send(:tree_select)
    end

    it "calls get_view with the associated dbname for the Configured Systems accordion" do
      stub_user(:features => :all)
      allow(controller).to receive(:x_active_tree).and_return(:configuration_manager_cs_filter_tree)
      allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_cs_filter)
      allow(controller).to receive(:build_listnav_search_list)
      controller.params = {:id => "configuration_manager_cs_filter_accord"}
      expect(controller).to receive(:get_view).with("ManageIQ::Providers::Foreman::ConfigurationManager::ConfiguredSystem",
                                                    :gtl_dbname => :cm_configured_systems, :dbname => :cm_configured_systems).and_call_original
      allow(controller).to receive(:build_listnav_search_list)
      controller.send(:accordion_select)
    end

    pending "does not display an automation manger configured system in the Configured Systems accordion" do
      controller.instance_variable_set(:@in_report_data, true)
      stub_user(:features => :all)
      FactoryBot.create(:configured_system_ansible_tower)
      allow(controller).to receive(:x_active_tree).and_return(:configuration_manager_cs_filter_tree)
      allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_cs_filter)
      allow(controller).to receive(:build_listnav_search_list)
      controller.params = {:id => "configuration_manager_cs_filter_accord"}
      controller.send(:accordion_select)
      view = controller.instance_variable_get(:@view)
      expect(view.table.data.size).to eq(5)
    end
  end

  it "singularizes breadcrumb name" do
    expect(controller.send(:breadcrumb_name, nil)).to eq("#{ui_lookup(:ui_title => "foreman")} Provider")
  end

  it "renders tagging editor for a configured system" do
    session[:tag_items] = [@configured_system.id]
    session[:assigned_filters] = []
    allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_cs_filter)
    parent = FactoryBot.create(:classification, :name => "test_category")
    FactoryBot.create(:classification_tag,      :name => "test_entry",         :parent => parent)
    FactoryBot.create(:classification_tag,      :name => "another_test_entry", :parent => parent)
    post :tagging, :params => { :id => @configured_system.id, :format => :js }
    expect(response.status).to eq(200)
  end

  it "renders tagging editor for a configured system in the manager accordion" do
    session[:assigned_filters] = []
    allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_providers)
    allow(controller).to receive(:x_node).and_return(config_profile_key(@config_profile))
    parent = FactoryBot.create(:classification, :name => "test_category")
    FactoryBot.create(:classification_tag,      :name => "test_entry",         :parent => parent)
    FactoryBot.create(:classification_tag,      :name => "another_test_entry", :parent => parent)
    post :tagging, :params => { :miq_grid_checks => [@configured_system.id], :id => @config_profile.id, :format => :js }
    expect(response.status).to eq(200)
  end

  it "renders tree_select as js" do
    TreeBuilderConfigurationManager.new(:configuration_manager_providers_tree, controller.instance_variable_get(:@sb))

    allow(controller).to receive(:process_show_list)
    allow(controller).to receive(:add_unassigned_configuration_profile_record)
    allow(controller).to receive(:replace_explorer_trees)
    allow(controller).to receive(:build_listnav_search_list)
    allow(controller).to receive(:rebuild_toolbars)
    allow(controller).to receive(:replace_search_box)
    allow(controller).to receive(:update_partials)

    stub_user(:features => :all)

    key = ems_key_for_provider(@provider)
    post :tree_select, :params => { :id => key, :format => :js }
    expect(response.status).to eq(200)
  end

  context "tree_select on provider foreman node" do
    before do
      login_as user_with_feature %w(provider_foreman_refresh_provider provider_foreman_edit_provider provider_foreman_delete_provider)

      allow(controller).to receive(:check_privileges)
      allow(controller).to receive(:process_show_list)
      allow(controller).to receive(:add_unassigned_configuration_profile_record)
      allow(controller).to receive(:replace_explorer_trees)
      allow(controller).to receive(:build_listnav_search_list)
      allow(controller).to receive(:replace_search_box)
      allow(controller).to receive(:x_active_tree).and_return(:configuration_manager_providers_tree)
    end

    it "does not hide Configuration button in the toolbar" do
      TreeBuilderConfigurationManager.new(:configuration_manager_providers_tree, controller.instance_variable_get(:@sb))
      key = ems_key_for_provider(@provider)
      post :tree_select, :params => { :id => key }
      expect(response.status).to eq(200)
      expect(response.body).not_to include('<div class=\"hidden btn-group dropdown\"><button data-explorer=\"true\" title=\"Configuration\"')
    end
  end

  it "renders textual summary for a configured system" do
    stub_user(:features => :all)

    tree_node_id = @configured_system.id

    # post to x_show sets session variables and redirects to explorer
    # then get to explorer renders the data for the active node
    # we test the textual_summary for a configured system

    seed_session_trees('provider_foreman', 'cs_tree', "cs-#{tree_node_id}")
    get :explorer

    expect(response.status).to eq(200)
    expect(response).to render_template(:partial => 'layouts/_textual_groups_generic')
  end

  context "fetches the list setting:Grid/Tile/List from settings" do
    before do
      login_as user_with_feature(%w(providers_accord configured_systems_filter_accord))
      allow(controller).to receive(:items_per_page).and_return(20)
      allow(controller).to receive(:current_page).and_return(1)
      allow(controller).to receive(:get_view_pages)
      allow(controller).to receive(:build_listnav_search_list)
      allow(controller).to receive(:load_or_clear_adv_search)
      allow(controller).to receive(:replace_search_box)
      allow(controller).to receive(:update_partials)
      allow(controller).to receive(:render)

      controller.instance_variable_set(:@settings,
                                       :views => {:cm_providers          => "grid",
                                                  :cm_configured_systems => "tile"})
      controller.send(:build_accordions_and_trees)
    end

    it "fetches list type = 'grid' from settings for Providers accordion" do
      key = ems_key_for_provider(@provider)
      allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_providers)
      controller.send(:get_node_info, key)
      list_type = controller.instance_variable_get(:@gtl_type)
      expect(list_type).to eq("grid")
    end

    it "fetches list type = 'tile' from settings for Configured Systems accordion" do
      key = ems_key_for_provider(@provider)
      allow(controller).to receive(:x_active_accord).and_return(:configuration_manager_cs_filter)
      controller.send(:get_node_info, key)
      list_type = controller.instance_variable_get(:@gtl_type)
      expect(list_type).to eq("tile")
    end
  end

  context "#build_credentials" do
    it "uses params[:default_password] for validation if one exists" do
      controller.params = {:default_userid   => "userid",
                           :default_password => "password2"}
      creds = {:userid => "userid", :password => "password2"}
      expect(controller.send(:build_credentials)).to include(:default => creds)
    end

    it "uses the stored password for validation if params[:default_password] does not exist" do
      controller.params = {:default_userid => "userid"}
      controller.instance_variable_set(:@provider, @provider)
      expect(@provider).to receive(:authentication_password).and_return('password')
      creds = {:userid => "userid", :password => "password"}
      expect(controller.send(:build_credentials)).to include(:default => creds)
    end
  end

  context "when user with specific tag settings logs in" do
    before do
      login_as user_with_feature %w(providers_accord configured_systems_filter_accord)
    end
    it "builds foreman tree with no nodes after rbac filtering" do
      user_filters = {'belongs' => [], 'managed' => [tags]}
      allow_any_instance_of(User).to receive(:get_filters).and_return(user_filters)
      tree = TreeBuilderConfigurationManager.new(:configuration_manager_providers_tree, controller.instance_variable_get(:@sb))
      first_child = find_treenode_for_foreman_provider(tree, @provider)
      expect(first_child).to eq(nil)
    end

    it "builds foreman tree with only those nodes that contain the filtered configured systems" do
      user_filters = {'belongs' => [], 'managed' => [tags]}
      allow_any_instance_of(User).to receive(:get_filters).and_return(user_filters)
      Classification.seed
      quota_2gb_tag = Classification.where("description" => "2GB").first
      Classification.bulk_reassignment(:model      => "ConfiguredSystem",
                                       :object_ids => @configured_system.id,
                                       :add_ids    => quota_2gb_tag.id,
                                       :delete_ids => [])
      tree = TreeBuilderConfigurationManager.new(:configuration_manager_providers_tree, controller.instance_variable_get(:@sb))
      node1 = find_treenode_for_foreman_provider(tree, @provider)
      node2 = find_treenode_for_foreman_provider(tree, @provider2)
      expect(node1).not_to be_nil
      expect(node2).to be_nil
    end
  end

  context "when a configured system belonging to an unassigned configuration profile is selected in the list" do
    it "calls tree_select to select the unassigned configuration profile node in the tree" do
      allow(controller).to receive(:check_privileges)
      allow(controller).to receive(:build_listnav_search_list)
      allow(controller).to receive(:x_node).and_return("-1000000000013-unassigned")
      post :x_show, :params => {:id => "1r1", :format => :js}
      expect(response.status).to eq(200)
    end
  end

  context "#tags_edit" do
    let!(:user) { stub_user(:features => :all) }
    before do
      EvmSpecHelper.create_guid_miq_server_zone
      allow(@configured_system).to receive(:tagged_with).with(:cat => user.userid).and_return("my tags")
      classification = FactoryBot.create(:classification, :name => "department", :description => "Department")
      @tag1 = FactoryBot.create(:classification_tag,
                                 :name   => "tag1",
                                 :parent => classification)
      @tag2 = FactoryBot.create(:classification_tag,
                                 :name   => "tag2",
                                 :parent => classification)
      allow(Classification).to receive(:find_assigned_entries).with(@configured_system).and_return([@tag1, @tag2])
      session[:tag_db] = "ConfiguredSystem"
      edit = {:key        => "ConfiguredSystem_edit_tags__#{@configured_system.id}",
              :tagging    => "ConfiguredSystem",
              :object_ids => [@configured_system.id],
              :current    => {:assignments => []},
              :new        => {:assignments => [@tag1.id, @tag2.id]}}
      session[:edit] = edit
    end

    it "builds tagging screen" do
      post :tagging, :params => {:format => :js, :miq_grid_checks => [@configured_system.id]}
      expect(assigns(:flash_array)).to be_nil
      expect(response.status).to eq(200)
    end

    it "cancels tags edit" do
      allow(controller).to receive(:previous_breadcrumb_url).and_return("previous-url")
      post :tagging_edit, :params => {:button => "cancel", :format => :js, :id => @configured_system.id}
      expect(assigns(:flash_array).first[:message]).to include("was cancelled by the user")
      expect(assigns(:edit)).to be_nil
      expect(response.status).to eq(200)
    end

    it "save tags" do
      allow(controller).to receive(:previous_breadcrumb_url).and_return("previous-url")
      post :tagging_edit, :params => {:button => "save", :format => :js, :id => @configured_system.id, :data => get_tags_json([@tag1, @tag2])}
      expect(assigns(:flash_array).first[:message]).to include("Tag edits were successfully saved")
      expect(assigns(:edit)).to be_nil
      expect(response.status).to eq(200)
    end
  end

  context 'download pdf file' do
    let(:pdf_options) { controller.instance_variable_get(:@options) }

    before do
      @record = @config_profile
      allow(PdfGenerator).to receive(:pdf_from_string).and_return("")
      allow(controller).to receive(:tagdata).and_return(nil)
      allow(controller).to receive(:x_node).and_return(config_profile_key(@config_profile))
      login_as FactoryBot.create(:user_admin)
      stub_user(:features => :all)
    end

    it 'request returns 200' do
      get :download_summary_pdf, :params => {:id => @record.id}
      expect(response.status).to eq(200)
    end

    it 'title is set correctly' do
      get :download_summary_pdf, :params => {:id => @record.id}
      expect(pdf_options[:title]).to eq("#{ui_lookup(:model => @record.class.name)} \"#{@record.name}\"")
    end
  end

  describe '#get_node_info' do
    before do
      controller.instance_variable_set(:@right_cell_text, "")
      controller.instance_variable_set(:@search_text, search)
    end

    context 'searching text' do
      let(:search) { "some_text" }

      it 'updates right cell text according to search text' do
        controller.send(:get_node_info, "root")
        expect(controller.instance_variable_get(:@right_cell_text)).to eq(" (Names with \"#{search}\")")
      end
    end
  end

  def find_treenode_for_foreman_provider(tree, provider)
    key = ems_key_for_provider(provider)
    tree_nodes = JSON.parse(tree.tree_nodes)
    tree_nodes[0]['nodes'][0]['nodes']&.find { |c| c['key'] == key }
  end

  def ems_key_for_provider(provider)
    ems = ExtManagementSystem.where(:provider_id => provider.id).first
    "fr-#{ems.id}"
  end

  def config_profile_key(config_profile)
    cp = ConfigurationProfile.where(:id => config_profile.id).first
    "cp-#{cp.id}"
  end

  def ems_id_for_provider(provider)
    ems = ExtManagementSystem.where(:provider_id => provider.id).first
    ems.id
  end
end

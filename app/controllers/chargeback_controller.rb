class ChargebackController < ApplicationController
  before_action :check_privileges
  before_action :get_session_data
  after_action :cleanup_action
  after_action :set_session_data

  include Mixins::SavedReportPaging
  include Mixins::GenericSessionMixin
  include Mixins::BreadcrumbsMixin

  CB_X_BUTTON_ALLOWED_ACTIONS = {
    'chargeback_rates_copy'   => :cb_rate_edit,
    'chargeback_rates_delete' => :cb_rates_delete,
    'chargeback_rates_edit'   => :cb_rate_edit,
    'chargeback_rates_new'    => :cb_rate_edit
  }.freeze

  def x_button
    generic_x_button(CB_X_BUTTON_ALLOWED_ACTIONS)
  end

  def x_show
    @explorer = true
    if x_active_tree == :cb_rates_tree
      @record = identify_record(params[:id], ChargebackRate)
      nodeid = x_build_node_id(@record)
      params[:id] = "xx-#{@record.rate_type}_#{nodeid}"
      params[:tree] = x_active_tree.to_s
      tree_select
    end
  end

  def accordion_select
    self.x_active_accord = params[:id].sub(/_accord$/, '')
    self.x_active_tree   = "#{x_active_accord}_tree"
    get_node_info(x_node)
    replace_right_cell
  end

  def tree_select
    self.x_active_tree = params[:tree] if params[:tree]
    self.x_node = params[:id]
    get_node_info(x_node)
    replace_right_cell
  end

  def explorer
    @breadcrumbs = []
    @explorer    = true
    build_accordions_and_trees

    @right_cell_text = case x_active_tree
                       when :cb_rates_tree       then _("All Chargeback Rates")
                       when :cb_assignments_tree then _("All Assignments")
                       when :cb_reports_tree     then _("All Saved Chargeback Reports")
                       end
    set_form_locals if @in_a_form
    session[:changed] = false

    render :layout => "application" unless request.xml_http_request?
  end

  def set_form_locals
    if x_active_tree == :cb_rates_tree
      @x_edit_buttons_locals = {:action_url => 'cb_rate_edit'}
    elsif x_active_tree == :cb_assignments_tree
      @x_edit_buttons_locals = {
        :action_url   => 'cb_assign_update',
        :no_cancel    => true,
        :multi_record => true
      }
    end
  end

  # Show the main Schedules list view
  def cb_rates_list
    @gtl_type = "list"
    @explorer = true
    if params[:ppsetting]                                              # User selected new per page value
      @items_per_page = params[:ppsetting].to_i                        # Set the new per page value
      @settings.store_path(:perpage, @gtl_type.to_sym, @items_per_page) # Set the per page setting for this gtl type
    end
    @sortcol = session[:rates_sortcol].nil? ? 0 : session[:rates_sortcol].to_i
    @sortdir = session[:rates_sortdir].nil? ? "ASC" : session[:rates_sortdir]

    @view, @pages = get_view(ChargebackRate, :named_scope => [[:with_rate_type, x_node.split('-').last]]) # Get the records (into a view) and the paginator

    @current_page = @pages[:current] unless @pages.nil? # save the current page number
    session[:rates_sortcol] = @sortcol
    session[:rates_sortdir] = @sortdir

    update_gtl_div('cb_rates_list') if pagination_or_gtl_request? && @show_list
  end

  def cb_rate_edit
    assert_privileges(params[:pressed]) if params[:pressed]
    case params[:button]
    when "cancel"
      if params[:id]
        add_flash(_("Edit of Chargeback Rate \"%{name}\" was cancelled by the user") % {:name => session[:edit][:new][:description]})
      else
        add_flash(_("Add of new Chargeback Rate was cancelled by the user"))
      end
      get_node_info(x_node)
      @edit = session[:edit] = nil # clean out the saved info
      session[:changed] = false
      replace_right_cell
    when "save", "add"
      id = params[:button] == "save" ? params[:id] : "new"
      return unless load_edit("cbrate_edit__#{id}", "replace_cell__chargeback")
      @rate = params[:button] == "add" ? ChargebackRate.new : ChargebackRate.find(params[:id])
      if @edit[:new][:description].nil? || @edit[:new][:description] == ""
        render_flash(_("Description is required"), :error)
        return
      end
      @rate.description = @edit[:new][:description]
      @rate.rate_type   = @edit[:new][:rate_type] if @edit[:new][:rate_type]

      cb_rate_set_record_vars
      # Detect errors saving tiers
      tiers_valid = @rate_tiers.all? { |tiers| tiers.all?(&:valid?) }

      @rate.chargeback_rate_details.replace(@rate_details)
      @rate.chargeback_rate_details.each_with_index do |_detail, i|
        @rate_details[i].save_tiers(@rate_tiers[i])
      end

      tiers_valid &&= @rate_details.all? { |rate_detail| rate_detail.errors.messages.blank? }

      if tiers_valid && @rate.save
        if params[:button] == "add"
          AuditEvent.success(build_created_audit(@rate, @edit))
          add_flash(_("Chargeback Rate \"%{name}\" was added") % {:name => @rate.description})
        else
          AuditEvent.success(build_saved_audit(@rate, @edit))
          add_flash(_("Chargeback Rate \"%{name}\" was saved") % {:name => @rate.description})
        end
        @edit = session[:edit] = nil # clean out the saved info
        session[:changed] = @changed = false
        get_node_info(x_node)
        replace_right_cell(:replace_trees => [:cb_rates])
      else
        @rate.errors.each do |field, msg|
          add_flash("#{field.to_s.capitalize} #{msg}", :error)
        end
        @rate_details.each do |detail|
          display_detail_errors(detail, detail.errors)
        end
        @rate_tiers.each_with_index do |tiers, detail_index|
          tiers.each do |tier|
            display_detail_errors(@rate_details[detail_index], tier.errors)
          end
        end
        @changed = session[:changed] = (@edit[:new] != @edit[:current])
        javascript_flash
      end

    when "reset", nil # displaying edit from for actions: new, edit or copy
      @in_a_form = true
      @_params[:id] ||= find_checked_items[0]
      session[:changed] = params[:pressed] == 'chargeback_rates_copy'

      @rate = new_rate_edit? ? ChargebackRate.new : ChargebackRate.find(params[:id])
      @record = @rate

      if params[:pressed] == 'chargeback_rates_edit' && @rate.default?
        render_flash(_("Default Chargeback Rate \"%{name}\" cannot be edited.") % {:name => @rate.description}, :error)
        return
      end

      cb_rate_set_form_vars

      add_flash(_("All changes have been reset"), :warning) if params[:button] == "reset"

      replace_right_cell
    end
  end

  # AJAX driven routine to check for changes in ANY field on the form
  def cb_rate_form_field_changed
    return unless load_edit("cbrate_edit__#{params[:id]}", "replace_cell__chargeback")
    cb_rate_get_form_vars
    render :update do |page|
      page << javascript_prologue
      changed = (@edit[:new] != @edit[:current])
      # Update the new column with the code of the currency selected by the user
      page.replace('chargeback_rate_currency', :partial => 'cb_rate_currency')
      page << javascript_for_miq_button_visibility(changed)
    end
  end

  def cb_rate_show
    @display = "main"
    if @record.nil?
      flash_to_session(_('Error: Record no longer exists in the database'), :error)
      redirect_to(:action => 'cb_rates_list')
      return
    end
  end

  # Delete all selected or single displayed action(s)
  def cb_rates_delete
    assert_privileges("chargeback_rates_delete")
    rates = []
    if !params[:id] # showing a list
      rates = find_checked_items
      if rates.empty?
        add_flash(_("No Chargeback Rates were selected for deletion"), :error)
      end
    else # showing 1 rate, delete it
      cb_rate = ChargebackRate.find_by(:id => params[:id])
      self.x_node = x_node.split('_').first
      if cb_rate.nil?
        add_flash(_("Chargeback Rate no longer exists"), :error)
      else
        rates.push(params[:id])
      end
    end
    process_cb_rates(rates, 'destroy') if rates.present?

    cb_rates_list
    @right_cell_text = _("%<typ>s Chargeback Rates") % {:typ => x_node.split('-').last}
    replace_right_cell(:replace_trees => [:cb_rates])
  end

  # AJAX driven routine to check for changes in ANY field on the form
  def cb_assign_field_changed
    return unless load_edit("cbassign_edit__#{x_node}", "replace_cell__chargeback")
    cb_assign_get_form_vars
    render :update do |page|
      page << javascript_prologue
      except = %i[cbshow_typ cbtag_cat cblabel_key]
      changed = (@edit[:new].except(*except) != @edit[:current].except(*except))
      page.replace("cb_assignment_div", :partial => "cb_assignments") if params[:cbshow_typ] || params[:cbtag_cat] || params[:cblabel_key]
      page << javascript_for_miq_button_visibility(changed)
    end
  end

  # Add a new tier at the end
  def cb_tier_add
    detail_index = params[:detail_index]
    ii = detail_index.to_i

    @edit  = session[:edit]
    detail = @edit[:new][:details][ii]

    @edit[:new][:num_tiers][ii] = detail[:chargeback_tiers].to_a.length if detail[:chargeback_tiers]
    @edit[:new][:num_tiers][ii] = 1 unless @edit[:new][:num_tiers][ii] || @edit[:new][:num_tiers][ii].zero?
    @edit[:new][:num_tiers][ii] += 1

    tier_index = @edit[:new][:num_tiers][ii] - 1
    tier_list = @edit[:new][:tiers][ii]
    tier_list[tier_index] = {}

    tier                 = tier_list[tier_index]
    tier[:start]         = tier_list[tier_index - 1][:finish]
    tier[:finish]        = Float::INFINITY
    tier[:fixed_rate]    = 0.0
    tier[:variable_rate] = 0.0

    code_currency = ChargebackRateDetailCurrency.find_by(:id => detail[:currency]).code
    add_row(detail_index, tier_index - 1, code_currency)
  end

  # Remove the selected tier
  def cb_tier_remove
    @edit = session[:edit]
    index = params[:index]
    detail_index, tier_to_remove_index = index.split("-")
    detail_index = detail_index.to_i
    @edit[:new][:num_tiers][detail_index] = @edit[:new][:num_tiers][detail_index] - 1

    # Delete tier record
    @edit[:new][:tiers][detail_index].delete_at(tier_to_remove_index.to_i)

    @changed = session[:changed] = true

    render :update do |page|
      page << javascript_prologue
      page.replace_html("chargeback_rate_edit_form", :partial => "cb_rate_edit_table")
      page << javascript_for_miq_button_visibility(@changed)
    end
  end

  def cb_assign_update
    if params[:button] == "reset"
      get_node_info(x_node)
      add_flash(_("All changes have been reset"), :warning)
      replace_right_cell
    else
      return unless load_edit("cbassign_edit__#{x_node}", "replace_cell__chargeback")
      cb_assign_set_record_vars
      rate_type = x_node.split('-').last
      begin
        ChargebackRate.set_assignments(rate_type, @edit[:set_assignments])
      rescue => bang
        render_flash(_("Error during 'Rate assignments': %{error_message}") % {:error_message => bang.message}, :error)
      else
        add_flash(_("Rate Assignments saved"))
        get_node_info(x_node)
        replace_right_cell
      end
    end
  end

  def title
    @title = _("Chargeback")
  end

  private ############################

  def features
    [
      {
        :role  => "chargeback_reports",
        :name  => :cb_reports,
        :title => _("Reports")
      },
      {
        :role  => "chargeback_rates",
        :name  => :cb_rates,
        :title => _("Rates")
      },
      {
        :role  => "chargeback_assignments",
        :name  => :cb_assignments,
        :title => _("Assignments")
      }
    ].map { |hsh| ApplicationController::Feature.new_with_hash(hsh) }
  end

  # Build a Chargeback Reports explorer tree
  def cb_rpts_build_tree
    TreeBuilderChargebackReports.new("cb_reports_tree", @sb)
  end

  def cb_rpts_show_saved_report
    @sb[:last_savedreports_id] = parse_nodetype_and_id(params[:id]).last if params[:id] && params[:id] != "reports"
    cb_rpts_fetch_saved_report(@sb[:last_savedreports_id])
    @sb[:parent_reports] = nil if @report.blank?
  end

  def cb_rpts_fetch_saved_report(id)
    rr = MiqReportResult.for_user(current_user).find(id.to_s.split('-').last)
    if rr.nil? # Saved report no longer exists
      @report = nil
      return
    end
    @right_cell_text ||= _("Saved Chargeback Report [%{name}]") % {:name => rr.name}
    if !current_user.miq_group_ids.include?(rr.miq_group_id) && !report_admin_user?
      add_flash(_("Report is not authorized for the logged in user"), :error)
      @saved_reports = cb_rpts_get_all_reps(id.split('-')[1])
      return
    else
      @report_result_id = session[:report_result_id] = rr.id
      session[:report_result_runtime] = rr.last_run_on
      if rr.status.downcase == "complete"
        session[:rpt_task_id] = nil
        if rr.valid_report_column?
          if rr.contains_records?
            @html = report_first_page(rr) # Get the first page of the results
            if @report.graph.present?
              @render_chart = true
              @ght_type = "hybrid"
            else
              @ght_type = "tabular"
            end
            @report.extras ||= {} # Create extras hash
            @report.extras[:to_html] ||= @html # Save the html report
          else
            add_flash(_("No records found for this report"), :warning)
          end
        else
          @saved_reports = cb_rpts_get_all_reps(rr.miq_report_id.to_s)
          rep = MiqReport.find(rr.miq_report_id)
          if x_active_tree == :cb_reports_tree
            self.x_node = "reports-#{rep.id}"
          end
          return
        end
      end
    end
  end

  def get_node_info(node, show_list = true)
    @show_list = show_list
    node = valid_active_node(node)
    if x_active_tree == :cb_rates_tree
      if node == "root"
        @record = nil
        @right_cell_text = _("All Chargeback Rates")
      elsif ["xx-Compute", "xx-Storage"].include?(node)
        @record = nil
        @right_cell_text = case node
                           when "xx-Compute" then _("Compute Chargeback Rates")
                           when "xx-Storage" then _("Storage Chargeback Rates")
                           end
        cb_rates_list
      else
        @record = ChargebackRate.find(parse_nodetype_and_id(node).last)
        @sb[:action] = nil
        @right_cell_text = case @record.rate_type
                           when "Compute" then _("Compute Chargeback Rate \"%{name}\"") % {:name => @record.description}
                           when "Storage" then _("Storage Chargeback Rate \"%{name}\"") % {:name => @record.description}
                           end
        cb_rate_show
      end
    elsif x_active_tree == :cb_assignments_tree
      if ["xx-Compute", "xx-Storage"].include?(node)
        cb_assign_set_form_vars
        @right_cell_text = case node
                           when "xx-Compute" then _("Compute Rate Assignments")
                           when "xx-Storage" then _("Storage Rate Assignments")
                           end
      else
        @right_cell_text = _("All Assignments")
      end
    elsif x_active_tree == :cb_reports_tree
      @nodetype = node.split("-")[0]
      nodes = x_node.split('_')
      nodes_len = nodes.length

      # On the root node
      if x_node == "root"
        cb_rpt_build_folder_nodes
        @right_cell_div = "reports_list_div"
        @right_cell_text = _("All Saved Chargeback Reports")
      elsif nodes_len == 2
        # On a saved report node
        cb_rpts_show_saved_report
        if @report
          s = MiqReportResult.for_user(current_user).find(nodes.last.split('-').last)

          @right_cell_div = "reports_list_div"
          @right_cell_text = _("Saved Chargeback Report \"%{last_run_on}\"") % {:last_run_on => format_timezone(s.last_run_on, Time.zone, "gtl")}
        else
          add_flash(_("Selected Saved Chargeback Report no longer exists"), :warning)
          self.x_node = nodes[0..1].join("_")
          cb_rpts_build_tree # Rebuild tree
        end
      # On a saved reports parent node
      else
        # saved reports under report node on saved report accordion
        @saved_reports = cb_rpts_get_all_reps(nodes[0].split('-')[1])
        if @saved_reports.present?
          @sb[:sel_saved_rep_id] = nodes[1]
          @right_cell_div = "reports_list_div"
          miq_report = MiqReport.for_user(current_user).find(@sb[:miq_report_id])
          @right_cell_text = _("Saved Chargeback Reports \"%{report_name}\"") % {:report_name => miq_report.name}
          @sb[:parent_reports] = nil if @sb[:saved_reports].present? # setting it to nil so saved reports can be displayed, unless all saved reports were deleted
        else
          add_flash(_("Selected Chargeback Report no longer exists"), :warning)
          self.x_node = nodes[0]
          @saved_reports = nil
          cb_rpts_build_tree # Rebuild tree
        end
      end
    end
    {:view => @view, :pages => @pages}
  end

  def cb_rpt_build_folder_nodes
    @parent_reports = {}

    MiqReportResult.with_saved_chargeback_reports.select_distinct_results.each_with_index do |sr, sr_idx|
      @parent_reports[sr.miq_report.name] = "#{sr.miq_report_id}-#{sr_idx}"
    end
  end

  def cb_rpts_get_all_reps(nodeid)
    return [] if nodeid.blank?
    @sb[:miq_report_id] = nodeid
    miq_report = MiqReport.for_user(current_user).find(@sb[:miq_report_id])
    saved_reports = miq_report.miq_report_results.with_current_user_groups
                              .select("id, miq_report_id, name, last_run_on, report_source")
                              .order(:last_run_on => :desc)

    @sb[:tree_typ] = "reports"
    @right_cell_text = _("Report \"%{report_name}\"") % {:report_name => miq_report.name}
    saved_reports
  end

  def cb_rates_build_tree
    TreeBuilderChargebackRates.new("cb_rates_tree", @sb)
  end

  # Build a Catalog Items explorer tree
  def cb_assignments_build_tree
    TreeBuilderChargebackAssignments.new("cb_assignments_tree", @sb)
  end

  # Common Schedule button handler routines
  def process_cb_rates(rates, task)
    process_elements(rates, ChargebackRate, task)
  end

  # Set form variables for edit
  def cb_rate_set_form_vars
    @edit = {}
    @edit[:new] = HashWithIndifferentAccess.new
    @edit[:current] = HashWithIndifferentAccess.new
    @edit[:new][:tiers] = []
    @edit[:new][:num_tiers] = []
    @edit[:new][:description] = @rate.description
    @edit[:new][:rate_type] = @rate.rate_type || x_node.split('-').last
    @edit[:new][:details] = []

    tiers = []
    rate_details = @rate.chargeback_rate_details
    rate_details = ChargebackRateDetail.default_rate_details_for(@edit[:new][:rate_type]) if new_rate_edit?

    # Select the currency of the first chargeback_rate_detail. All the chargeback_rate_details have the same currency
    @edit[:new][:currency] = rate_details[0].detail_currency.id
    @edit[:new][:code_currency] = rate_details[0].detail_currency.code

    rate_details.each_with_index do |detail, detail_index|
      temp = detail.slice(*ChargebackRateDetail::FORM_ATTRIBUTES)
      temp[:report_column_name] = Dictionary.gettext(detail.chargeable_field.metric_key, :type => :column, :notfound => :titleize)
      temp[:group] = detail.chargeable_field.group
      temp[:per_time] ||= "hourly"

      temp[:currency] = detail.detail_currency.id

      if detail.chargeable_field.detail_measure.present?
        temp[:detail_measure] = {}
        temp[:detail_measure][:measures] = detail.chargeable_field.detail_measure.measures
        temp[:chargeback_rate_detail_measure_id] = detail.chargeable_field.detail_measure.id
      end

      temp[:id] = params[:pressed] == 'chargeback_rates_copy' ? nil : detail.id
      temp[:sub_metrics] = detail.sub_metrics
      temp[:sub_metric_human] = detail.sub_metric_human

      tiers[detail_index] ||= []

      detail.chargeback_tiers.each do |tier|
        new_tier = tier.slice(*ChargebackTier::FORM_ATTRIBUTES)
        new_tier[:id] = params[:pressed] == 'chargeback_rates_copy' ? nil : tier.id
        new_tier[:chargeback_rate_detail_id] = params[:pressed] == 'chargeback_rates_copy' ? nil : detail.id
        new_tier[:start] = new_tier[:start].to_f
        new_tier[:finish] = ChargebackTier.to_float(new_tier[:finish])
        tiers[detail_index].push(new_tier)
      end

      @edit[:new][:tiers][detail_index] = tiers[detail_index]
      @edit[:new][:num_tiers][detail_index] = tiers[detail_index].size
      @edit[:new][:details].push(temp)
    end

    @edit[:new][:per_time_types] = ChargebackRateDetail::PER_TIME_TYPES

    if params[:pressed] == 'chargeback_rates_copy'
      @rate.id = nil
      @edit[:new][:description] = "copy of #{@rate.description}"
    end

    @edit[:rec_id] = @rate.id || nil
    @edit[:key] = "cbrate_edit__#{@rate.id || "new"}"
    @edit[:current] = copy_hash(@edit[:new])
    session[:edit] = @edit
  end

  # Get variables from edit form
  def cb_rate_get_form_vars
    @edit[:new][:description] = params[:description] if params[:description]
    if params[:currency]
      @edit[:new][:currency] = params[:currency].to_i
      @edit[:new][:code_currency] = ChargebackRateDetailCurrency.find(params[:currency]).code
    end
    @edit[:new][:details].each_with_index do |detail, detail_index|
      %i[per_time per_unit sub_metric].each do |measure|
        key = "#{measure}_#{detail_index}".to_sym
        detail[measure] = params[key] if params[key]
      end
      # Add currencies to chargeback_controller.rb
      detail[:currency] = params[:currency].to_i if params[:currency]

      # Save tiers into @edit
      (0..@edit[:new][:num_tiers][detail_index].to_i - 1).each do |tier_index|
        tier = @edit[:new][:tiers][detail_index][tier_index] || {}
        %i[fixed_rate variable_rate start finish].each do |field|
          key = "#{field}_#{detail_index}_#{tier_index}".to_sym
          tier[field] = params[key] if params[key]
        end
      end
    end
  end

  def cb_rate_set_record_vars
    @rate_details = []
    @rate_tiers = []
    @edit[:new][:details].each_with_index do |detail, detail_index|
      rate_detail = detail[:id] ? ChargebackRateDetail.find(detail[:id]) : ChargebackRateDetail.new
      rate_detail.attributes = detail.slice(*ChargebackRateDetail::FORM_ATTRIBUTES)
      rate_detail.sub_metric = detail[:sub_metric] if rate_detail.sub_metric
      rate_detail_edit = @edit[:new][:details][detail_index]
      # C: Record the currency selected in the edit view, in my chargeback_rate_details table
      rate_detail.chargeback_rate_detail_currency_id = rate_detail_edit[:currency]
      rate_detail.chargeback_rate_detail_measure_id = rate_detail_edit[:chargeback_rate_detail_measure_id]
      rate_detail.chargeback_rate_id = @rate.id
      # Save tiers into @sb
      rate_tiers = []
      @edit[:new][:tiers][detail_index].each do |tier|
        rate_tier = tier[:id] ? ChargebackTier.find(tier[:id]) : ChargebackTier.new
        tier[:start] = Float::INFINITY if tier[:start].blank?
        tier[:finish] = Float::INFINITY if tier[:finish].blank?
        rate_tier.attributes = tier.slice(*ChargebackTier::FORM_ATTRIBUTES)
        rate_tier.chargeback_rate_detail_id = rate_detail.id
        rate_tiers.push(rate_tier)
      end
      @rate_tiers[detail_index] = rate_tiers
      @rate_details.push(rate_detail)
    end
  end

  # Set record vars for save
  def cb_assign_set_record_vars
    @edit[:set_assignments] = []
    if @edit[:new][:cbshow_typ].ends_with?("-tags")
      assigned_rates_from_all_categories = @edit[:cb_assign][:tags].values.reduce({}, :merge)
      assigned_rates_from_all_categories.each_key do |id|
        key = "#{@edit[:new][:cbshow_typ]}__#{id}"
        next if @edit[:new][key].nil? || @edit[:new][key] == "nil"
        temp = {
          :cb_rate => ChargebackRate.find(@edit[:new][key]),
          :tag     => [Classification.find(id)],
        }
        temp[:tag].push(@edit[:new][:cbshow_typ].split("-").first)
        @edit[:set_assignments].push(temp)
      end
    elsif @edit[:new][:cbshow_typ].ends_with?("-labels")
      @edit[:cb_assign][:docker_label_values_saved].each_key do |id|
        key = "#{@edit[:new][:cbshow_typ]}__#{id}"
        next if @edit[:new][key].nil? || @edit[:new][key] == "nil"
        temp = {
          :cb_rate => ChargebackRate.find(@edit[:new][key]),
          :label   => [CustomAttribute.find(id)]
        }
        temp[:label].push(@edit[:new][:cbshow_typ].split("-").first)
        @edit[:set_assignments].push(temp)
      end
    else
      @edit[:cb_assign][:cis].each_key do |id|
        key = "#{@edit[:new][:cbshow_typ]}__#{id}"
        next if @edit[:new][key].nil? || @edit[:new][key] == "nil"
        temp = {:cb_rate => ChargebackRate.find(@edit[:new][key])}
        model = if @edit[:new][:cbshow_typ] == "enterprise"
                  MiqEnterprise
                elsif @edit[:new][:cbshow_typ] == "ems_container"
                  ExtManagementSystem
                else
                  Object.const_get(@edit[:new][:cbshow_typ].camelize) rescue nil
                end

        temp[:object] = model.find(id) unless model.nil?
        @edit[:set_assignments].push(temp)
      end
    end
  end

  # Set form variables for edit
  def cb_assign_set_form_vars
    @edit = {
      :cb_rates  => {},
      :cb_assign => {},
    }
    ChargebackRate.all.each do |cbr|
      if cbr.rate_type == x_node.split('-').last
        @edit[:cb_rates][cbr.id.to_s] = cbr.description
      end
    end
    @edit[:key] = "cbassign_edit__#{x_node}"
    @edit[:new]     = HashWithIndifferentAccess.new
    @edit[:current] = HashWithIndifferentAccess.new
    @edit[:current_assignment] = ChargebackRate.get_assignments(x_node.split('-').last)
    unless @edit[:current_assignment].empty?
      @edit[:new][:cbshow_typ] = case @edit[:current_assignment][0][:object]
                                 when EmsCluster
                                   "ems_cluster"
                                 when ExtManagementSystem, ManageIQ::Providers::ContainerManager
                                   "ext_management_system"
                                 when MiqEnterprise
                                   "enterprise"
                                 when NilClass
                                   if @edit[:current_assignment][0][:tag]
                                     "#{@edit[:current_assignment][0][:tag][1]}-tags"
                                   else
                                     "#{@edit[:current_assignment][0][:label][1]}-labels"
                                   end
                                 else
                                   @edit[:current_assignment][0][:object].class.name.downcase
                                 end
    end
    if @edit[:new][:cbshow_typ]&.ends_with?("-tags")
      get_categories_all
      tag = @edit[:current_assignment][0][:tag][0]
      if tag
        @edit[:new][:cbtag_cat] = tag["parent_id"].to_s
        get_tags_all
      else
        @edit[:current_assignment] = []
      end
    elsif @edit[:new][:cbshow_typ]&.ends_with?("-labels")
      get_docker_labels_all_keys
      assigned_label = @edit[:current_assignment][0][:label][0]
      if assigned_label
        label = @edit[:cb_assign][:docker_label_keys].detect { |_key, value| value == assigned_label.name }
        label ||= @edit[:cb_assign][:docker_label_default_keys].detect { |_key, value| value == assigned_label.name }
        @edit[:new][:cblabel_key] = label.first
        get_docker_labels_all_values(label.first)
      else
        @edit[:current_assignment] = []
      end
    elsif @edit[:new][:cbshow_typ]
      get_cis_all
    end

    @edit[:current_assignment].each do |el|
      if el[:object]
        @edit[:new]["#{@edit[:new][:cbshow_typ]}__#{el[:object]["id"]}"] = el[:cb_rate]["id"].to_s
      elsif el[:tag]
        @edit[:new]["#{@edit[:new][:cbshow_typ]}__#{el[:tag][0]["id"]}"] = el[:cb_rate]["id"].to_s
      elsif el[:label]
        @edit[:new]["#{@edit[:new][:cbshow_typ]}__#{el[:label][0].id}"] = el[:cb_rate]["id"].to_s
      end
    end

    @edit[:current] = copy_hash(@edit[:new])
    session[:edit] = @edit
    @in_a_form = true
  end

  def new_rate_edit?
    params[:id] == 'new' || params[:pressed] == 'chargeback_rates_new'
  end

  def get_categories_all
    @edit[:cb_assign][:cats] = {}
    Classification.categories.select { |c| c.show && !c.entries.empty? }.each do |c|
      @edit[:cb_assign][:cats][c.id.to_s] = c.description
    end
  end

  def get_tags_all
    @edit[:cb_assign][:tags] ||= {}

    Classification.all.each do |category|
      @edit[:cb_assign][:tags][category.id] ||= {}
      category.entries.each do |entry|
        @edit[:cb_assign][:tags][category.id][entry.id.to_s] = entry.description
      end
    end
  end

  DEFAULT_CHARGEBACK_LABELS = ["com.redhat.component"].freeze

  def get_docker_labels_all_keys
    @edit[:cb_assign][:docker_label_keys] = {}
    @edit[:cb_assign][:docker_label_default_keys] = {}
    CustomAttribute.where(:section => "docker_labels").pluck(:id, :name).uniq(&:second).each do |label|
      if DEFAULT_CHARGEBACK_LABELS.include?(label.second)
        @edit[:cb_assign][:docker_label_default_keys][label.first.to_s] = label.second
      else
        @edit[:cb_assign][:docker_label_keys][label.first.to_s] = label.second
      end
    end
  end

  def get_docker_labels_all_values(label_id)
    @edit[:cb_assign][:docker_label_values] = {}
    @edit[:cb_assign][:docker_label_values_saved] = {}

    CustomAttribute.where(:section => "docker_labels").pluck(:id, :value).each do |label|
      @edit[:cb_assign][:docker_label_values_saved][label.first.to_s] = label.second
    end

    return if label_id && label_id == 'null' || label_id.nil?

    label_name = CustomAttribute.find(label_id).name

    CustomAttribute.where(:section => "docker_labels", :name => label_name).pluck(:id, :value).uniq(&:second).each do |label|
      @edit[:cb_assign][:docker_label_values][label.first.to_s] = label.second
    end
  end

  WHITELIST_INSTANCE_TYPE = %w[enterprise storage ext_management_system ems_cluster tenant ems_container].freeze
  NOTHING_FORM_VALUE = "nil".freeze

  def get_cis_all
    @edit[:cb_assign][:cis] = {}
    klass = @edit[:new][:cbshow_typ]
    return if klass == NOTHING_FORM_VALUE || klass.nil? # no rate was selected
    unless WHITELIST_INSTANCE_TYPE.include?(klass)
      raise ArgumentError, "Received: #{klass}, expected one of #{WHITELIST_INSTANCE_TYPE}"
    end
    all_of_classtype =
      if klass == "enterprise"
        MiqEnterprise.all
      elsif klass == "ext_management_system"
        ExtManagementSystem.all
      else
        klass.classify.constantize.all
      end
    @edit[:cb_assign][:hierarchy] ||= {}
    all_of_classtype.each do |instance|
      @edit[:cb_assign][:cis][instance.id] = instance.name
      if klass == "ems_cluster"
        provider_name = instance.ext_management_system.name
        @edit[:cb_assign][:cis][instance.id] = "#{provider_name}/#{instance.name}"
      end
      next unless klass == "tenant" && instance.root?
      @edit[:cb_assign][:hierarchy][instance.id] = {}
      @edit[:cb_assign][:hierarchy][instance.id][:name] = instance.name
      @edit[:cb_assign][:hierarchy][instance.id][:subtenant] = instance.build_tenant_tree
    end
  end

  def cb_assign_params_to_edit(cb_assign_key, tag_category_id = nil)
    current_assingments = cb_assign_key == :tags ? @edit[:cb_assign][cb_assign_key].try(:[], tag_category_id) : @edit[:cb_assign][cb_assign_key]

    return unless current_assingments
    current_assingments.each_key do |id|
      key = "#{@edit[:new][:cbshow_typ]}__#{id}"
      @edit[:new][key] = params[key].to_s if params[key]
    end
  end

  # Get variables from edit form
  def cb_assign_get_form_vars
    @edit[:new][:cbshow_typ] = params[:cbshow_typ] if params[:cbshow_typ]
    @edit[:new][:cbtag_cat] = nil if params[:cbshow_typ] # Reset categories pull down if assign to selection is changed
    @edit[:new][:cbtag_cat] = params[:cbtag_cat].to_s if params[:cbtag_cat]
    @edit[:new][:cblabel_key] = nil if params[:cbshow_typ]
    @edit[:new][:cblabel_key] = params[:cblabel_key].to_s if params[:cblabel_key]

    if @edit[:new][:cbshow_typ].ends_with?("-tags")
      get_categories_all
      get_tags_all
    elsif @edit[:new][:cbshow_typ].ends_with?("-labels")
      get_docker_labels_all_keys
      get_docker_labels_all_values(@edit[:new][:cblabel_key])
    else
      get_cis_all
    end

    cb_assign_params_to_edit(:cis)
    cb_assign_params_to_edit(:tags, @edit[:new][:cbtag_cat].try(:to_i))
    cb_assign_params_to_edit(:docker_label_values)
  end

  def replace_right_cell(options = {})
    replace_trees = Array(options[:replace_trees])
    replace_trees = @replace_trees if @replace_trees # get_node_info might set this
    @explorer = true
    c_tb = build_toolbar(center_toolbar_filename)

    # Build a presenter to render the JS
    presenter = ExplorerPresenter.new(:active_tree => x_active_tree)
    reload_trees_by_presenter(presenter, [cb_rates_build_tree]) if replace_trees.include?(:cb_rates)

    # FIXME
    #  if params[:action].ends_with?("_delete")
    #    page << "miqTreeActivateNodeSilently('#{x_active_tree.to_s}', '<%= x_node %>');"
    #  end
    # presenter[:select_node] = x_node if params[:action].ends_with?("_delete")
    presenter[:osf_node] = x_node

    case x_active_tree
    when :cb_rates_tree
      # Rates accordion
      if c_tb.present?
        presenter.reload_toolbars(:center => c_tb)
      end
      presenter.set_visibility(c_tb.present?, :toolbar)
      presenter.update(:main_div, r[:partial => 'rates_tabs'])
    when :cb_assignments_tree
      # Assignments accordion
      presenter.update(:main_div, r[:partial => "assignments_tabs"])
    when :cb_reports_tree
      if c_tb.present?
        presenter.reload_toolbars(:center => c_tb)
        presenter.show(:toolbar)
      else
        presenter.hide(:toolbar)
      end
      presenter.update(:main_div, r[:partial => 'reports_list'])
      if @html
        presenter.update(:paging_div, r[:partial => 'layouts/saved_report_paging_bar',
                                        :locals  => @sb[:pages]])
        presenter.show(:paging_div)
      else
        presenter.hide(:paging_div)
      end
    end

    if @record || @in_a_form ||
       (@pages && (@items_per_page == ONE_MILLION || @pages[:items] == 0))
      if %w[chargeback_rates_copy chargeback_rates_edit chargeback_rates_new].include?(@sb[:action]) ||
         (x_active_tree == :cb_assignments_tree && %w[Compute Storage].include?(x_node.split('-').last))
        presenter.hide(:toolbar)
        # incase it was hidden for summary screen, and incase there were no records on show_list
        presenter.show(:paging_div, :form_buttons_div).remove_paging
        locals = {:record_id => @edit[:rec_id]}
        if x_active_tree == :cb_rates_tree
          locals[:action_url] = 'cb_rate_edit'
        else
          locals.update(
            :action_url   => 'cb_assign_update',
            :no_cancel    => true,
            :multi_record => true,
          )
        end
        presenter.update(:form_buttons_div, r[:partial => 'layouts/x_edit_buttons', :locals => locals])
      else
        # Added so buttons can be turned off even tho div is not being displayed it still pops up Abandon changes box when trying to change a node on tree after saving a record
        presenter.hide(:buttons_on).show(:toolbar).hide(:paging_div)
        presenter.hide(:form_buttons_div) if params[:button]
      end
    else
      presenter.hide(:form_buttons_div)
      if (x_active_tree == :cb_assignments_tree && x_node == "root") ||
         (x_active_tree == :cb_reports_tree && !@report) ||
         (x_active_tree == :cb_rates_tree && x_node == "root")
        presenter.hide(:toolbar).remove_paging
      end
      presenter.show(:paging_div)
    end

    presenter[:record_id] = determine_record_id_for_presenter

    presenter[:clear_gtl_list_grid] = @gtl_type && @gtl_type != 'list'

    presenter[:right_cell_text]     = @right_cell_text
    unless x_active_tree == :cb_assignments_tree
      presenter[:lock_sidebar] = @in_a_form && @edit
    end

    presenter.update(:breadcrumbs, r[:partial => 'layouts/breadcrumbs'])

    render :json => presenter.for_render
  end

  def get_session_data
    super
    @current_page = session[:chargeback_current_page]
  end

  def set_session_data
    super
    session[:chargeback_current_page] = @current_page
  end

  def display_detail_errors(detail, errors)
    errors.each { |field, msg| add_flash("'#{detail.chargeable_field.description}' #{field.to_s.humanize.downcase} #{msg}", :error) }
  end

  def add_row(i, pos, code_currency)
    locals = {:code_currency => code_currency}
    render :update do |page|
      page << javascript_prologue
      # Update the first row to change the colspan
      page.replace("rate_detail_row_#{i}_0",
                   :partial => "tier_first_row",
                   :locals  => locals)
      # Insert the new tier after the last one
      page.insert_html(:after,
                       "rate_detail_row_#{i}_#{pos}",
                       :partial => "tier_row",
                       :locals  => locals)
      page << javascript_for_miq_button_visibility(true)
    end
  end

  def breadcrumbs_options
    {
      :breadcrumbs => [
        {:title => _("Overview")},
        {:title => _("Chargebacks")},
      ],
    }
  end

  menu_section :vi
end

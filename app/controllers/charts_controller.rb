class ChartsController < ApplicationController

  unloadable

  menu_item :charts

  before_filter :find_project, :authorize, :only => [:index]
  
  Y_STEPS = 5
  X_STEPS = 5

  # Show main page with conditions form and chart
  def index
    if show_conditions
      @grouping_options = get_grouping_options.collect { |i| [l("charts_group_by_#{i}".to_sym), i]  }
      @conditions_options = get_conditions_options.collect do |i|
        case i
        when :user_id then [:user_id, Project.find(params[:project_id]).assignable_users.collect { |u| [u.login, u.id] }.unshift([l(:charts_condition_all), 0])]      
        when :issue_id then [:issue_id, nil]
        when :activity_id then [:activity_id, Enumeration.get_values("ACTI").collect { |a| [a.name.downcase, a.id] }.unshift([l(:charts_condition_all), 0])]
        when "issues.category_id".to_sym then ["issues.category_id".to_sym, IssueCategory.find_all_by_project_id(Project.find(params[:project_id]).id).collect { |c| [c.name.downcase, c.id] }.unshift([l(:charts_condition_all), 0])]
        end
      end
      @date_condition = show_date_condition
      @show_conditions = true
    else
      @show_conditions = false
    end
    @help = get_help
    
    render :template => "charts/index"
  end

  # Return data for chart
  def data
    chart =OpenFlashChart.new
    
    conditions, grouping, range = prepare_params

    x_labels, x_count, y_max, sets = get_data(conditions, grouping, range)

    index = 0

    type = get_module_type

    sets.each do |name,values|
      chart.add_element(type.prepare_data(index,name,values,x_labels))
      index += 1
    end
    
    unless get_title.nil?
      title = Title.new(get_title)
      chart.set_title(title)
    end

    if show_y_axis
      y = YAxis.new
      y.set_range(0,y_max*1.2,y_max/Y_STEPS) if y_max
      chart.y_axis = y
    end

    if show_x_axis
      x = XAxis.new
      x.set_range(0,x_count,1) if x_count
      if x_labels        
        labels = []         
        step = (x_labels.size / X_STEPS).to_i
        step = 1 if step == 0
        x_labels.each_with_index do |l,i|          
          if i % step == 0
            labels << l
          else 
            labels << ""
          end
        end
        x.set_labels(labels) 
      end
      chart.x_axis = x
    else
      x = XAxis.new
      x.set_labels([""])
      chart.x_axis = x
    end

    unless get_x_legend.nil?
      x_legend = XLegend.new(get_x_legend)
      x_legend.set_style('{font-size: 12px}')
      chart.set_x_legend(x_legend)
    end
    
    unless get_x_legend.nil?
      y_legend = YLegend.new(get_y_legend)
      y_legend.set_style('{font-size: 12px}')
      chart.set_y_legend(y_legend)
    end

    chart.set_bg_colour('#ffffff');

    render :text => chart.to_s
  end

  protected

  def get_type
    "line_dot"
  end

  def get_help
    nil
  end
  
  def get_title
    nil
  end
  
  def get_data
    raise "overwrite it"
  end
  
  def get_global_hints
    nil
  end
  
  def get_hints
    nil
  end
  
  def get_x_legend
    nil
  end
  
  def get_y_legend
    nil
  end
  
  def show_x_axis
    false
  end
  
  def show_y_axis
    false
  end

  def show_conditions
    true
  end
  
  def show_date_condition
    false
  end
    
  def get_grouping_options
    [ :users, :issues, :activities, :categories ]
  end
  
  def get_conditions_options
    [ :user_id, :issue_id, :activity_id, "issues.category_id".to_sym ]
  end

  def count_range(range, first_time)
    case range[:in]
    when :weeks
      strftime_i = "%W"
      items_in_year = 52
    when :months
      strftime_i = "%m"
      items_in_year = 12
    else
      strftime_i = "%j"
      items_in_year = 366
    end

    first = first_time.strftime(strftime_i).to_i + first_time.strftime('%Y').to_i * items_in_year
    now = Time.now.strftime(strftime_i).to_i + Time.now.strftime('%Y').to_i * items_in_year

    range[:steps] = now - first + 4
    range[:offset] = 1
    range
  end

  def prepare_range(range, column = "created_on")
    case range[:in]
    when :weeks
      strftime_i = "%W"
      strftime_f = "%Y-%W"
    when :months
      strftime_i = "%m"
      strftime_f = "%Y-%m"
    else
      strftime_i = "%j"
      strftime_f = "%Y-%m-%d"
    end

    from = times_ago(range[:steps],range[:offset],0,range[:in])
    to = times_ago(range[:steps],range[:offset]-1,0,range[:in])

    dates = []
    x_labels = []

    range[:steps].times do |i|
      x_labels[i] = times_ago(range[:steps],range[:offset],i,range[:in]).strftime(strftime_f)
      dates[i] = times_ago(range[:steps],range[:offset],i+1,range[:in])
    end

    diff = from.strftime(strftime_i).to_i + from.strftime('%Y').to_i
    #sql = RedmineCharts::DateFormat.format_date(range[:in], column, diff)
    sql = ActiveRecord::Base.format_date(range[:in], column, diff)

    [from, to, x_labels, range[:steps], sql, dates]
  end

  def get_sets(rows, grouping, x_count, flat = false)
    if rows.empty?
      [nil, {}]
    end

    sets = {}
    y_max = 0
    i = -1

    rows.each do |r|
      if flat
        group_name = ""
      else
        group_name = group_id_to_string(r.group_id, grouping)
      end
      sets[group_name] ||= Array.new(x_count, [0, get_hints])

      if r.value_x
        i = r.value_x.to_i
      else
        i += 1
      end

      sets[group_name][i] = [r.value_y.to_i, get_hints(r, grouping)]
      y_max = r.value_y.to_i if y_max < r.value_y.to_i
    end

    [y_max, sets]
  end

  def group_id_to_string(group_id, grouping)
    group_name = group_id
    group_name = IssueCategory.find_by_id(group_id.to_i).name if grouping == :categories and IssueCategory.find_by_id(group_id.to_i)
    group_name = User.find_by_id(group_id.to_i).login if grouping == :users and User.find_by_id(group_id.to_i)
    group_name = Issue.find_by_id(group_id.to_i).subject if grouping == :issues and Issue.find_by_id(group_id.to_i)
    group_name = Enumeration.find_by_id(group_id.to_i).name if grouping == :activities and Enumeration.find_by_id(group_id.to_i)
    group_name
  end

  private

  def get_module_type
    eval("RedmineCharts::DataFor#{get_type.to_s.camelize}")
  end

  def find_project
    @project = Project.find(params[:project_id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def prepare_params
    range = {:steps => 10, :offset => 1, :in => :days}
    range[:steps] = Integer(params[:range_steps]) unless params[:range_steps].blank?
    range[:steps] = 0 if params[:range_steps] and params[:range_steps].blank?
    range[:offset] = Integer(params[:range_offset]) unless 
    range[:in] = params[:range_in].to_sym unless params[:range_in].blank?
    
    conditions = {:project_id => Project.find(params[:project_id]).id}
    get_conditions_options.each do |k|
      t = params["conditions_#{k.to_s}".to_sym].blank? ? nil :Integer(params["conditions_#{k.to_s}".to_sym])
      conditions[k] = t if t and t > 0
    end    
    
    grouping = params[:grouping].blank? ? nil : params[:grouping].to_sym
    
    [conditions, grouping, range]
  end


  def times_ago(steps, offset, i, type)
    ((steps*offset)-i-1).send(type).ago
  end
  
end

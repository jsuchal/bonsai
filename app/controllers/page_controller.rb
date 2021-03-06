class PageController < ApplicationController
  before_filter :load_page, :except => [:add_lock, :update_locked]
  before_filter :can_manage_page_check, :only => [:manage, :change_permission, :set_permissions, :remove_permission, :switch_public, :switch_editable]
  before_filter :can_edit_page_check, :only => [:edit, :update, :upload, :undo, :new_part, :files]
  prepend_before_filter :slash_check, :only => [:view]
  before_filter :can_view_page_check, :only => [:view, :history, :revision, :diff, :toggle_favorite]
  before_filter :is_file, :only => [:view]
  before_filter :is_blank_page, :only => [:view]

  def rss
    user_from_token = User.find_by_token params[:token]
    user_from_token = AnonymousUser.new(session) if user_from_token.nil?
    if user_from_token.can_view_page? @page
      rss_history
    else
      render :nothing => true, :status => :forbidden
    end
  end

  def view
    #unless session[:link_back].nil? then session[:link_back]= nil end
    @hide_view_in_toolbar = true
    layout = @page.nil? ? 'application' : @page.resolve_layout
    render :action => :view, :layout => layout
  end

  def unprivileged
    @hide_view_in_toolbar = true
    render :action => :unprivileged
  end

  def history
    render :action => :show_history
  end

  def diff
    page = PageAtRevision.find_by_path(@path)

    first_revision = params[:first_revision]
    second_revision = params[:second_revision]
    if (first_revision.to_i < second_revision.to_i)
      first = second_revision
      second = first_revision
    else
      second = second_revision
      first = first_revision
    end

    revision1 = page.page_parts_revisions[first.to_i].id
    old_revision = ""
    for part in page.page_parts
      revision = part.page_part_revisions.first(:conditions => ["id <= ?", revision1])
      unless revision.nil? or revision.was_deleted?
        old_revision << revision.body << "\n"
      end
    end

    new_revision = ""
    revision2 = page.page_parts_revisions[second.to_i].id
    for part in page.page_parts
      revision = part.page_part_revisions.first(:conditions => ["id <= ?", revision2])
      unless revision.nil? or revision.was_deleted?
        new_revision << revision.body << "\n"
      end
    end
    @changes = SimpleDiff.diff(old_revision, new_revision)
    render :action => 'diff'
  end

  def revision
    @page = PageAtRevision.find_by_path(@path)

    revision_date = @page.page_parts_revisions[params[:revision].to_i].created_at
    @page.revision_date = revision_date
    @page_parts = Array.new

    for part in @page.page_parts
      current_part = part.page_part_revisions.find(:first, :conditions => ['created_at <= ?', revision_date])
      @page_parts << current_part if current_part
    end
    layout = @page.nil? ? 'application' : @page.resolve_layout

    render :action => 'show_revision', :layout => layout
  end

  def undo
    @page_revision = @page.page_parts_revisions[params[:revision].to_i]
    @page_part = @page_revision.page_part
    @undo = true
    render :action => 'edit'
  end

  def switch_public
    was_public = @page.is_public?
    if (@page.parent.nil? || @page.parent.is_public?)
      @page.page_permissions.each do |permission|
        permission.can_view = was_public
        permission.can_edit = was_public if was_public
        #TODO: if the @page has some public descendants, we should spread the switch to them as well
        permission.save
      end
    end
    redirect_to manage_page_path(@page)
  end

  def switch_editable
    was_editable = @page.is_editable?
    if (@page.parent.nil? || @page.parent.is_public?)
      @page.page_permissions.each do |permission|
        permission.can_view = was_editable if !was_editable
        permission.can_edit = was_editable
        #TODO: if the @page has some public descendants, we should spread the switch to them as well
        permission.save
      end
    end
    redirect_to manage_page_path(@page)
  end

  def change_permission
    page_permission = @page.page_permissions[params[:index].to_i]
    if (params[:permission] == "can_view")
      if (page_permission.group.users.include? @current_user)
        flash[:notice] = t(:can_view_error)
      else
        page_permission.can_view ? @page.remove_viewer(page_permission.group):@page.add_viewer(page_permission.group)
      end
    elsif (params[:permission] == "can_edit")
      if (page_permission.group.users.include? @current_user)
        flash[:notice] = t(:can_edit_error)
      else
        page_permission.can_edit ? @page.remove_editor(page_permission.group):@page.add_editor(page_permission.group)
      end
    elsif (params[:permission] == "can_manage")
      page_permission.can_manage ? @page.remove_manager(page_permission.group):@page.add_manager(page_permission.group)
    end
    page_permission.save
    redirect_to manage_page_path(@page)
  end

  def remove_permission
    page_permission = @page.page_permissions[params[:index].to_i]
    page_permission.destroy
    redirect_to manage_page_path(@page)
  end

  def process_file
    @no_toolbar = true
    file_name = 'shared/upload/' + @path.join('/')
    parent_page_path = @path.clone
    @filename = parent_page_path.pop
    @page = Page.find_by_path(parent_page_path)

    if params.include? 'upload' then
      upload and return
    end
    return render(:action => :file_not_found) unless File.file?(file_name)

    if @current_user.can_view_page? @page
      return send_file(file_name)
    else
      return render(:action => :unprivileged)
    end
  end

  def new
    if @path.empty?
      @parent_id = nil
    else
      parent_path = Array.new @path
      parent_path.pop
      parent = Page.find_by_path(parent_path)
      render :action => 'no_parent' and return if parent.nil?
      @parent_id = parent.id
    end
    if (!@parent_id.nil? && !(@current_user.can_edit_page? Page.find_by_id(@parent_id)))
      unprivileged
    else
      @sid = @path.empty? ? nil : @path.last
      render :action => 'new'
    end
  end

  def create
    parent = nil
    unless params[:parent_id].blank?
      parent = Page.find_by_id(params[:parent_id])
      # TODO check if exists
    end

    if (!parent.nil? && !(@current_user.can_edit_page? parent))
      unprivileged
    else
      sid = params[:sid].blank? ? nil : params[:sid]
      layout = params[:layout].empty? ? nil : params[:layout]
      page = Page.new(:title => params[:title], :sid => sid, :layout => layout)
      unless (page.valid?)
        error_message = ""
        page.errors.each_full { |msg| error_message << msg }
        flash[:notice] = error_message
        render :action => "new"
        return
      end
      page.save!
      page.add_manager @current_user.private_group
      page.move_to_child_of parent unless parent.nil?
      page_part = page.page_parts.create(:name => "body", :current_page_part_revision_id => 0)
      first_revision = page_part.page_part_revisions.create(:user => @current_user, :body => params[:body], :summary => params[:summary])
      unless (first_revision.valid?)
        error_message = ""
        first_revision.errors.each_full { |msg| error_message << msg }
        flash[:notice] = error_message
        @body = first_revision.body
        @sid = sid
        @parent_id = params[:parent_id]
        page_part.delete
        page.delete
        render :action => "new"
        return
      end
      if (first_revision.save)
        flash[:notice] = t(:page_created)
        page_part.current_page_part_revision = first_revision
        page_part.save!
      end
      redirect_to page.get_path
    end
  end

  def show_history
  end

  def rss_history
    @recent_revisions = PagePartRevision.find(:all, :include => [:page_part, :user], :conditions => ["page_parts.page_id = ?", @page.id], :limit => 10, :order => "created_at DESC")
    @revision_count = @page.page_parts_revisions.count
    render :action => :rss_history, :layout => false
  end


  def edit
    render :action => :edit
  end

  def set_permissions
    addedgroups = params[:add_group].split(",")
    for addedgroup in addedgroups
      groups = Group.find_all_by_name(addedgroup)
      for group in groups
        users = group.users
        retVal = group.is_public?
        retValUsers = users.include?(@current_user)
        if (retVal || retValUsers)
          @page.add_viewer group if params[:group_role][:type] == 'viewer'
          @page.add_editor group if params[:group_role][:type] == 'editor'
          @page.add_manager group if params[:group_role][:type] == 'manager'
        end
      end
    end
    redirect_to manage_page_path(@page)
  end

  def update
    @num_of_changed_page_parts = 0
    @page.title = params[:title]
    if @current_user.can_manage_page? @page
      @page.layout = params[:layout].empty? ? nil : params[:layout]
    end

    @page.save
    params[:parts].each do |part_name, body|

      page_part = PagePart.find_by_name_and_page_id(part_name, @page.id)
      PagePartLock.delete_lock(page_part.id, @current_user)
      new_part_name = params["parts_name"][part_name]

      edited_revision_id = params["parts_revision"][part_name]
      delete_part = params[:is_deleted].blank? ? false : !params[:is_deleted][part_name].blank?

      edited_revision = page_part.page_part_revisions.find(:first, :conditions => {:id => edited_revision_id})

      #for each page_part we check if there was not created newer revision
      newest_revisions = page_part.page_part_revisions.first(:conditions => {:page_part_id => page_part.id})

      if (newest_revisions.id > edited_revision_id.to_i)
        @num_of_changed_page_parts += 1
      end

      # update if part name changed
      if new_part_name != part_name
        # TODO validation?
        page_part.name = new_part_name
        page_part.save
      end

      # create new revision if
      # part body was edited
      # or current revision deletion status is different # TODO ok?
      if edited_revision.body != body or page_part.current_page_part_revision.was_deleted != delete_part
        revision = page_part.page_part_revisions.create(:user => @current_user, :body => body, :summary => params[:summary], :was_deleted => delete_part)
        unless (revision.valid?)
          error_message = ""
          revision.errors.each_full { |msg| error_message << msg }
          @page_part = page_part
          @page_revision = revision
          flash[:error] = error_message
          render :action => "edit"
          return true
        end
        revision.save!
        page_part.current_page_part_revision = revision
        page_part.name = new_part_name
        page_part.save!
      end
    end
    
    if @num_of_changed_page_parts > 0 then
      flash[:notice] = t(:page_updated_with_new_revisions)
    else
      flash[:notice] = t(:page_updated)
    end
    redirect_to @page.get_path
  end


  def new_part
    page_part = @page.page_parts.find_or_create_by_name(:name => params[:new_page_part_name], :current_page_part_revision_id => 0)
    unless page_part.valid?
      error_message = ""
      page_part.errors.each_full { |msg| error_message << msg }
      flash[:error] = error_message
      render :action => "edit"
      return true
    end
    page_part_revision = page_part.page_part_revisions.create(:user => @current_user, :body => params[:new_page_part_text], :summary => "init")
    page_part_revision.save
    page_part.current_page_part_revision = page_part_revision
    page_part.save!
    flash[:notice] = t(:page_part_added)
    redirect_to edit_page_path(@page)
  end

  def upload
    @name = params[:uploaded_file_filename]
    tmp_file = UploadedFile.new(params[:uploaded_file])
    if @name.nil?
      @uploaded_file = UploadedFile.find_by_filename_and_page_id(tmp_file.filename, @page.id)
    else
      @uploaded_file = UploadedFile.find_by_filename_and_page_id(@name, @page.id)
    end
    if @uploaded_file.nil?
      @uploaded_file = tmp_file
    else
      @uploaded_file.temp_path = tmp_file.temp_path
    end
    sleep(2) # TODO get rid of this    

    if @uploaded_file.filename.nil?
      flash[:notice] = t(:no_files_selected)
      redirect_to @page.get_path
    else

#      if @uploaded_file.exist?(@page.get_path)
#        flash[:notice] = t(:file_exists)
#        redirect_to @page.get_path
#      else

      if !@name.nil? && File.extname(@name) != File.extname(@uploaded_file.filename)
        flash[:notice] = t(:file_not_match)
        redirect_to @page.get_path
      else
        @uploaded_file.page = @page
        @uploaded_file.user = @current_user
        @uploaded_file.rename(@name) unless @name.nil?
        same_page = @path
        same_page.push(@uploaded_file.filename)
        if Page.find_by_path(same_page).nil?
          if @uploaded_file.save
            flash[:notice] = t(:file_uploaded)
            redirect_to @page.get_path
          else
            error_message = ""
            @uploaded_file.errors.each_full { |msg| error_message << msg }
            flash[:notice] = error_message
            render :action => :edit
          end
        else
          flash[:notice] = t(:same_as_page)
          render :action => :edit
        end
      end

      #end

    end

  end

  def files
    render :action => :files
  end

  def toggle_favorite
    active = @current_user.favorite_pages.include?(@page)
    if active
      @current_user.favorite_pages.delete(@page)
    else
      @current_user.favorites.create(:page => @page)
    end

    respond_to do |format|
      format.js do
        render :update do |page|
          page.replace_html 'favorite', :partial => 'shared/favorite'
        end
      end
      format.html { redirect_to @page.get_path }
    end
  end

  def add_lock
   @add_part_id = params[:part_id]
   @add_part_name = PagePart.find(@add_part_id).name
   @editedbyanother = PagePartLock.check_lock?(@add_part_id, @current_user)
   if !@editedbyanother then
      PagePartLock.create_lock(@add_part_id, @current_user)
   end

  end

  def update_lock
   @up_part_id = params[:part_id]
   PagePartLock.create_lock(@up_part_id, @current_user)
  end


  private
  def load_page
    @path = params[:path]
    @page = Page.find_by_path(@path)
    unless session[:link_back].nil? then session[:link_back]= nil end
  end

  def can_manage_page_check
    unprivileged unless @current_user.can_manage_page?(@page)
  end

  def can_edit_page_check
    unprivileged unless @current_user.can_edit_page?(@page)
  end

  def can_view_page_check
    unprivileged unless @page.nil? or @current_user.can_view_page?(@page)
  end

  def slash_check
    link = request.env['PATH_INFO']
    unless link.ends_with?('/')
      redirect_to link + '/'
      return
    end
  end

  def is_file
    # is it a file?
    if !@path.empty? and (@path.last.match(/[\w-]+\.\w+/) or File.file?("shared/upload/" + @path.join('/')))
      process_file
      return
    end
  end

  def is_blank_page
    if @page.nil?
      unless @current_user.logged?
        unprivileged
      else
        params.include?('create') ? create : new
      end
      return
    end
  end
end

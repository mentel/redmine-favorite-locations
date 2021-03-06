require 'mechanize'

class FavoriteLocationsController < ApplicationController
  unloadable

  before_filter :check_user, :only => [:edit, :update, :destroy]
  before_filter :render_empty_if_anonymous

  def index
    @locations = FavoriteLocation.for_user(User.current)
    @no_edit_favorite_locations = params[:no_edit_favorite_locations]
    render :json => {
      :action => :index,
      :html => render_to_string(:partial => 'index')
    }
  end

  def new
    @location = FavoriteLocation.new
    @location.user_id = User.current.id
    render :json => {
      :action => :new,
      :html => render_to_string(:partial => 'form')
    }
  end

  def edit
    render :json => {
      :action => :edit,
      :html => render_to_string(:partial => 'form')
    }
  end

  def create
    @location = FavoriteLocation.new(params[:favorite_location].except(:user_id)) do |loc|
      loc.user_id = User.current.id
    end
    if @location.save
      if params[:favorite_location][:page_title].blank?
        # non-threaded server
        if defined?(Unicorn)
          scrape_url
        # guessing that it's threaded
        else
          new_thread { scrape_url }
        end
      end
      render :json => {
        :action => :create,
        :html => render_to_string(:partial => 'show')
      }
    else
      render :json => {}, :status => 500
    end
  end

  def destroy
    if @location.destroy
      render :json => { :action => :destroy, :html => '' }
    else
      render :json => {}, :status => 500
    end
  end

  def update
    if @location.update_attributes(params[:favorite_location].except(:user_id))
      render :json => {
        :action => :update,
        :html => render_to_string(:partial => 'show')
      }
    else
      render :json => {}, :status => 500
    end
  end

  protected

  def check_user
    @location = FavoriteLocation.find_by_id(params[:id])
    if @location.blank? || @location.user != User.current
      flash[:error] = "can't update another user's favorite location"
      redirect_to(:action => :index)
    end
  end

  def render_empty_if_anonymous
    return unless User.current.anonymous?
    render :json => {}
  end

  def new_thread
    Thread.new do
      sleep 3
      yield
      ActiveRecord::Base.connection.disconnect!
      ActiveRecord::Base.connection.close
    end
  end

  def scrape_url
    begin
      url = File.join("#{request.scheme}://#{request.host}:#{request.port}/", @location.link_path)
      logger.info "URL: #{url}"
      agent = Mechanize.new
      agent.redirect_ok = false
      cookie_uri = URI.parse("#{request.scheme}://#{request.host}")
      request.cookie_jar.to_a.each do |(key, val)|
        cookie = Mechanize::Cookie.new(key, val)
        cookie.domain = ".#{request.domain}"
        cookie.path = '/'
        agent.cookie_jar.add(cookie_uri, cookie)
      end
      page = agent.get(url)
    rescue => e
      logger.error e
      page = nil
    end
    if page.present? && page.title.present?
      @location.update_attributes(:page_title => page.title)
    end
  end

end
